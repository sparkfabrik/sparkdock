RED='\033[0;31m'
NC='\033[0m'

print () {
    echo -e "\e[1m\e[93m[ \e[92m•\e[93m ] \e[4m$1\e[0m" }

checkMacosVersion() {
    print "Checking for macOS supported version..."
    if ! [[ $( sw_vers -productVersion ) =~ ^(13.[0-9]+|12.[0-9]+|11.[0-9]+) ]] ; then
        print  "${RED}Sorry, this script is supposed to be executed on macOS Big Sur (11.x), Monterey (12.x) and Ventura (13.x). Please use a supported version.${NC}"
        exit 1
    fi
    exit 0
}

sparkdockfetch() {
cat <<"EOF"


  ___                _      _         _
 / __|_ __  __ _ _ _| |____| |___  __| |__
 \__ \ '_ \/ _` | '_| / / _` / _ \/ _| / /
 |___/ .__/\__,_|_| |_\_\__,_\___/\__|_\_\
     |_|


EOF
}