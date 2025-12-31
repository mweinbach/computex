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

Computex includes safety mechanisms to prevent accidental execution of potentially destructive keyboard shortcuts.

#### Protected Key Combinations

The following key combinations require explicit user confirmation before execution:

- **Alt+F4** - Close window
- **Ctrl+W** - Close tab/window
- **Ctrl+Q** - Quit application
- **Ctrl+Shift+Q** - Quit application (force)
- **Super+Q** / **Cmd+Q** / **Meta+Q** - Quit application (macOS-style)
- **Ctrl+Alt+Backspace** - Kill X server

#### How the Approval Flow Works

1. **Agent requests a destructive action**: When Claude wants to press a protected key combination, it calls `computer_key` with the key sequence.

2. **Handler detects the dangerous combo**: The `computer_use` handler checks if the key combination matches any protected patterns using case-insensitive normalized key names.

3. **Rejection without confirmation**: If the tool call doesn't include `confirm=true`, the handler immediately rejects the request with an error message:
   ```
   "destructive key combo requires confirm=true after user approval"
   ```

4. **Agent requests user approval**: Claude sees the rejection and asks the user for permission to proceed with the destructive action.

5. **User reviews and approves**: In the TUI, the user reviews the request and decides whether to approve it.

6. **Agent retries with confirmation**: If approved, Claude calls `computer_key` again with the same keys plus `confirm=true`.

7. **Handler executes the action**: With `confirm=true` present, the handler bypasses the safety check and executes the key combination.

#### Example Flow

```
# Step 1: Claude attempts to close a window
computer_key(keys=["alt", "f4"])

# Step 2: Handler rejects (no confirm parameter)
Error: "destructive key combo requires confirm=true after user approval"

# Step 3: Claude asks user
"I need to close this window using Alt+F4. May I proceed?"

# Step 4: User approves in TUI
[User clicks "Approve" or types confirmation]

# Step 5: Claude retries with confirmation
computer_key(keys=["alt", "f4"], confirm=true)

# Step 6: Handler executes
Success: "pressed alt+f4"
```

#### Key Normalization

The handler normalizes key names to handle variations:
- `cmd`, `meta`, `super` → normalized to `super`
- `control` → normalized to `ctrl`
- All keys converted to lowercase
- Whitespace trimmed

This ensures protection works regardless of how the keys are specified.

#### Safe Key Combinations

Common keyboard shortcuts that do NOT require confirmation:
- **Ctrl+C** / **Ctrl+V** - Copy/paste
- **Ctrl+Z** / **Ctrl+Y** - Undo/redo
- **Alt+Tab** - Switch windows
- **Ctrl+Alt+T** - Terminal (many Linux distros)
- **Ctrl+S** - Save
- Any single key presses
- Function keys (F1-F12) without dangerous modifiers

#### Bypassing Protection (Not Recommended)

While the handler requires `confirm=true` for destructive actions, the actual user approval workflow is implemented at the TUI level. In non-interactive exec mode, the safety mechanism will prevent destructive actions unless explicitly confirmed in the tool call.

**Security Note**: Never set `confirm=true` automatically without actual user approval. The confirmation parameter exists to acknowledge that the user has consciously approved the potentially destructive operation.
