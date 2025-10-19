#!/usr/bin/env bash
# Sparkdock Shell Utilities
# Shared functions for shell configuration management

# Check if a user file is symlinked to Sparkdock's default
# Usage: check_sparkdock_symlink <user_file> <sparkdock_file>
# Returns:
#   0 - Managed by Sparkdock (symlinked to our file)
#   1 - Custom configuration (user's file or external symlink)
#   2 - Does not exist (needs setup)
check_sparkdock_symlink() {
    local user_file="$1"
    local sparkdock_file="$2"

    if [[ ! -e "${user_file}" ]]; then
        return 2
    fi

    if [[ -L "${user_file}" ]]; then
        local link_target
        link_target="$(readlink "${user_file}")"
        if [[ "${link_target}" == "${sparkdock_file}" ]]; then
            return 0
        fi
    fi
    return 1
}

# Print configuration status message
# Args: program_name, status (0=managed, 1=custom, 2=not exists), user_file, sparkdock_file, config_name
print_config_status() {
    local program_name="${1}"
    local status="${2}"
    local user_file="${3}"
    local sparkdock_file="${4}"
    local config_name="${5}"
    local prefix=""

    if [[ -n "${program_name}" ]]; then
        prefix="${program_name}: "
    fi

    if [[ ${status} -eq 0 ]]; then
        echo "ℹ️ ${prefix}managed ${config_name} (auto-updates with Sparkdock)"
    else
        echo "ℹ️ ${prefix}custom ${config_name} detected, this file cannot be managed, skipping."
        echo "💡 ${prefix}to use Sparkdock defaults: rm ${user_file} && ln -s ${sparkdock_file} ${user_file}"
    fi
}

# Print setup completion message for newly created config files
# Usage: print_setup_complete <user_file> <sparkdock_file> <extra_info>
# extra_info: Optional additional info (e.g., "Based on Catppuccin color scheme")
print_setup_complete() {
    local user_file="$1"
    local sparkdock_file="$2"
    local extra_info="${3:-}"

    echo ""
    echo "💡 This uses Sparkdock's default (auto-updates with Sparkdock)"
    echo "💡 To customize: rm ${user_file} && cp ${sparkdock_file} ${user_file}"
    if [[ -n "${extra_info}" ]]; then
        echo "💡 ${extra_info}"
    fi
}

# Print comprehensive shell information
print_shell_info() {
    echo "=========================================="
    echo "Sparkdock Shell Enhancements"
    echo "=========================================="
    echo ""
    echo "🎨 Configuration Status:"
    local zshrc_file="${HOME}/.zshrc"
    local sparkdock_check_line="if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"

    if [[ -f "${zshrc_file}" ]] && grep -qF "${sparkdock_check_line}" "${zshrc_file}"; then
        echo "  ✅ Enabled in ${zshrc_file}"
    else
        echo "  ❌ Not enabled - Run 'sjust shell-enable' to enable"
    fi

    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        echo "  ✅ oh-my-zsh installed"
    else
        echo "  ❌ oh-my-zsh not installed - Run 'sjust shell-omz-setup'"
    fi

    echo ""
    echo "🚀 Modern Tools Status:"
    for tool in eza fd rg bat fzf zoxide; do
        if command -v "${tool}" &> /dev/null; then
            echo "  ✅ ${tool}"
        else
            echo "  ❌ ${tool}"
        fi
    done

    echo ""
    echo "🔧 Optional Tools (require manual enable):"
    if command -v starship &> /dev/null; then
        if [[ -n "${SPARKDOCK_ENABLE_STARSHIP:-}" ]]; then
            echo "  ✅ starship (ENABLED)"
        else
            echo "  ⚙️  starship (available, set SPARKDOCK_ENABLE_STARSHIP=1 to enable)"
        fi
    else
        echo "  ❌ starship (not installed)"
    fi

    if command -v atuin &> /dev/null; then
        if [[ -n "${SPARKDOCK_ENABLE_ATUIN:-}" ]]; then
            echo "  ✅ atuin (ENABLED)"
        else
            echo "  ⚙️  atuin (available, set SPARKDOCK_ENABLE_ATUIN=1 to enable)"
        fi
    else
        echo "  ❌ atuin (not installed)"
    fi

    if command -v fzf &> /dev/null; then
        if [[ -n "${SPARKDOCK_ENABLE_FZF:-}" ]]; then
            echo "  ✅ fzf (ENABLED)"
        else
            echo "  ⚙️  fzf (available, set SPARKDOCK_ENABLE_FZF=1 to enable)"
        fi
    else
        echo "  ❌ fzf (not installed)"
    fi

    echo ""
    echo "✨ Key Features:"
    echo "  • ls/cat → eza/bat (modern replacements)"
    echo "  • cd → smart zoxide integration with fallback"
    echo "  • ff → fuzzy file finder | Ctrl+R → history search"
    echo "  • z <dir> → smart directory jump | .., ..., .... shortcuts"
    echo "  • Docker, Git, Kubernetes aliases (dc, gs, k, etc.)"
    echo "  • oh-my-zsh plugins (autosuggestions, syntax highlighting)"
    echo ""
    echo "=========================================="
    echo "Available Aliases & Commands"
    echo "=========================================="
    echo ""
    echo "📁 FILE & DIRECTORY:"
    echo "  ls              - Modern eza listing (detects -lt/-ltr flags)"
    echo "  ls -lt          - List by time, newest first"
    echo "  ls -ltr         - List by time, oldest first"
    echo "  lsa             - List all including hidden"
    echo "  lt              - Tree view (2 levels)"
    echo "  lta             - Tree with hidden files"
    echo ""
    echo "🚀 NAVIGATION:"
    echo "  cd <path>       - Smart cd (uses zoxide for partial matches)"
    echo "  ..              - Up one directory"
    echo "  ...             - Up two directories"
    echo "  ....            - Up three directories"
    echo "  z <partial>     - Jump to frequently used directory"
    echo ""
    echo "🔍 SEARCH:"
    echo "  ff              - Fuzzy file finder with preview"
    echo "  rg <pattern>    - Fast ripgrep search"
    echo "  Ctrl+R          - Fuzzy history search"
    echo "  Ctrl+T          - Fuzzy file search"
    echo ""
    echo "📄 VIEWING:"
    echo "  cat <file>      - Syntax highlighted view (bat)"
    echo "  ccat <file>     - Original cat"
    echo ""
    echo "🐳 DOCKER:"
    echo "  dc              - docker-compose"
    echo "  dps, dpsa       - docker ps (all)"
    echo "  di              - docker images"
    echo ""
    echo "🔧 GIT:"
    echo "  gs, gp, gpush   - status, pull, push"
    echo "  gc, gco, ga     - commit, checkout, add"
    echo "  gd, gl          - diff, log (graph)"
    echo ""
    echo "☸️  KUBERNETES:"
    echo "  k               - kubectl"
    echo "  kgp, kgs, kgd   - get pods/services/deployments"
    echo "  kdp, kds, kdd   - describe pod/service/deployment"
    echo "  kl              - logs"
    echo "  kx, kn          - kubectx, kubens"
    echo ""
    echo "⚙️  SYSTEM:"
    echo "  reload          - Reload zsh"
    echo "  path            - Show PATH"
    echo "  h, c            - history, clear"
    echo ""
    echo "💡 Commands:"
    echo "  sjust shell-enable             - Enable shell enhancements"
    echo "  sjust shell-omz-setup          - Install oh-my-zsh and plugins"
    echo "  sjust shell-starship-setup     - Setup default Starship config"
    echo "  sjust shell-eza-setup          - Setup default eza theme"
    echo "  sjust shell-alacritty-setup    - Setup default Alacritty config"
    echo "  sjust shell-ghostty-setup      - Setup default Ghostty config"
    echo ""
    echo "🔧 Optional Features (add to ~/.zshrc before sourcing):"
    echo "  export SPARKDOCK_ENABLE_STARSHIP=1  - Enable starship prompt"
    echo "  export SPARKDOCK_ENABLE_FZF=1       - Enable fzf fuzzy finder"
    echo "  export SPARKDOCK_ENABLE_ATUIN=1     - Enable atuin history sync"
    echo ""
    echo "📚 Configuration:"
    echo "  /opt/sparkdock/config/shell/sparkdock.zshrc"
    echo "  /opt/sparkdock/config/shell/README.md"
    echo "  ~/.config/spark/shell.zsh (customizations)"
    echo "=========================================="
}
