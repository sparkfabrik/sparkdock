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

# Print shared shell enable overview and compute defaults.
# Arguments:
#   $1 - Path to user's zshrc
#   $2 - (optional) Print next steps prompt ("yes" | "no"), defaults to "yes"
sparkdock_print_shell_overview() {
    local zshrc_file="$1"
    local show_next_steps="${2:-yes}"

    HAS_OMZ=false
    HAS_STARSHIP=false
    HAS_ATUIN=false
    HAS_FZF=false

    if [[ -f "${zshrc_file}" ]]; then
        if grep -qE "(source.*oh-my-zsh\.sh|ZSH=)" "${zshrc_file}"; then
            HAS_OMZ=true
        fi
        if grep -qE "starship init (zsh|bash)" "${zshrc_file}"; then
            HAS_STARSHIP=true
        fi
        if grep -qE "atuin init (zsh|bash)" "${zshrc_file}"; then
            HAS_ATUIN=true
        fi
        if grep -qE "(\[ -f.*fzf\.zsh \]|source.*fzf)" "${zshrc_file}"; then
            HAS_FZF=true
        fi
    fi

    DEFAULT_STARSHIP="1"
    DEFAULT_FZF="1"
    DEFAULT_ATUIN="0"

    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║  ✨ Sparkdock Shell Enhancement Installer ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

    echo "Included capabilities:"
    echo "  • Modern aliases: ls→eza, cat→bat, cd→zoxide"
    echo "  • Toolchain on PATH: fd, ripgrep, oh-my-zsh"
    echo "  • Optional modules (managed via SPARKDOCK_ENABLE_*):"
    echo "    - starship prompt — https://starship.rs"
    echo "    - fzf fuzzy finder — https://github.com/junegunn/fzf"
    echo "    - atuin history sync — https://atuin.sh"
    echo "    (override defaults by exporting SPARKDOCK_ENABLE_* before sourcing Sparkdock)"
    echo "  • Profiles Sparkdock keeps in sync (only if not already present):"
    echo "    - ~/.config/alacritty/alacritty.toml"
    echo "    - ~/.config/ghostty/config"
    echo "    - ~/.config/eza/theme.yml"
    echo "    - ~/.config/starship.toml (when starship is enabled)"
    echo ""

    echo "Detected shell configuration (${zshrc_file}):"
    if [[ "${HAS_OMZ}" == "true" ]]; then
        echo "  • oh-my-zsh: detected — Sparkdock retains your plugin setup"
    else
        echo "  • oh-my-zsh: not detected — Sparkdock can initialize it if installed"
    fi

    if [[ "${HAS_STARSHIP}" == "true" ]]; then
        DEFAULT_STARSHIP="0"
        echo "  • starship: detected — Sparkdock skips its prompt initialization"
    else
        echo "  • starship: not detected — default SPARKDOCK_ENABLE_STARSHIP=1"
    fi

    if [[ "${HAS_ATUIN}" == "true" ]]; then
        DEFAULT_ATUIN="0"
        DEFAULT_FZF="0"
        echo "  • atuin: detected — default SPARKDOCK_ENABLE_ATUIN=0"
        echo "  • fzf: managed by atuin — default SPARKDOCK_ENABLE_FZF=0"
    else
        echo "  • atuin: not detected — default SPARKDOCK_ENABLE_ATUIN=0 (set to 1 to enable)"
    fi

    if [[ "${HAS_FZF}" == "true" ]]; then
        DEFAULT_FZF="0"
        echo "  • fzf: detected — existing setup is left untouched"
    elif [[ "${HAS_ATUIN}" != "true" ]]; then
        echo "  • fzf: not detected — default SPARKDOCK_ENABLE_FZF=1"
    fi

    echo ""
    echo "Block to be appended to ${zshrc_file}:"
    echo ""
    echo "if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
    echo "    export SPARKDOCK_ENABLE_STARSHIP=${DEFAULT_STARSHIP}"
    echo "    export SPARKDOCK_ENABLE_FZF=${DEFAULT_FZF}"
    echo "    export SPARKDOCK_ENABLE_ATUIN=${DEFAULT_ATUIN}"
    echo "    source /opt/sparkdock/config/shell/sparkdock.zshrc;"
    echo "    # Set SPARKDOCK_ENABLE_* above this block to change defaults"
    echo "fi"
    echo ""
    echo "📚 Reference files:"
    echo "   • Primary config: /opt/sparkdock/config/shell/sparkdock.zshrc"
    echo "   • Documentation:  /opt/sparkdock/config/shell/README.md"
    echo ""
    echo "✏️ Personal overrides (auto-sourced after Sparkdock):"
    echo "   ~/.config/spark/shell.zsh  — keep custom aliases and exports here"
    echo ""
    if [[ "${show_next_steps}" == "yes" ]]; then
        echo "Proceed with installation by pressing “y”, or cancel with “n”."
        echo "To revisit this summary at any time, run: sjust shell-info"
        echo ""
    fi
}
