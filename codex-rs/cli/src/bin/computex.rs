use clap::Parser;
use codex_arg0::arg0_dispatch_or_else;
use codex_common::CliConfigOverrides;
use codex_core::COMPUTER_USE_PROMPT;
use codex_core::config::find_codex_home;
use codex_core::config::load_config_as_toml_with_cli_overrides;
use codex_core::features::Feature;
use codex_core::features::FeatureOverrides;
use codex_core::features::Features;
use codex_core::features::is_known_feature_key;
use codex_core::protocol::FinalOutput;
use codex_tui::AppExitInfo;
use codex_tui::Cli as TuiCli;
use codex_tui::update_action::UpdateAction;
use codex_tui2 as tui2;
use codex_utils_absolute_path::AbsolutePathBuf;
use owo_colors::OwoColorize;
use std::path::PathBuf;
use supports_color::Stream;

#[derive(Debug, Parser)]
#[command(
    author,
    version,
    bin_name = "computex",
    override_usage = "computex [OPTIONS] [PROMPT]"
)]
struct ComputexCli {
    #[clap(flatten)]
    config_overrides: CliConfigOverrides,

    #[clap(flatten)]
    feature_toggles: FeatureToggles,

    #[clap(flatten)]
    interactive: TuiCli,

    /// Enable GUI tools (screenshots + input).
    #[arg(long, conflicts_with = "headless")]
    gui: bool,

    /// Disable GUI tools (shell-only).
    #[arg(long, conflicts_with = "gui")]
    headless: bool,
}

#[derive(Debug, Default, Parser, Clone)]
struct FeatureToggles {
    /// Enable a feature (repeatable). Equivalent to `-c features.<name>=true`.
    #[arg(long = "enable", value_name = "FEATURE", action = clap::ArgAction::Append, global = true)]
    enable: Vec<String>,

    /// Disable a feature (repeatable). Equivalent to `-c features.<name>=false`.
    #[arg(long = "disable", value_name = "FEATURE", action = clap::ArgAction::Append, global = true)]
    disable: Vec<String>,
}

impl FeatureToggles {
    fn to_overrides(&self) -> anyhow::Result<Vec<String>> {
        let mut overrides = Vec::new();
        for feature in &self.enable {
            Self::validate_feature(feature)?;
            overrides.push(format!("features.{feature}=true"));
        }
        for feature in &self.disable {
            Self::validate_feature(feature)?;
            overrides.push(format!("features.{feature}=false"));
        }
        Ok(overrides)
    }

    fn validate_feature(feature: &str) -> anyhow::Result<()> {
        if is_known_feature_key(feature) {
            Ok(())
        } else {
            anyhow::bail!("Unknown feature flag: {feature}")
        }
    }
}

fn main() -> anyhow::Result<()> {
    arg0_dispatch_or_else(|codex_linux_sandbox_exe| async move {
        cli_main(codex_linux_sandbox_exe).await?;
        Ok(())
    })
}

async fn cli_main(codex_linux_sandbox_exe: Option<PathBuf>) -> anyhow::Result<()> {
    let ComputexCli {
        config_overrides,
        feature_toggles,
        interactive,
        gui,
        headless,
    } = ComputexCli::parse();

    let interactive = prepare_interactive(
        config_overrides,
        feature_toggles,
        interactive,
        gui,
        headless,
    )?;

    let exit_info = run_interactive_tui(interactive, codex_linux_sandbox_exe).await?;
    handle_app_exit(exit_info)?;
    Ok(())
}

fn prepare_interactive(
    mut config_overrides: CliConfigOverrides,
    feature_toggles: FeatureToggles,
    mut interactive: TuiCli,
    gui: bool,
    headless: bool,
) -> anyhow::Result<TuiCli> {
    let toggle_overrides = feature_toggles.to_overrides()?;
    config_overrides.raw_overrides.extend(toggle_overrides);

    interactive.config_overrides = config_overrides;
    let enable_gui = gui && !headless;
    interactive
        .config_overrides
        .raw_overrides
        .push(format!("features.computer_use_gui={enable_gui}"));
    interactive.base_instructions_override = Some(COMPUTER_USE_PROMPT.to_string());

    Ok(interactive)
}

async fn run_interactive_tui(
    interactive: TuiCli,
    codex_linux_sandbox_exe: Option<PathBuf>,
) -> std::io::Result<AppExitInfo> {
    if is_tui2_enabled(&interactive).await? {
        let result = tui2::run_main(interactive.into(), codex_linux_sandbox_exe).await?;
        Ok(result.into())
    } else {
        codex_tui::run_main(interactive, codex_linux_sandbox_exe).await
    }
}

async fn is_tui2_enabled(cli: &TuiCli) -> std::io::Result<bool> {
    let raw_overrides = cli.config_overrides.raw_overrides.clone();
    let overrides_cli = codex_common::CliConfigOverrides { raw_overrides };
    let cli_kv_overrides = overrides_cli
        .parse_overrides()
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidInput, e))?;

    let codex_home = find_codex_home()?;
    let cwd = cli.cwd.clone();
    let config_cwd = match cwd.as_deref() {
        Some(path) => AbsolutePathBuf::from_absolute_path(path)?,
        None => AbsolutePathBuf::current_dir()?,
    };
    let config_toml =
        load_config_as_toml_with_cli_overrides(&codex_home, &config_cwd, cli_kv_overrides).await?;
    let config_profile = config_toml.get_config_profile(cli.config_profile.clone())?;
    let overrides = FeatureOverrides::default();
    let features = Features::from_config(&config_toml, &config_profile, overrides);
    Ok(features.enabled(Feature::Tui2))
}

fn format_exit_messages(exit_info: AppExitInfo, color_enabled: bool) -> Vec<String> {
    let AppExitInfo {
        token_usage,
        conversation_id,
        ..
    } = exit_info;

    if token_usage.is_zero() {
        return Vec::new();
    }

    let mut lines = vec![format!("{}", FinalOutput::from(token_usage))];

    if let Some(session_id) = conversation_id {
        let resume_cmd = format!("codex resume {session_id}");
        let command = if color_enabled {
            resume_cmd.cyan().to_string()
        } else {
            resume_cmd
        };
        lines.push(format!("To continue this session, run {command}"));
    }

    lines
}

fn handle_app_exit(exit_info: AppExitInfo) -> anyhow::Result<()> {
    let update_action = exit_info.update_action;
    let color_enabled = supports_color::on(Stream::Stdout).is_some();
    for line in format_exit_messages(exit_info, color_enabled) {
        println!("{line}");
    }
    if let Some(action) = update_action {
        run_update_action(action)?;
    }
    Ok(())
}

fn run_update_action(action: UpdateAction) -> anyhow::Result<()> {
    println!();
    let cmd_str = action.command_str();
    println!("Updating Codex via `{cmd_str}`...");

    let status = {
        #[cfg(windows)]
        {
            std::process::Command::new("cmd")
                .args(["/C", &cmd_str])
                .status()?
        }
        #[cfg(not(windows))]
        {
            let (cmd, args) = action.command_args();
            std::process::Command::new(cmd).args(args).status()?
        }
    };
    if !status.success() {
        anyhow::bail!("`{cmd_str}` failed with status {status}");
    }
    println!();
    println!("🎉 Update ran successfully! Please restart Codex.");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use pretty_assertions::assert_eq;

    #[test]
    fn computex_gui_sets_instructions_and_flag() -> anyhow::Result<()> {
        let cli = ComputexCli::parse_from(["computex", "--gui", "hello"]);
        let interactive = prepare_interactive(
            cli.config_overrides,
            cli.feature_toggles,
            cli.interactive,
            cli.gui,
            cli.headless,
        )?;

        assert_eq!(
            interactive.base_instructions_override.as_deref(),
            Some(COMPUTER_USE_PROMPT)
        );
        assert!(
            interactive
                .config_overrides
                .raw_overrides
                .iter()
                .any(|value| value == "features.computer_use_gui=true")
        );
        Ok(())
    }

    #[test]
    fn computex_headless_disables_gui_tools() -> anyhow::Result<()> {
        let cli = ComputexCli::parse_from(["computex", "--headless", "hello"]);
        let interactive = prepare_interactive(
            cli.config_overrides,
            cli.feature_toggles,
            cli.interactive,
            cli.gui,
            cli.headless,
        )?;

        assert!(
            interactive
                .config_overrides
                .raw_overrides
                .iter()
                .any(|value| value == "features.computer_use_gui=false")
        );
        Ok(())
    }
}
