use async_trait::async_trait;
use codex_protocol::user_input::UserInput;
use serde::Deserialize;
use std::env;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;
use uuid::Uuid;
use which::which;

use crate::function_tool::FunctionCallError;
use crate::protocol::EventMsg;
use crate::protocol::ViewImageToolCallEvent;
use crate::tools::context::ToolInvocation;
use crate::tools::context::ToolOutput;
use crate::tools::context::ToolPayload;
use crate::tools::registry::ToolHandler;
use crate::tools::registry::ToolKind;

const TARGET_WIDTH: f64 = 1280.0;
const TARGET_HEIGHT: f64 = 720.0;
const DEFAULT_SCROLL_TICKS: u32 = 3;

pub struct ComputerUseHandler;

#[derive(Deserialize)]
struct ClickArgs {
    x: f64,
    y: f64,
    button: Option<String>,
    double: Option<bool>,
}

#[derive(Deserialize)]
struct DragArgs {
    from_x: f64,
    from_y: f64,
    to_x: f64,
    to_y: f64,
    button: Option<String>,
}

#[derive(Deserialize)]
struct ScrollArgs {
    direction: String,
    amount: Option<u32>,
    x: Option<f64>,
    y: Option<f64>,
}

#[derive(Deserialize)]
struct TypeArgs {
    text: String,
    delay_ms: Option<u64>,
}

#[derive(Deserialize)]
struct KeyArgs {
    keys: Vec<String>,
    confirm: Option<bool>,
}

#[async_trait]
impl ToolHandler for ComputerUseHandler {
    fn kind(&self) -> ToolKind {
        ToolKind::Function
    }

    async fn is_mutating(&self, invocation: &ToolInvocation) -> bool {
        invocation.tool_name != "computer_screenshot"
    }

    async fn handle(&self, invocation: ToolInvocation) -> Result<ToolOutput, FunctionCallError> {
        let ToolInvocation {
            session,
            turn,
            payload,
            call_id,
            tool_name,
            ..
        } = invocation;

        let ToolPayload::Function { arguments } = payload else {
            return Err(FunctionCallError::RespondToModel(format!(
                "unsupported payload for {tool_name}"
            )));
        };

        ensure_display()?;

        match tool_name.as_str() {
            "computer_screenshot" => {
                let image_path = capture_screenshot()?;
                session
                    .inject_input(vec![UserInput::LocalImage {
                        path: image_path.clone(),
                    }])
                    .await
                    .map_err(|_| {
                        FunctionCallError::RespondToModel(
                            "unable to attach screenshot (no active task)".to_string(),
                        )
                    })?;

                session
                    .send_event(
                        turn.as_ref(),
                        EventMsg::ViewImageToolCall(ViewImageToolCallEvent {
                            call_id,
                            path: image_path.clone(),
                        }),
                    )
                    .await;

                let display = image_path.display();
                Ok(ToolOutput::Function {
                    content: format!("captured screenshot at {display}"),
                    content_items: None,
                    success: Some(true),
                })
            }
            "computer_click" => {
                let args: ClickArgs = parse_args(&arguments)?;
                let xdotool = require_command("xdotool")?;
                let (screen_w, screen_h) = display_geometry(&xdotool)?;
                let (x, y) = scale_point(args.x, args.y, screen_w, screen_h);
                let button = mouse_button(args.button)?;
                let mut cmd = vec![
                    "mousemove".to_string(),
                    "--sync".to_string(),
                    x.to_string(),
                    y.to_string(),
                    "click".to_string(),
                    button.clone(),
                ];
                if args.double.unwrap_or(false) {
                    cmd.extend(["click".to_string(), button]);
                }
                run_command(&xdotool, &cmd)?;
                Ok(ToolOutput::Function {
                    content: format!("clicked at {x},{y}"),
                    content_items: None,
                    success: Some(true),
                })
            }
            "computer_drag" => {
                let args: DragArgs = parse_args(&arguments)?;
                let xdotool = require_command("xdotool")?;
                let (screen_w, screen_h) = display_geometry(&xdotool)?;
                let (from_x, from_y) = scale_point(args.from_x, args.from_y, screen_w, screen_h);
                let (to_x, to_y) = scale_point(args.to_x, args.to_y, screen_w, screen_h);
                let button = mouse_button(args.button)?;
                let cmd = vec![
                    "mousemove".to_string(),
                    "--sync".to_string(),
                    from_x.to_string(),
                    from_y.to_string(),
                    "mousedown".to_string(),
                    button.clone(),
                    "mousemove".to_string(),
                    "--sync".to_string(),
                    to_x.to_string(),
                    to_y.to_string(),
                    "mouseup".to_string(),
                    button,
                ];
                run_command(&xdotool, &cmd)?;
                Ok(ToolOutput::Function {
                    content: format!("dragged from {from_x},{from_y} to {to_x},{to_y}"),
                    content_items: None,
                    success: Some(true),
                })
            }
            "computer_scroll" => {
                let args: ScrollArgs = parse_args(&arguments)?;
                let direction = scroll_button(&args.direction)?;
                let ticks = args.amount.unwrap_or(DEFAULT_SCROLL_TICKS).max(1);
                let xdotool = require_command("xdotool")?;
                let mut cmd = Vec::new();
                if args.x.is_some() ^ args.y.is_some() {
                    return Err(FunctionCallError::RespondToModel(
                        "computer_scroll requires both x and y when positioning the cursor"
                            .to_string(),
                    ));
                }
                if let (Some(x), Some(y)) = (args.x, args.y) {
                    let (screen_w, screen_h) = display_geometry(&xdotool)?;
                    let (mx, my) = scale_point(x, y, screen_w, screen_h);
                    cmd.extend([
                        "mousemove".to_string(),
                        "--sync".to_string(),
                        mx.to_string(),
                        my.to_string(),
                    ]);
                }
                cmd.push("click".to_string());
                if ticks > 1 {
                    cmd.push("--repeat".to_string());
                    cmd.push(ticks.to_string());
                }
                cmd.push(direction);
                run_command(&xdotool, &cmd)?;
                Ok(ToolOutput::Function {
                    content: format!("scrolled {ticks} ticks"),
                    content_items: None,
                    success: Some(true),
                })
            }
            "computer_type" => {
                let args: TypeArgs = parse_args(&arguments)?;
                let xdotool = require_command("xdotool")?;
                let mut cmd = vec!["type".to_string()];
                if let Some(delay_ms) = args.delay_ms {
                    cmd.push("--delay".to_string());
                    cmd.push(delay_ms.to_string());
                }
                cmd.push("--".to_string());
                cmd.push(args.text.clone());
                run_command(&xdotool, &cmd)?;
                let count = args.text.len();
                Ok(ToolOutput::Function {
                    content: format!("typed {count} characters"),
                    content_items: None,
                    success: Some(true),
                })
            }
            "computer_key" => {
                let args: KeyArgs = parse_args(&arguments)?;
                if requires_confirmation(&args.keys) && !matches!(args.confirm, Some(true)) {
                    return Err(FunctionCallError::RespondToModel(
                        "destructive key combo requires confirm=true after user approval"
                            .to_string(),
                    ));
                }
                let xdotool = require_command("xdotool")?;
                let combo = args.keys.join("+");
                run_command(&xdotool, &["key".to_string(), combo.clone()])?;
                Ok(ToolOutput::Function {
                    content: format!("pressed {combo}"),
                    content_items: None,
                    success: Some(true),
                })
            }
            _ => Err(FunctionCallError::RespondToModel(format!(
                "unsupported computer-use tool: {tool_name}"
            ))),
        }
    }
}

fn ensure_display() -> Result<(), FunctionCallError> {
    if !cfg!(target_os = "linux") {
        return Err(FunctionCallError::RespondToModel(
            "computer-use GUI tools are only supported on Linux/X11".to_string(),
        ));
    }
    if env::var("DISPLAY").is_err() {
        return Err(FunctionCallError::RespondToModel(
            "DISPLAY is not set; GUI tools require an X11 session".to_string(),
        ));
    }
    Ok(())
}

fn parse_args<T: for<'de> Deserialize<'de>>(arguments: &str) -> Result<T, FunctionCallError> {
    serde_json::from_str(arguments).map_err(|e| {
        FunctionCallError::RespondToModel(format!("failed to parse function arguments: {e:?}"))
    })
}

fn require_command(name: &str) -> Result<PathBuf, FunctionCallError> {
    which(name).map_err(|_| {
        let hint = match name {
            "xdotool" => "sudo apt-get install -y xdotool",
            "import" => "sudo apt-get install -y imagemagick",
            _ => "install the required package",
        };
        FunctionCallError::RespondToModel(format!(
            "required command `{name}` not found; install it with `{hint}`"
        ))
    })
}

fn display_geometry(xdotool: &Path) -> Result<(f64, f64), FunctionCallError> {
    let output = Command::new(xdotool)
        .arg("getdisplaygeometry")
        .output()
        .map_err(|err| {
            FunctionCallError::RespondToModel(format!(
                "failed to run xdotool getdisplaygeometry: {err}"
            ))
        })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(FunctionCallError::RespondToModel(format!(
            "xdotool getdisplaygeometry failed: {stderr}"
        )));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut parts = stdout.split_whitespace();
    let width = parts
        .next()
        .ok_or_else(|| {
            FunctionCallError::RespondToModel(
                "xdotool getdisplaygeometry returned no width".to_string(),
            )
        })?
        .parse::<f64>()
        .map_err(|err| {
            FunctionCallError::RespondToModel(format!(
                "xdotool getdisplaygeometry invalid width: {err}"
            ))
        })?;
    let height = parts
        .next()
        .ok_or_else(|| {
            FunctionCallError::RespondToModel(
                "xdotool getdisplaygeometry returned no height".to_string(),
            )
        })?
        .parse::<f64>()
        .map_err(|err| {
            FunctionCallError::RespondToModel(format!(
                "xdotool getdisplaygeometry invalid height: {err}"
            ))
        })?;

    Ok((width, height))
}

fn scale_point(x: f64, y: f64, width: f64, height: f64) -> (i64, i64) {
    let x = x.clamp(0.0, TARGET_WIDTH - 1.0);
    let y = y.clamp(0.0, TARGET_HEIGHT - 1.0);
    let scaled_x = (x / TARGET_WIDTH) * width;
    let scaled_y = (y / TARGET_HEIGHT) * height;
    (scaled_x.round() as i64, scaled_y.round() as i64)
}

fn mouse_button(button: Option<String>) -> Result<String, FunctionCallError> {
    let button = button.unwrap_or_else(|| "left".to_string());
    let button = button.to_ascii_lowercase();
    match button.as_str() {
        "left" | "1" => Ok("1".to_string()),
        "middle" | "2" => Ok("2".to_string()),
        "right" | "3" => Ok("3".to_string()),
        _ => Err(FunctionCallError::RespondToModel(format!(
            "unsupported mouse button: {button}"
        ))),
    }
}

fn scroll_button(direction: &str) -> Result<String, FunctionCallError> {
    match direction.to_ascii_lowercase().as_str() {
        "up" => Ok("4".to_string()),
        "down" => Ok("5".to_string()),
        _ => Err(FunctionCallError::RespondToModel(format!(
            "unsupported scroll direction: {direction}"
        ))),
    }
}

fn requires_confirmation(keys: &[String]) -> bool {
    let normalized: std::collections::BTreeSet<String> =
        keys.iter().map(String::as_str).map(normalize_key).collect();

    let combos = [
        vec!["alt", "f4"],
        vec!["ctrl", "w"],
        vec!["ctrl", "q"],
        vec!["ctrl", "shift", "q"],
        vec!["super", "q"],
        vec!["ctrl", "alt", "backspace"],
    ];

    combos
        .iter()
        .any(|combo| combo.iter().all(|key| normalized.contains(*key)))
}

fn normalize_key(key: &str) -> String {
    let key = key.trim().to_ascii_lowercase();
    match key.as_str() {
        "cmd" | "meta" | "super" => "super".to_string(),
        "control" => "ctrl".to_string(),
        _ => key,
    }
}

fn run_command(command: &Path, args: &[String]) -> Result<(), FunctionCallError> {
    let output = Command::new(command).args(args).output().map_err(|err| {
        FunctionCallError::RespondToModel(format!("failed to run {command:?}: {err}"))
    })?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        return Err(FunctionCallError::RespondToModel(format!(
            "command {command:?} failed: {stderr}{stdout}"
        )));
    }

    Ok(())
}

fn capture_screenshot() -> Result<PathBuf, FunctionCallError> {
    let import = require_command("import")?;
    let id = Uuid::new_v4();
    let filename = format!("codex-screenshot-{id}.png");
    let path = env::temp_dir().join(filename);
    let output = Command::new(&import)
        .args(["-window", "root", "-resize", "1280x720!"])
        .arg(&path)
        .output()
        .map_err(|err| FunctionCallError::RespondToModel(format!("failed to run import: {err}")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(FunctionCallError::RespondToModel(format!(
            "import failed: {stderr}"
        )));
    }

    if !path.is_file() {
        let display = path.display();
        return Err(FunctionCallError::RespondToModel(format!(
            "screenshot was not created at {display}"
        )));
    }

    Ok(path)
}
