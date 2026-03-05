#!/usr/bin/env bash
# Sparkdock Shell Utilities
# Shared functions for shell configuration management

# Source shared logging library
# shellcheck source=../../bin/common/logging.sh
source "$(dirname "${BASH_SOURCE[0]}")/../../bin/common/logging.sh"

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

# Create a timestamped backup of a file
# Usage: sparkdock_backup_file <file_path>
# Returns: The backup file path via stdout
sparkdock_backup_file() {
    local file_path="$1"
    local backup_file
    backup_file="${file_path}.backup.$(date +%Y%m%d%H%M%S)"

    cp "${file_path}" "${backup_file}"
    echo "✅ Backup created: ${backup_file}"
    echo ""

    # Return the backup file path for potential use
    echo "${backup_file}"
}

sparkdock_has_starship() {
    if grep -qE "starship init (zsh|bash)" "${1}"; then
        return 0
    else
        return 1
    fi
}

sparkdock_has_omz() {
    if grep -qE "(source.*oh-my-zsh\.sh|ZSH=)" "${1}"; then
        return 0
    else
        return 1
    fi
}

sparkdock_has_atuin() {
    if grep -qE "atuin init (zsh|bash)" "${1}"; then
        return 0
    else
        return 1
    fi
}

sparkdock_has_fzf() {
    if grep -qE "(\[ -f.*fzf\.zsh \]|source.*fzf)" "${1}"; then
        return 0
    else
        return 1
    fi
}

sparkdock_print_openai_key_instructions() {
    cat <<'EOF'
⚠️  OPENAI_API_KEY is required for sparkdock-ai

   ⚠️  IMPORTANT: Replace YOUR_SECRET_NAME and YOUR_GCP_PROJECT with your actual values!

   • Add to ${HOME}/.config/spark/shell.zsh:
       function export_openai_key() {
         export OPENAI_API_KEY=$(gcloud secrets versions access "latest" --secret YOUR_SECRET_NAME --project YOUR_GCP_PROJECT)
       }

   • Run `export_openai_key` before launching sparkdock-ai.
   • Need help? Check in on #support-tech (Slack).
EOF
}

# Compute default values for shell enhancements based on existing configuration
# Arguments:
#   $1 - Path to user's zshrc
# Sets global variables: DEFAULT_STARSHIP, DEFAULT_FZF, DEFAULT_ATUIN
sparkdock_compute_defaults() {
    local zshrc_file="$1"

    HAS_OMZ=false
    HAS_STARSHIP=false
    HAS_ATUIN=false
    HAS_FZF=false

    if [[ -f "${zshrc_file}" ]]; then
        if sparkdock_has_omz "${zshrc_file}"; then
            HAS_OMZ=true
        fi
        if sparkdock_has_starship "${zshrc_file}"; then
            HAS_STARSHIP=true
        fi
        if sparkdock_has_atuin "${zshrc_file}"; then
            HAS_ATUIN=true
        fi
        if sparkdock_has_fzf "${zshrc_file}"; then
            HAS_FZF=true
        fi
    fi

    DEFAULT_STARSHIP="1"
    DEFAULT_FZF="1"
    DEFAULT_ATUIN="0"

    if [[ "${HAS_STARSHIP}" == "true" ]]; then
        DEFAULT_STARSHIP="0"
    fi

    if [[ "${HAS_ATUIN}" == "true" ]]; then
        DEFAULT_ATUIN="0"
        DEFAULT_FZF="0"
    fi

    if [[ "${HAS_FZF}" == "true" ]]; then
        DEFAULT_FZF="0"
    fi
}

# Write the Sparkdock shell configuration block to a file
# Arguments:
#   $1 - Path to the zshrc file to append to
sparkdock_write_shell_config() {
    local zshrc_file="$1"

    # Create backup
    sparkdock_backup_file "${zshrc_file}" > /dev/null

    # Compute defaults first
    sparkdock_compute_defaults "${zshrc_file}"

    {
        echo ""
        echo "# Sparkdock shell enhancements"
        echo "if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
        printf '    export SPARKDOCK_ENABLE_STARSHIP=%s\n' "${DEFAULT_STARSHIP}"
        printf '    export SPARKDOCK_ENABLE_FZF=%s\n' "${DEFAULT_FZF}"
        printf '    export SPARKDOCK_ENABLE_ATUIN=%s\n' "${DEFAULT_ATUIN}"
        echo "    source /opt/sparkdock/config/shell/sparkdock.zshrc;"
        echo "fi"
    } >> "${zshrc_file}"
}

# Print shared shell enable overview and compute defaults.
# Arguments:
#   $1 - Path to user's zshrc
#   $2 - (optional) Print next steps prompt ("yes" | "no"), defaults to "yes"
sparkdock_print_shell_overview() {
    local zshrc_file="$1"
    local show_next_steps="${2:-yes}"

    # Compute defaults first
    sparkdock_compute_defaults "${zshrc_file}"

    echo ""
    log_section "✨ Sparkdock Shell Enhancement Installer"
    echo ""

    echo "Included capabilities:"
    echo ""
    echo "  • Modern aliases: ls→eza, cat→bat, cd→zoxide, img2terminal (chafa)"
    echo "  • Toolchain on PATH: fd, ripgrep, oh-my-zsh"
    echo "  • Optional modules (managed via SPARKDOCK_ENABLE_*):"
    echo "    - starship prompt — https://starship.rs"
    echo "    - fzf fuzzy finder — https://github.com/junegunn/fzf"
    echo "    - atuin history sync — https://atuin.sh"
    echo "    (defaults: starship=ON, fzf=ON, atuin=OFF — override by exporting SPARKDOCK_ENABLE_* before sourcing)"
    echo "  • Profiles Sparkdock keeps in sync (only if not already present):"
    echo "    - ~/.config/ghostty/config"
    echo "    - ~/.config/eza/theme.yml"
    echo "    - ~/.config/starship.toml (when starship is enabled)"
    echo ""

    echo "Detected shell configuration (${zshrc_file}):"
    if [[ "${HAS_OMZ}" == "true" ]]; then
        echo "  🟢 oh-my-zsh: detected — Sparkdock retains your plugin setup"
    else
        echo "  ⚪ oh-my-zsh: not detected — run 'sjust shell-omz-setup' to install (Sparkdock keeps defaults otherwise)"
    fi

    if [[ "${HAS_STARSHIP}" == "true" ]]; then
        echo "  🟢 starship: detected — Sparkdock skips its prompt initialization"
    else
        echo "  ⚪ starship: not detected — default SPARKDOCK_ENABLE_STARSHIP=1 (prompt turns ON unless you set it to 0)"
    fi

    if [[ "${HAS_ATUIN}" == "true" ]]; then
        echo "  🟢 atuin: detected — Sparkdock leaves SPARKDOCK_ENABLE_ATUIN=0 (history stays opt-in)"
        echo "  🟡 fzf: managed by atuin — Sparkdock sets SPARKDOCK_ENABLE_FZF=0 to avoid conflicts"
    else
        echo "  ⚪ atuin: not detected — default SPARKDOCK_ENABLE_ATUIN=0 (set to 1 before sourcing to enable history sync)"
    fi

    if [[ "${HAS_FZF}" == "true" ]]; then
        echo "  🟢 fzf: detected — existing setup is left untouched (Sparkdock leaves SPARKDOCK_ENABLE_FZF=0)"
    elif [[ "${HAS_ATUIN}" != "true" ]]; then
        echo "  ⚪ fzf: not detected — default SPARKDOCK_ENABLE_FZF=1 (fuzzy finder turns ON unless you set it to 0)"
    fi

    echo ""
    echo "📚 Reference files:"
    echo "   • Primary config: /opt/sparkdock/config/shell/sparkdock.zshrc"
    echo "   • Documentation:  /opt/sparkdock/config/shell/README.md"
    echo "   • Alias catalog:  /opt/sparkdock/config/shell/aliases.zsh"
    echo ""
    echo "✏️ Personal overrides (auto-sourced after Sparkdock):"
    echo "   ~/.config/spark/shell.zsh  — keep custom aliases and exports here"
    echo ""
    echo "Block to be appended to ${zshrc_file}:"
    echo ""
    echo "+ if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
    echo "+     export SPARKDOCK_ENABLE_STARSHIP=${DEFAULT_STARSHIP}"
    echo "+     export SPARKDOCK_ENABLE_FZF=${DEFAULT_FZF}"
    echo "+     export SPARKDOCK_ENABLE_ATUIN=${DEFAULT_ATUIN}"
    echo "+     source /opt/sparkdock/config/shell/sparkdock.zshrc;"
    echo "+     # Set SPARKDOCK_ENABLE_* above this block to change defaults"
    echo "+ fi"
    echo ""

    if [[ "${show_next_steps}" == "yes" ]]; then
        echo "Proceed with installation by pressing \"y\", or cancel with \"n\"."
        echo "To revisit this summary at any time, run: sjust shell-info"
        echo ""
    fi
}

# Setup Ghostty configuration using config-file directive
# This creates a two-file setup: main config + user overrides file.
# This ensures proper load order per Ghostty's documentation:
# 1. Main config is parsed (including config-file directives)
# 2. Sparkdock base config is loaded (first config-file)
# 3. User overrides are loaded (second config-file = user)
# Arguments: None (uses standard paths)
sparkdock_setup_ghostty_config() {
    local USER_CONFIG="${HOME}/.config/ghostty/config"
    local USER_OVERRIDES="${HOME}/.config/ghostty/user"
    local SPARKDOCK_CONFIG="/opt/sparkdock/config/shell/config/ghostty/config"

    # Check if user config already exists and is not empty
    if [[ -f "${USER_CONFIG}" && -s "${USER_CONFIG}" ]]; then
        # Check if it's a symlink
        if [[ -L "${USER_CONFIG}" ]]; then
            echo "⚠️  Ghostty config is a symlink, removing to create config-file based setup..."
            rm "${USER_CONFIG}"
        else
            # Check if it already has the proper two-file setup
            if grep -q "config-file = user" "${USER_CONFIG}" 2>/dev/null; then
                echo "✅ Ghostty config already properly configured with two-file setup"
                echo "📄 Main config: ${USER_CONFIG}"
                echo "📄 User overrides: ${USER_OVERRIDES}"
                echo "📄 Sparkdock config: ${SPARKDOCK_CONFIG}"
                echo ""
                echo "ℹ️  You can customize your Ghostty configuration by editing:"
                echo "   ${USER_OVERRIDES}"
                echo ""
                echo "   Any settings you add will override Sparkdock defaults."
                return 0
            else
                echo "✅ Ghostty config already exists (user-managed)"
                echo "📄 Config location: ${USER_CONFIG}"
                echo ""
                echo "ℹ️  To use Sparkdock's Ghostty configuration with proper overrides, replace with:"
                echo "   config-file = ${SPARKDOCK_CONFIG}"
                echo "   config-file = user"
                echo ""
                echo "   Then create ${USER_OVERRIDES} with your customizations."
                return 0
            fi
        fi
    fi

    # Create new config with two config-file directives
    echo "📦 Setting up Ghostty configuration with two-file setup..."
    mkdir -p "$(dirname "${USER_CONFIG}")"

    cat > "${USER_CONFIG}" << 'EOF'
# Ghostty Configuration
# This file loads Sparkdock's base configuration and allows you to override settings.
# Documentation: https://ghostty.org/docs/config

# Load Sparkdock base configuration
config-file = /opt/sparkdock/config/shell/config/ghostty/config

# Load user configuration/overrides
config-file = user
EOF

    # Create user overrides file
    cat > "${USER_OVERRIDES}" << 'EOF'
# Ghostty User Overrides
# Add your custom overrides below this line.
# These settings will override Sparkdock defaults.
# Documentation: https://ghostty.org/docs/config
#
# Example:
# font-size = 16
# theme = Nord
EOF

    echo "✅ Ghostty config created at ${USER_CONFIG}"
    echo "✅ User overrides file created at ${USER_OVERRIDES}"
    echo "📄 Sparkdock config: ${SPARKDOCK_CONFIG}"
    echo ""
    echo "ℹ️  Configuration uses two-file setup for proper override support:"
    echo "   - Base settings loaded from: ${SPARKDOCK_CONFIG}"
    echo "   - Customize by editing: ${USER_OVERRIDES}"
    echo "   - Your settings in 'user' file override Sparkdock defaults"
    echo "   - Changes reload automatically in Ghostty"
}
