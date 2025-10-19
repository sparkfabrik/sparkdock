# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Only set zsh options if we're running in zsh
if [[ -n "${ZSH_VERSION:-}" ]]; then
    setopt PROMPT_SUBST
fi

# Print functions for different message types
print_info() {
    printf "${BOLD}${BLUE}[INFO]${NC} %s\n" "$1"
}

print_success() {
    printf "${BOLD}${GREEN}[ OK ]${NC} %s\n" "$1"
}

print_warning() {
    printf "${BOLD}${YELLOW}[WARN]${NC} %s\n" "$1"
}

print_error() {
    printf "${BOLD}${RED}[FAIL]${NC} %s\n" "$1"
}

print_section() {
    echo ""
    printf "${BOLD}${BLUE}=== %s ===${NC}\n" "$1"
}

# Deprecate old print function but keep for compatibility
print() {
    print_info "$1"
}

checkMacosVersion() {
    if ! [[ $( sw_vers -productVersion ) =~ ^(26.[0-9]+|15.[0-9]+) ]] ; then
        print_error "Sorry, this script is supposed to be executed on macOS Sequoia (15.x) or macOS Tahoe (26.x). Please use a supported version."
        return 1
    fi
    return 0
}

# Note: The old install_update_service function has been removed
# Update checking is now handled by the Sparkdock Manager menu bar app

get_last_update() {
    if [ -f /opt/sparkdock/.last_update ]; then
        cat /opt/sparkdock/.last_update
    else
        echo "Never updated"
    fi
}

get_version_info() {
    # check if /opt/sparkdock exists, if not, it is a first run, just return
    if [ ! -d /opt/sparkdock ]; then
        echo "First run, no version information available."
        return
    fi
    cd /opt/sparkdock
    local current_branch=$(git rev-parse --abbrev-ref HEAD)
    local current_version=$(git rev-parse --short HEAD)
    local last_commit_date=$(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M:%S')
    echo "Version: ${current_version} (${current_branch})"
    echo "Last commit: ${last_commit_date}"
    echo "Last update: $(get_last_update)"
}

print_banner() {
cat <<"EOF"


  ___                _      _         _
 / __|_ __  __ _ _ _| |____| |___  __| |__
 \__ \ '_ \/ _` | '_| / / _` / _ \/ _| / /
 |___/ .__/\__,_|_| |_\_\__,_\___/\__|_\_\
     |_|

EOF
    print_section "System Information"
    get_version_info
    echo ""
}

# Check for Xcode command line tools issues using brew doctor
check_xcode_issues() {
    # Skip check in CI environments
    if [[ -n "${CI:-}" || -n "${GITHUB_ACTIONS:-}" || -n "${NON_INTERACTIVE:-}" ]]; then
        return 0
    fi

    # Check if brew is available
    if ! command -v brew &> /dev/null; then
        print_warning "Homebrew not found. Skipping Xcode command line tools check."
        return 0
    fi

    # Run brew doctor and capture output
    local brew_doctor_output
    brew_doctor_output=$(brew doctor 2>&1 || true)

    # Check for the specific Swift compilation issue mentioned in the GitHub issue
    if echo "${brew_doctor_output}" | grep -q "No Cask quarantine support available.*Swift compilation failed"; then
        print_error "Xcode command line tools issue detected!"
        echo ""
        print_warning "brew doctor reports: No Cask quarantine support available: Swift compilation failed."
        print_warning "This is usually due to a broken or incompatible Command Line Tools installation."
        echo ""
        print_info "To resolve this issue, please run:"
        echo "  xcode-select --install"
        echo ""
        print_info "If that doesn't resolve your issues, run:"
        echo "  sudo rm -rf /Library/Developer/CommandLineTools"
        echo "  sudo xcode-select --install"
        echo ""
        print_info "Alternatively, manually download them from:"
        echo "  https://developer.apple.com/download/all/"
        echo ""

        # Ask user if they want to continue
        echo -n "Do you want to continue with the provisioning anyway? (y/N): "
        read -r response
        if [[ ! "${response}" =~ ^[Yy]$ ]]; then
            print_info "Exiting. Please resolve the Xcode issues first."
            exit 1
        fi
        echo ""
        return 1
    fi

    # Check for other Command Line Tools related issues in brew doctor output
    if echo "${brew_doctor_output}" | grep -qi "command line tools\|xcode-select"; then
        print_warning "Potential Xcode command line tools issue detected in brew doctor output:"
        echo "${brew_doctor_output}" | grep -i "command line tools\|xcode-select" | sed 's/^/  /'
        echo ""
        print_info "You may want to check your Xcode command line tools installation."
        print_info "If you encounter issues during provisioning, try running: xcode-select --install"
        echo ""
        return 1
    fi

    print_success "No Xcode command line tools issues detected."
    return 0
}

# Ensure Python3 is installed and available at the expected location
ensure_python3() {
    if [[ ! -f /opt/homebrew/bin/python3 ]]; then
        print_info "Python3 symlink not found at /opt/homebrew/bin/python3"

        # Check if python@3 is installed but not linked
        if brew list python@3 &> /dev/null; then
            print_info "Python is installed but not linked, fixing symlinks..."
            brew unlink python@3 &> /dev/null || true
            brew link python@3 &> /dev/null || true
        else
            print_info "Installing Python3..."
            brew install python3
        fi

        # Verify python3 symlink is now available
        if [[ ! -f /opt/homebrew/bin/python3 ]]; then
            print_error "Failed to create python3 symlink. Please run: brew link python@3"
            exit 1
        fi
        print_info "Python3 is now available at /opt/homebrew/bin/python3"
    fi
}

# Check if we're running in a CI environment
is_ci_environment() {
    [[ -n "${CI:-}" ]] || \
    [[ -n "${GITHUB_ACTIONS:-}" ]] || \
    [[ -n "${RUNNER_OS:-}" ]] || \
    [[ -n "${CIRRUS_CI:-}" ]] || \
    [[ "${HOME}" == "/var/root" ]] || \
    [[ -n "${ANSIBLE_SUDO_PASSWORD:-}" ]]
}

# Keep old function name for backward compatibility
sparkdockfetch() {
    print_banner
}
