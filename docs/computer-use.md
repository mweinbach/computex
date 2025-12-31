## Computer use (CLI)

Computex runs as a computer-use agent in the interactive TUI. Use `--headless` to run shell-only, or `--gui` to enable on-demand screenshots and GUI input tools.

### Usage

```bash
# Shell-only (no GUI tools)
computex --headless "summarize /var/log/syslog"

# GUI-enabled (on-demand screenshots + input)
computex --gui "open the browser and check the system status page"
```

### GUI dependencies (Ubuntu + X11)

GUI mode requires an X11 session and a few helper binaries:

```bash
sudo apt-get install -y xdotool imagemagick
```

If `DISPLAY` is not set, GUI tools will fail. Launch Computex from an X11 session (or forward `DISPLAY`).

### Tool overview

When `--gui` is enabled, Computex exposes these tools:

- `computer_screenshot` – capture a single screenshot (1280x720 coordinate space)
- `computer_click` – move and click at a coordinate
- `computer_drag` – click-and-drag between coordinates
- `computer_scroll` – scroll up or down
- `computer_type` – type text at the current focus
- `computer_key` – press a key or key chord

### Coordinate system

All GUI tools use a fixed 1280x720 coordinate space. Take a `computer_screenshot` before clicking so coordinates align with what the agent sees.

### Destructive actions

Certain key combos (Alt+F4, Ctrl+W, Ctrl+Q, Ctrl+Shift+Q, Super+Q, Ctrl+Alt+Backspace) require `confirm=true`. Computex will ask for explicit confirmation before using them.
