## Computer use (macOS VM)

Computex runs as a computer-use agent inside a macOS virtual machine managed by the host app in the top-level `macos-app/` directory. Codex core executes inside the guest and streams all events to the host UI.

### Usage

- Launch the host app to create or resume a VM session.
- Complete the first-boot macOS setup once.
- Start a primary (persistent) session or create a disposable session for each task.

### Tool overview

Computex exposes these tools:

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
