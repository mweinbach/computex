---
name: computex-setup
description: Verify and install dependencies for Computex computer-use tools (xdotool, imagemagick, X11/DISPLAY). Use when user wants to set up computer-use GUI tools, troubleshoot "command not found" errors for xdotool or import, or check if their environment is ready for GUI automation.
metadata:
  short-description: Set up and verify computex computer-use dependencies
---

# Computex Setup

## Overview

This skill helps verify and install the required dependencies for Computex computer-use GUI tools. It checks for xdotool, imagemagick, and proper X11/DISPLAY configuration.

## Quick Verification

To verify the environment is ready for computer-use tools, run the verification script:

```bash
python scripts/check_dependencies.py
```

This will check:
1. Operating system (Linux required)
2. DISPLAY environment variable
3. xdotool installation
4. imagemagick installation

## Installation Guide

### Prerequisites

Computer-use GUI tools require:
- **Platform**: Linux with X11 (not Wayland, not macOS, not Windows)
- **Display Server**: X11 session with DISPLAY environment variable set
- **Tools**: xdotool and imagemagick packages

### Step 1: Verify Platform

Computer-use tools only work on Linux with X11:

```bash
# Check if running Linux
uname -s  # Should output: Linux

# Check if X11 is running
echo $DISPLAY  # Should output something like :0 or :1
```

If DISPLAY is empty, you need to:
- Start an X11 session (if running headless, use Xvfb)
- Or use `computex --headless` mode (shell-only, no GUI tools)

### Step 2: Install xdotool

xdotool is used for mouse and keyboard control:

**Debian/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install -y xdotool
```

**Fedora/RHEL:**
```bash
sudo dnf install -y xdotool
```

**Arch Linux:**
```bash
sudo pacman -S xdotool
```

**Verify installation:**
```bash
which xdotool
xdotool version
```

### Step 3: Install ImageMagick

ImageMagick's `import` command is used for screenshot capture:

**Debian/Ubuntu:**
```bash
sudo apt-get update
sudo apt-get install -y imagemagick
```

**Fedora/RHEL:**
```bash
sudo dnf install -y ImageMagick
```

**Arch Linux:**
```bash
sudo pacman -S imagemagick
```

**Verify installation:**
```bash
which import
import -version
```

### Step 4: Verify Setup

Run the verification script to confirm everything is working:

```bash
python scripts/check_dependencies.py --verbose
```

If all checks pass, you're ready to use `computex --gui`!

## Troubleshooting

### DISPLAY not set

**Symptom:** Error: "DISPLAY is not set; GUI tools require an X11 session"

**Solutions:**
1. **If running locally with GUI:** Ensure you're in a graphical session
2. **If using SSH:** Forward X11 with `ssh -X user@host`
3. **If running headless:** Set up Xvfb virtual display:
   ```bash
   Xvfb :99 -screen 0 1280x720x24 &
   export DISPLAY=:99
   ```
4. **Alternative:** Use `computex --headless` for shell-only mode

### xdotool not found

**Symptom:** Error: "required command `xdotool` not found; install it with `sudo apt-get install -y xdotool`"

**Solution:** Install xdotool using your package manager (see Step 2 above)

### import not found

**Symptom:** Error: "required command `import` not found; install it with `sudo apt-get install -y imagemagick`"

**Solution:** Install imagemagick using your package manager (see Step 3 above)

### Running on macOS or Windows

**Symptom:** Error: "computer-use GUI tools are only supported on Linux/X11"

**Solution:** Computer-use GUI tools are Linux-only. Consider:
- Using a Linux VM or container
- Using WSL2 with X11 forwarding (Windows)
- Using the shell-only mode: `computex --headless`

### Wayland Display Server

**Symptom:** DISPLAY is set but tools don't work properly

**Solution:** xdotool requires X11. If you're on Wayland:
- Switch to X11 session (logout, select X11 at login screen)
- Or run under XWayland compatibility layer
- Or use `computex --headless` for shell-only mode

## Remote Usage (SSH)

To use computer-use tools over SSH:

```bash
# Connect with X11 forwarding
ssh -X user@remote-host

# Verify DISPLAY is set
echo $DISPLAY  # Should show something like localhost:10.0

# Run computex
computex --gui "take a screenshot"
```

## Headless Server Setup (Xvfb)

For servers without a physical display, use Xvfb (X Virtual Frame Buffer):

```bash
# Install Xvfb
sudo apt-get install -y xvfb

# Start virtual display
Xvfb :99 -screen 0 1280x720x24 &

# Set DISPLAY environment variable
export DISPLAY=:99

# Verify it works
xdotool getdisplaygeometry
# Should output: 1280 720
```

To make it persistent, add to your shell profile:
```bash
echo 'export DISPLAY=:99' >> ~/.bashrc
```

## Scripts

### check_dependencies.py

Comprehensive dependency checker that verifies all requirements and provides actionable error messages.

**Usage:**
```bash
# Quick check
python scripts/check_dependencies.py

# Verbose output with details
python scripts/check_dependencies.py --verbose

# Check and auto-install (requires sudo)
python scripts/check_dependencies.py --install
```

**Exit codes:**
- `0`: All dependencies satisfied
- `1`: Missing dependencies (check output for details)
- `2`: Platform not supported (not Linux)

### install_dependencies.sh

Automated installation script for supported package managers.

**Usage:**
```bash
# Detect package manager and install
bash scripts/install_dependencies.sh

# Force specific package manager
bash scripts/install_dependencies.sh --apt
bash scripts/install_dependencies.sh --dnf
bash scripts/install_dependencies.sh --pacman
```

## Testing Computer-Use Tools

After setup, test the tools:

```bash
# Test screenshot
computex --gui "take a screenshot and describe what you see"

# Test mouse control
computex --gui "move the mouse to the center of the screen"

# Test keyboard
computex --gui "type 'hello world' into the active window"
```

## Usage Modes

**GUI Mode (default with --gui):**
- Full computer-use tools available
- Requires X11, xdotool, and imagemagick
- Can capture screenshots and control mouse/keyboard

**Headless Mode (--headless):**
- Shell commands only
- No GUI tools, no screenshots
- Works anywhere (no X11 required)
- Useful for server automation

## References

- `scripts/check_dependencies.py` - Dependency verification tool
- `scripts/install_dependencies.sh` - Automated installer
- Main documentation: `docs/computer-use.md`
