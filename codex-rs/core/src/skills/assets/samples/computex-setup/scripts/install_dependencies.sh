#!/bin/bash
#
# Computex Dependency Installer
#
# Automatically detects package manager and installs xdotool and imagemagick.
# Supports: apt-get (Debian/Ubuntu), dnf (Fedora), pacman (Arch), yum (RHEL/CentOS)

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}${BOLD}==>${NC} $1"
}

print_success() {
    echo -e "${GREEN}${BOLD}✓${NC} $1"
}

print_error() {
    echo -e "${RED}${BOLD}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}${BOLD}⚠${NC} $1"
}

# Check if running on Linux
if [[ "$(uname -s)" != "Linux" ]]; then
    print_error "This script only works on Linux"
    echo "Computer-use GUI tools require Linux/X11"
    exit 2
fi

# Detect package manager
detect_package_manager() {
    if command -v apt-get &> /dev/null; then
        echo "apt"
    elif command -v dnf &> /dev/null; then
        echo "dnf"
    elif command -v pacman &> /dev/null; then
        echo "pacman"
    elif command -v yum &> /dev/null; then
        echo "yum"
    else
        echo "unknown"
    fi
}

# Install using apt (Debian/Ubuntu)
install_apt() {
    print_status "Using apt package manager (Debian/Ubuntu)"

    print_status "Updating package lists..."
    sudo apt-get update

    print_status "Installing xdotool..."
    sudo apt-get install -y xdotool

    print_status "Installing imagemagick..."
    sudo apt-get install -y imagemagick

    print_success "Installation complete!"
}

# Install using dnf (Fedora)
install_dnf() {
    print_status "Using dnf package manager (Fedora)"

    print_status "Installing xdotool..."
    sudo dnf install -y xdotool

    print_status "Installing ImageMagick..."
    sudo dnf install -y ImageMagick

    print_success "Installation complete!"
}

# Install using pacman (Arch Linux)
install_pacman() {
    print_status "Using pacman package manager (Arch Linux)"

    print_status "Updating package database..."
    sudo pacman -Sy

    print_status "Installing xdotool and imagemagick..."
    sudo pacman -S --noconfirm xdotool imagemagick

    print_success "Installation complete!"
}

# Install using yum (RHEL/CentOS)
install_yum() {
    print_status "Using yum package manager (RHEL/CentOS)"

    print_status "Installing xdotool..."
    sudo yum install -y xdotool

    print_status "Installing ImageMagick..."
    sudo yum install -y ImageMagick

    print_success "Installation complete!"
}

# Parse command line arguments
FORCE_PM=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --apt)
            FORCE_PM="apt"
            shift
            ;;
        --dnf)
            FORCE_PM="dnf"
            shift
            ;;
        --pacman)
            FORCE_PM="pacman"
            shift
            ;;
        --yum)
            FORCE_PM="yum"
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [--apt|--dnf|--pacman|--yum]"
            echo ""
            echo "Automatically installs computex dependencies (xdotool, imagemagick)"
            echo ""
            echo "Options:"
            echo "  --apt      Force use of apt-get (Debian/Ubuntu)"
            echo "  --dnf      Force use of dnf (Fedora)"
            echo "  --pacman   Force use of pacman (Arch Linux)"
            echo "  --yum      Force use of yum (RHEL/CentOS)"
            echo "  -h, --help Show this help message"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Main installation logic
echo -e "${BOLD}Computex Dependency Installer${NC}"
echo ""

# Determine package manager
if [[ -n "$FORCE_PM" ]]; then
    PM="$FORCE_PM"
    print_status "Using forced package manager: $PM"
else
    PM=$(detect_package_manager)
    if [[ "$PM" == "unknown" ]]; then
        print_error "Unable to detect package manager"
        echo ""
        echo "Supported package managers:"
        echo "  - apt-get (Debian/Ubuntu)"
        echo "  - dnf (Fedora)"
        echo "  - pacman (Arch Linux)"
        echo "  - yum (RHEL/CentOS)"
        echo ""
        echo "Please install xdotool and imagemagick manually using your package manager."
        exit 1
    fi
    print_status "Detected package manager: $PM"
fi

# Check if already installed
XDOTOOL_INSTALLED=false
IMAGEMAGICK_INSTALLED=false

if command -v xdotool &> /dev/null; then
    XDOTOOL_INSTALLED=true
    print_success "xdotool is already installed"
fi

if command -v import &> /dev/null; then
    IMAGEMAGICK_INSTALLED=true
    print_success "imagemagick is already installed"
fi

# Exit early if everything is installed
if $XDOTOOL_INSTALLED && $IMAGEMAGICK_INSTALLED; then
    echo ""
    print_success "All dependencies are already installed!"
    echo ""
    echo "You can now use: ${BLUE}computex --gui${NC}"
    exit 0
fi

# Confirm installation
echo ""
if ! $XDOTOOL_INSTALLED; then
    echo "  - xdotool"
fi
if ! $IMAGEMAGICK_INSTALLED; then
    echo "  - imagemagick"
fi
echo ""

# Install based on package manager
case "$PM" in
    apt)
        install_apt
        ;;
    dnf)
        install_dnf
        ;;
    pacman)
        install_pacman
        ;;
    yum)
        install_yum
        ;;
    *)
        print_error "Unsupported package manager: $PM"
        exit 1
        ;;
esac

# Verify installation
echo ""
print_status "Verifying installation..."

if command -v xdotool &> /dev/null; then
    print_success "xdotool installed successfully"
else
    print_error "xdotool installation failed"
    exit 1
fi

if command -v import &> /dev/null; then
    print_success "imagemagick installed successfully"
else
    print_error "imagemagick installation failed"
    exit 1
fi

echo ""
print_success "All dependencies installed successfully!"
echo ""
echo "Next steps:"
echo "  1. Verify DISPLAY is set: ${BLUE}echo \$DISPLAY${NC}"
echo "  2. Run verification script: ${BLUE}python scripts/check_dependencies.py${NC}"
echo "  3. Start using computex: ${BLUE}computex --gui \"take a screenshot\"${NC}"
