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

sparkdockfetch() {
cat <<"EOF"


  ___                _      _         _
 / __|_ __  __ _ _ _| |____| |___  __| |__
 \__ \ '_ \/ _` | '_| / / _` / _ \/ _| / /
 |___/ .__/\__,_|_| |_\_\__,_\___/\__|_\_\
     |_|


EOF
}
