RED='\033[0;31m'
NC='\033[0m'

setopt PROMPT_SUBST

print () {
    printf "\e[1m\e[93m[ \e[92m•\e[93m ] \e[4m%s\e[0m\n" "$1"
}

checkMacosVersion() {
    if ! [[ $( sw_vers -productVersion ) =~ ^(15.[0-9]+|14.[0-9]+|13.[0-9]+|12.[0-9]+|11.[0-9]+) ]] ; then
        print  "${RED}Sorry, this script is supposed to be executed on macOS Big Sur (11.x), Monterey (12.x), Ventura (13.x), Sonoma (14.x) and Sequoia (15.x). Please use a supported version.${NC}"
        return 1
    fi
    return 0
}

install_update_service() {
    # Ensure LaunchAgents directory exists
    mkdir -p ~/Library/LaunchAgents

    # Install or update the plist file
    cp /opt/sparkdock/launchd/com.sparkfabrik.sparkdock.plist ~/Library/LaunchAgents/

    # Unload if exists (ignoring errors) and load the service
    launchctl unload ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.plist 2>/dev/null || true
    launchctl load ~/Library/LaunchAgents/com.sparkfabrik.sparkdock.plist
}

get_last_update() {
    if [ -f /opt/sparkdock/.last_update ]; then
        cat /opt/sparkdock/.last_update
    else
        echo "Never updated"
    fi
}

sparkdockfetch() {
cat <<"EOF"


  ___                _      _         _
 / __|_ __  __ _ _ _| |____| |___  __| |__
 \__ \ '_ \/ _` | '_| / / _` / _ \/ _| / /
 |___/ .__/\__,_|_| |_\_\__,_\___/\__|_\_\
     |_|

Last updated: $(get_last_update)

EOF
}
