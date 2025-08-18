# Colors and formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

setopt PROMPT_SUBST

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
    local local_version=$(git rev-parse --short HEAD)
    local last_commit_date=$(git log -1 --format=%cd --date=format:'%Y-%m-%d %H:%M:%S')

    # Get remote version (fetch quietly to get latest remote info)
    local remote_version="unknown"
    if git fetch origin "${current_branch}" -q 2>/dev/null; then
        remote_version=$(git rev-parse --short "origin/${current_branch}" 2>/dev/null || echo "unknown")
    fi
    echo "Local version: ${local_version} (${current_branch})"
    echo "Remote version: ${remote_version} (${current_branch})"
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

# Keep old function name for backward compatibility
sparkdockfetch() {
    print_banner
}
