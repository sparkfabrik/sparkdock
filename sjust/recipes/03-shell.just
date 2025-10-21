
# Enable Sparkdock shell enhancements in your zshrc.
# Pass "force" as argument to override declined state: sjust shell-enable force
[group('shell')]
shell-enable $force="false":
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{justfile_directory()}}/../libs/libshell.sh"

    ZSHRC_FILE="${HOME}/.zshrc"
    SPARKDOCK_CHECK_LINE="if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
    DECLINED_FILE="${HOME}/.config/spark/.shell-enable-declined"

    # Create zshrc if it doesn't exist
    touch "${ZSHRC_FILE}"

    # Check if user previously declined (unless force is true)
    if [[ -f "${DECLINED_FILE}" ]] && [[ "${force}" != "force" ]]; then
        echo "ℹ️ You previously declined to enable Sparkdock shell enhancements"
        echo "💡 To enable anyway, run: sjust shell-enable force"
        exit 0
    fi

    # Remove declined file if forcing installation
    if [[ -f "${DECLINED_FILE}" ]] && [[ "${force}" == "force" ]]; then
        rm -f "${DECLINED_FILE}"
        echo "🔄 Removed declined marker, proceeding with installation..."
        echo ""
    fi

    # Check if already enabled
    if grep -qF "${SPARKDOCK_CHECK_LINE}" "${ZSHRC_FILE}"; then
        echo "ℹ️  Sparkdock shell enhancements are already enabled in ${ZSHRC_FILE}"
        echo ""
        echo "If you want reinstall again:"
        echo "  1) Run 'sjust shell-disable' to remove existing configuration"
        echo "  2) Run 'sjust shell-enable' to enable again"
        exit 0
    fi

    sparkdock_print_shell_overview "${ZSHRC_FILE}"

    read -p "Do you want to enable Sparkdock shell enhancements? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo "❌ Shell enhancement setup cancelled"
        echo ""
        mkdir -p "${HOME}/.config/spark"
        touch "${DECLINED_FILE}"
        echo "💡 If you change your mind later, run: sjust shell-enable force"
        exit 0
    fi

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Invalid response. Please run the command again and answer 'y' or 'n'"
        exit 1
    fi

    # Install oh-my-zsh if not already installed
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        echo ""
        echo "📦 Installing oh-my-zsh..."
        sjust shell-omz-setup
        echo ""
    fi

    sparkdock_write_shell_config "${ZSHRC_FILE}"
    echo "✅ Sparkdock shell enhancements enabled in ${ZSHRC_FILE}"
    echo ""

    # Setup configurations for tools if they will be enabled
    if command -v starship &> /dev/null && sparkdock_has_starship "${ZSHRC_FILE}"; then
        sjust shell-starship-setup 2>/dev/null || true
    fi

    if command -v eza &> /dev/null; then
        sjust shell-eza-setup 2>/dev/null || true
    fi

    # Setup terminal configurations
    sjust shell-alacritty-setup 2>/dev/null || true
    sjust shell-ghostty-setup 2>/dev/null || true

    echo "💡 Run 'source ~/.zshrc' or restart your terminal to activate"

# Disable Sparkdock shell enhancements from your zshrc.
[group('shell')]
shell-disable:
    #!/usr/bin/env bash
    set -euo pipefail

    ZSHRC_FILE="${HOME}/.zshrc"
    SPARKDOCK_CHECK_LINE="if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"

    if ! grep -qF "${SPARKDOCK_CHECK_LINE}" "${ZSHRC_FILE}"; then
        echo "ℹ️  Sparkdock shell enhancements are not enabled in ${ZSHRC_FILE}"
        exit 0
    fi

    # Create a backup
    BACKUP_FILE=$(sparkdock_backup_file "${ZSHRC_FILE}" | grep '^/' | head -n 1)

    # Remove the entire Sparkdock configuration block from zshrc
    # This removes the comment line and the entire if block
    sed -i.tmp -e '/# Sparkdock shell enhancements/,/^fi$/d' "${ZSHRC_FILE}"
    rm -f "${ZSHRC_FILE}.tmp"

    echo "✅ Sparkdock shell enhancements disabled from ${ZSHRC_FILE}"
    echo "💡 You can remove \"~/.oh-my-zsh\" if you no longer need it."
    echo "💡 Backup saved to ${BACKUP_FILE}"
    echo "💡 Run 'source ~/.zshrc' or restart your terminal to deactivate"

# Show Sparkdock shell enable overview.
[group('shell')]
shell-info:
    #!/usr/bin/env bash
    set -euo pipefail
    source "{{justfile_directory()}}/../libs/libshell.sh"
    sparkdock_print_shell_overview "${HOME}/.zshrc" "no"

# Setup oh-my-zsh and zsh plugins.
[group('shell')]
shell-omz-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=========================================="
    echo "Setting up oh-my-zsh and zsh plugins"
    echo "=========================================="
    echo ""

    # Install oh-my-zsh if not already installed
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        echo "📦 Installing oh-my-zsh..."

        # Download installer with integrity verification
        OMZ_INSTALL_SCRIPT="/tmp/omz-install-$$.sh"
        echo "📥 Downloading oh-my-zsh installer..."
        curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o "${OMZ_INSTALL_SCRIPT}"

        # Show checksum for verification
        echo "🔐 Installer SHA256 checksum:"
        shasum -a 256 "${OMZ_INSTALL_SCRIPT}"
        echo ""
        echo "💡 You can verify this checksum at: https://github.com/ohmyzsh/ohmyzsh"
        echo ""

        # Execute the installer with KEEP_ZSHRC to preserve user's .zshrc
        KEEP_ZSHRC=yes sh "${OMZ_INSTALL_SCRIPT}" --unattended
        rm -f "${OMZ_INSTALL_SCRIPT}"

        echo "✅ oh-my-zsh installed"
    else
        # Update oh-my-zsh if already installed.
        echo "📦 Updating oh-my-zsh..."
        git -C "$HOME/.oh-my-zsh" pull --quiet
    fi

    # Create plugins directory
    PLUGINS_DIR="${HOME}/.config/spark/zsh-plugins"
    mkdir -p "${PLUGINS_DIR}"

    # Install zsh-completions
    if [[ -d "${PLUGINS_DIR}/zsh-completions" ]]; then
        echo "📦 Updating zsh-completions..."
        git -C "${PLUGINS_DIR}/zsh-completions" pull --quiet
    else
        echo "📦 Installing zsh-completions..."
        git clone --quiet https://github.com/zsh-users/zsh-completions "${PLUGINS_DIR}/zsh-completions"
    fi

    # Install zsh-autosuggestions
    if [[ -d "${PLUGINS_DIR}/zsh-autosuggestions" ]]; then
        echo "📦 Updating zsh-autosuggestions..."
        git -C "${PLUGINS_DIR}/zsh-autosuggestions" pull --quiet
    else
        echo "📦 Installing zsh-autosuggestions..."
        git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "${PLUGINS_DIR}/zsh-autosuggestions"
    fi

    # Install zsh-syntax-highlighting
    if [[ -d "${PLUGINS_DIR}/zsh-syntax-highlighting" ]]; then
        echo "📦 Updating zsh-syntax-highlighting..."
        git -C "${PLUGINS_DIR}/zsh-syntax-highlighting" pull --quiet
    else
        echo "📦 Installing zsh-syntax-highlighting..."
        git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting "${PLUGINS_DIR}/zsh-syntax-highlighting"
    fi

    echo ""
    echo "📂 Creating symlinks to oh-my-zsh custom plugins..."

    # Create oh-my-zsh custom plugins directory
    mkdir -p "$HOME/.oh-my-zsh/custom/plugins"

    # Symlink plugins to oh-my-zsh
    ln -sf "${PLUGINS_DIR}/zsh-completions" "$HOME/.oh-my-zsh/custom/plugins/zsh-completions"
    ln -sf "${PLUGINS_DIR}/zsh-autosuggestions" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
    ln -sf "${PLUGINS_DIR}/zsh-syntax-highlighting" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"

    echo "✅ Symlinks created"
    echo ""
    echo "✅ Setup complete!"
    echo ""
    echo "The following plugins are now available:"
    echo "  - zsh-completions"
    echo "  - zsh-autosuggestions"
    echo "  - zsh-syntax-highlighting"
    echo "  - ssh-agent (built-in to oh-my-zsh)"
    echo ""
    echo "Plugins are automatically enabled when you source sparkdock.zshrc"
    echo "Configuration is in: /opt/sparkdock/config/shell/omz-init.zsh"
    echo ""
    echo "💡 To update on-my-zsh and plugins in the future, simply re-run 'sjust shell-omz-setup'"

# Setup Starship prompt configuration.
[group('shell')]
shell-starship-setup:
    @just _shell-config-setup \
        "starship" \
        "${HOME}/.config/starship.toml" \
        "/opt/sparkdock/config/shell/config/starship/starship.toml" \
        "config at ~/.config/starship.toml" \
        "See https://starship.rs/config/ for configuration options"

# Setup eza theme configuration.
[group('shell')]
shell-eza-setup:
    @just _shell-config-setup \
        "eza" \
        "${HOME}/.config/eza/theme.yml" \
        "/opt/sparkdock/config/shell/config/eza/theme.yml" \
        "theme at ~/.config/eza/theme.yml" \
        "Based on Catppuccin color scheme"

# Generic configuration setup helper (internal use).
_shell-config-setup tool_name config_path sparkdock_path config_description setup_info:
    #!/usr/bin/env bash
    source "{{justfile_directory()}}/../libs/libshell.sh"

    USER_CONFIG="{{config_path}}"
    SPARKDOCK_CONFIG="{{sparkdock_path}}"

    check_sparkdock_symlink "${USER_CONFIG}" "${SPARKDOCK_CONFIG}"
    status=$?

    if [[ ${status} -ne 2 ]]; then
        print_config_status "{{tool_name}}" "${status}" "${USER_CONFIG}" "${SPARKDOCK_CONFIG}" "{{config_description}}"
        echo ""
        exit 0
    fi

    echo "📦 Setting up default {{tool_name}} config..."
    mkdir -p "$(dirname "${USER_CONFIG}")"
    ln -sf "${SPARKDOCK_CONFIG}" "${USER_CONFIG}"
    echo "✅ Default {{tool_name}} config symlinked to ${USER_CONFIG}"
    print_setup_complete "${USER_CONFIG}" "${SPARKDOCK_CONFIG}" "{{setup_info}}"

# Setup Alacritty configuration.
[group('shell')]
shell-alacritty-setup:
    @just _shell-config-setup \
        "alacritty" \
        "${HOME}/.config/alacritty/alacritty.toml" \
        "/opt/sparkdock/config/shell/config/alacritty/alacritty.toml" \
        "config at ~/.config/alacritty/alacritty.toml" \
        "Based on Catppuccin Mocha theme with JetBrains Mono font"

# Setup Ghostty configuration.
[group('shell')]
shell-ghostty-setup:
    @just _shell-config-setup \
        "ghostty" \
        "${HOME}/.config/ghostty/config" \
        "/opt/sparkdock/config/shell/config/ghostty/config" \
        "config at ~/.config/ghostty/config" \
        "Based on Catppuccin Mocha theme"
