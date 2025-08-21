# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

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
    if ! [[ $( sw_vers -productVersion ) =~ ^(15.[0-9]+|14.[0-9]+|13.[0-9]+|12.[0-9]+|11.[0-9]+) ]] ; then
        print_error "Sorry, this script is supposed to be executed on macOS Big Sur (11.x), Monterey (12.x), Ventura (13.x), Sonoma (14.x) and Sequoia (15.x). Please use a supported version."
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
    # Source advanced color libraries if available for cyberpunk effects
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local sparkdock_root="$(cd "${script_dir}/../.." && pwd)"
    
    # Try to source color libraries for enhanced effects
    if [[ -f "${sparkdock_root}/sjust/libs/libcolors.sh" ]]; then
        # shellcheck source=../../sjust/libs/libcolors.sh
        source "${sparkdock_root}/sjust/libs/libcolors.sh" 2>/dev/null || true
    fi
    if [[ -f "${sparkdock_root}/sjust/libs/libformatting.sh" ]]; then
        # shellcheck source=../../sjust/libs/libformatting.sh  
        source "${sparkdock_root}/sjust/libs/libformatting.sh" 2>/dev/null || true
    fi
    
    # Check if advanced colors are available, fall back to basic if not
    if [[ -n "${lightred:-}" && -n "${cyan:-}" && -n "${bold:-}" ]]; then
        # Advanced cyberpunk banner with gradient effects
        echo ""
        echo ""
        # Modern cyberpunk gradient border
        echo -e "${bold}${red}  ░▒▓${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}▓▒░${normal:-${NC}}"
        echo ""
        
        # SPARKDOCK in clean block letters with cyberpunk colors
        echo -e "${bold}${lightred}     ▄█████▄ ▄█████▄  ▄█████▄ ▄█████▄ ██  ██ ▄█████▄${normal:-${NC}}"
        echo -e "${bold}${red}     █${cyan}▄▄▄▄▄${red}█ █${cyan}██████${red}█ █${cyan}██████${red}█ █${cyan}██████${red}█ █${cyan}██${red}██ █${cyan}██████${red}█${normal:-${NC}}"
        echo -e "${bold}${cyan}     █${red}████${cyan}█▄ █${red}██████${cyan}█ █${red}██████${cyan}█ █${red}██████${cyan}█ █${red}██${cyan}██ █${red}██████${cyan}█${normal:-${NC}}"
        echo -e "${bold}${red}     ▄${cyan}▄▄▄▄${red}██ █${cyan}██${red}█▄▄▄▄ █${cyan}██${red}█▄▄▄▄ █${cyan}██${red}█▄▄▄▄ █${cyan}██${red}██ █${cyan}██${red}█▄▄▄▄${normal:-${NC}}"
        echo -e "${bold}${cyan}     █████▄▄ █${red}██${cyan}█     █${red}██${cyan}█     █${red}██████${cyan}█ █${red}██${cyan}██ █${red}██${cyan}█${normal:-${NC}}"
        echo ""
        echo -e "${bold}${cyan}     ▄█████▄  ▄█████▄  ▄█████▄ ██  ██${normal:-${NC}}"
        echo -e "${bold}${red}     █${cyan}██████${red}█ █${cyan}██████${red}█ █${cyan}██████${red}█ █${cyan}██${red}██${normal:-${NC}}"
        echo -e "${bold}${cyan}     █${red}██████${cyan}█ █${red}██████${cyan}█ █${red}██${cyan}█  ▄▄ █${red}██${cyan}██${normal:-${NC}}"
        echo -e "${bold}${red}     █${cyan}██${red}█  ▄▄ █${cyan}██${red}█  ▄▄ █${cyan}██${red}█ ▄██ █${cyan}██${red}██${normal:-${NC}}"
        echo -e "${bold}${cyan}     █${red}██${cyan}█  ▄▄ ████████ ▄█████▄ █${red}██${cyan}██${normal:-${NC}}"
        
        echo ""
        # Modern cyberpunk gradient border
        echo -e "${bold}${red}  ░▒▓${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}█${cyan}█${lightcyan:-${cyan}}█${cyan}█${red}█${lightred}█${red}▓▒░${normal:-${NC}}"
        echo ""
    else
        # Fallback to enhanced basic colors if advanced libraries not available
        echo ""
        echo ""
        echo -e "${BOLD}${RED}  ░▒▓████████████████████████████████████████████▓▒░${NC}"
        echo ""
        echo -e "${BOLD}${RED}     ▄█████▄ ▄█████▄  ▄█████▄ ▄█████▄ ██  ██ ▄█████▄${NC}"
        echo -e "${BOLD}${RED}     █▄▄▄▄▄█ ████████ ████████ ████████ █████ ████████${NC}"  
        echo -e "${BOLD}${BLUE}     ██████▄ ████████ ████████ ████████ █████ ████████${NC}"
        echo -e "${BOLD}${RED}     ▄▄▄▄▄██ ████▄▄▄▄ ████▄▄▄▄ ████▄▄▄▄ █████ ████▄▄▄▄${NC}"
        echo -e "${BOLD}${BLUE}     █████▄▄ ████     ████     ████████ █████ ████${NC}"
        echo ""
        echo -e "${BOLD}${BLUE}     ▄█████▄  ▄█████▄  ▄█████▄ ██  ██${NC}"
        echo -e "${BOLD}${RED}     ████████ ████████ ████████ █████${NC}"
        echo -e "${BOLD}${BLUE}     ████████ ████████ ████  ▄▄ █████${NC}"
        echo -e "${BOLD}${RED}     ████  ▄▄ ████  ▄▄ ████ ▄██ █████${NC}"
        echo -e "${BOLD}${BLUE}     ████  ▄▄ ████████ ▄█████▄ █████${NC}"
        echo ""
        echo -e "${BOLD}${RED}  ░▒▓████████████████████████████████████████████▓▒░${NC}"
        echo ""
    fi
    
    print_section "System Information"
    get_version_info
    echo ""
}

# Keep old function name for backward compatibility
sparkdockfetch() {
    print_banner
}
