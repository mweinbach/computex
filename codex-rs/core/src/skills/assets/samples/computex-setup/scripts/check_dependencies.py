#!/usr/bin/env python3
"""
Computex Dependency Checker

Verifies that all required dependencies for computer-use GUI tools are installed.
Checks: Linux platform, DISPLAY variable, xdotool, and imagemagick.

Exit codes:
  0 - All dependencies satisfied
  1 - Missing dependencies
  2 - Platform not supported
"""

import argparse
import os
import platform
import shutil
import subprocess
import sys


class Colors:
    """ANSI color codes for terminal output"""

    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    RED = "\033[91m"
    BLUE = "\033[94m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def print_check(name, passed, message="", verbose=False):
    """Print a check result with color coding"""
    if passed:
        status = f"{Colors.GREEN}✓ PASS{Colors.RESET}"
        if verbose and message:
            print(f"{status} {name}: {message}")
        else:
            print(f"{status} {name}")
    else:
        status = f"{Colors.RED}✗ FAIL{Colors.RESET}"
        print(f"{status} {name}")
        if message:
            print(f"       {message}")


def check_platform(verbose=False):
    """Check if running on Linux"""
    system = platform.system()
    is_linux = system == "Linux"

    if verbose:
        print_check(
            "Platform", is_linux, f"Running on {system} (Linux required)", verbose
        )
    else:
        print_check("Platform", is_linux, "Not Linux - computer-use requires Linux/X11")

    return is_linux


def check_display(verbose=False):
    """Check if DISPLAY environment variable is set"""
    display = os.environ.get("DISPLAY", "")
    has_display = bool(display)

    msg = ""
    if not has_display:
        msg = "Set DISPLAY (e.g., export DISPLAY=:0) or use 'computex --headless'"
    elif verbose:
        msg = f"DISPLAY={display}"

    print_check("DISPLAY variable", has_display, msg, verbose)
    return has_display


def check_command(command, verbose=False):
    """Check if a command is available in PATH"""
    path = shutil.which(command)
    available = path is not None

    msg = ""
    if not available:
        if command == "xdotool":
            msg = "Install: sudo apt-get install -y xdotool"
        elif command == "import":
            msg = "Install: sudo apt-get install -y imagemagick"
        else:
            msg = f"Command '{command}' not found in PATH"
    elif verbose:
        msg = f"Found at {path}"

    print_check(command, available, msg, verbose)
    return available, path


def check_command_version(command, path, verbose=False):
    """Try to get version information for a command"""
    if not path or not verbose:
        return

    try:
        # Try common version flags
        for flag in ["--version", "-version", "version", "-V"]:
            try:
                result = subprocess.run(
                    [command, flag],
                    capture_output=True,
                    text=True,
                    timeout=2,
                    check=False,
                )
                if result.returncode == 0 and result.stdout.strip():
                    # Print first line of version output
                    first_line = result.stdout.strip().split("\n")[0]
                    print(f"       Version: {first_line}")
                    return
            except (subprocess.TimeoutExpired, FileNotFoundError):
                continue
    except Exception:
        pass


def get_install_command():
    """Detect package manager and return install command"""
    if shutil.which("apt-get"):
        return "sudo apt-get update && sudo apt-get install -y xdotool imagemagick"
    elif shutil.which("dnf"):
        return "sudo dnf install -y xdotool ImageMagick"
    elif shutil.which("pacman"):
        return "sudo pacman -S xdotool imagemagick"
    elif shutil.which("yum"):
        return "sudo yum install -y xdotool ImageMagick"
    else:
        return None


def auto_install():
    """Attempt to auto-install missing dependencies"""
    print(f"\n{Colors.BOLD}Attempting to install dependencies...{Colors.RESET}\n")

    install_cmd = get_install_command()
    if not install_cmd:
        print(
            f"{Colors.RED}Unable to detect package manager. Please install manually.{Colors.RESET}"
        )
        return False

    print(f"Running: {install_cmd}\n")

    try:
        result = subprocess.run(install_cmd, shell=True, check=False)
        return result.returncode == 0
    except Exception as e:
        print(f"{Colors.RED}Installation failed: {e}{Colors.RESET}")
        return False


def main():
    parser = argparse.ArgumentParser(
        description="Check computex computer-use dependencies"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true", help="Show detailed information"
    )
    parser.add_argument(
        "--install",
        action="store_true",
        help="Attempt to auto-install missing dependencies (requires sudo)",
    )
    args = parser.parse_args()

    print(f"{Colors.BOLD}Computex Computer-Use Dependency Check{Colors.RESET}\n")

    # Track overall status
    all_passed = True

    # Check platform
    if not check_platform(args.verbose):
        all_passed = False
        print(
            f"\n{Colors.RED}Computer-use GUI tools are only supported on Linux/X11.{Colors.RESET}"
        )
        print("Alternatives:")
        print("  - Use 'computex --headless' for shell-only mode")
        print("  - Run in a Linux VM or container")
        return 2

    # Check DISPLAY
    has_display = check_display(args.verbose)
    if not has_display:
        all_passed = False

    # Check xdotool
    has_xdotool, xdotool_path = check_command("xdotool", args.verbose)
    if not has_xdotool:
        all_passed = False
    elif args.verbose:
        check_command_version("xdotool", xdotool_path, args.verbose)

    # Check imagemagick
    has_import, import_path = check_command("import", args.verbose)
    if not has_import:
        all_passed = False
    elif args.verbose:
        check_command_version("import", import_path, args.verbose)

    # Print summary
    print()
    if all_passed:
        print(
            f"{Colors.GREEN}{Colors.BOLD}✓ All dependencies satisfied!{Colors.RESET}"
        )
        print(f"\nYou can now use: {Colors.BLUE}computex --gui{Colors.RESET}")
        return 0
    else:
        print(
            f"{Colors.RED}{Colors.BOLD}✗ Some dependencies are missing{Colors.RESET}"
        )

        # Offer installation if requested
        if args.install:
            if auto_install():
                print(
                    f"\n{Colors.GREEN}Installation completed. Re-running checks...{Colors.RESET}\n"
                )
                # Re-run checks
                return main() if "--install" not in sys.argv else 1
            else:
                print(
                    f"\n{Colors.RED}Auto-installation failed. Please install manually.{Colors.RESET}"
                )

        # Print manual installation instructions
        print("\nTo install missing dependencies:")

        if not has_display:
            print(
                f"\n  {Colors.YELLOW}DISPLAY:{Colors.RESET} Set up X11 or use --headless mode"
            )
            print("    export DISPLAY=:0           # If X11 is running")
            print(
                "    computex --headless         # Use shell-only mode (no GUI tools)"
            )

        if not has_xdotool or not has_import:
            install_cmd = get_install_command()
            if install_cmd:
                print(f"\n  {Colors.YELLOW}Install commands:{Colors.RESET}")
                print(f"    {install_cmd}")
            else:
                print(f"\n  {Colors.YELLOW}Manual installation:{Colors.RESET}")
                if not has_xdotool:
                    print("    Install xdotool using your package manager")
                if not has_import:
                    print("    Install imagemagick using your package manager")

        print(
            f"\nOr run with auto-install: {Colors.BLUE}python {sys.argv[0]} --install{Colors.RESET}"
        )

        return 1


if __name__ == "__main__":
    sys.exit(main())
