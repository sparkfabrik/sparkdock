
# Enable Sparkdock shell enhancements in your zshrc.
# Pass "force" as argument to override declined state: sjust shell-enable force
[group('shell')]
shell-enable $force="false":
    #!/usr/bin/env bash
    set -euo pipefail

    ZSHRC_FILE="${HOME}/.zshrc"
    SPARKDOCK_CHECK_LINE="if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
    DECLINED_FILE="${HOME}/.config/spark/.shell-enable-declined"

    # Create zshrc if it doesn't exist
    touch "${ZSHRC_FILE}"

    echo ""
    echo "╔═══════════════════════════════════════════╗"
    echo "║  ✨ Sparkdock Shell Enhancement Installer ║"
    echo "╚═══════════════════════════════════════════╝"
    echo ""

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

    # Detect existing configurations
    HAS_OMZ=false
    HAS_STARSHIP=false
    HAS_ATUIN=false
    HAS_FZF=false

    if [[ -f "${ZSHRC_FILE}" ]]; then
        if grep -qE "(source.*oh-my-zsh\.sh|ZSH=)" "${ZSHRC_FILE}"; then
            HAS_OMZ=true
        fi
        if grep -qE "starship init (zsh|bash)" "${ZSHRC_FILE}"; then
            HAS_STARSHIP=true
        fi
        if grep -qE "atuin init (zsh|bash)" "${ZSHRC_FILE}"; then
            HAS_ATUIN=true
        fi
        if grep -qE "(\[ -f.*fzf\.zsh \]|source.*fzf)" "${ZSHRC_FILE}"; then
            HAS_FZF=true
        fi
    fi

    DEFAULT_STARSHIP="1"
    DEFAULT_FZF="1"
    DEFAULT_ATUIN="0"
    STARSHIP_COMMENT="Enabled by default"
    FZF_COMMENT="Enabled by default"
    ATUIN_COMMENT="Disabled by default"

    echo ""
    echo "🎯 Core tooling (always enabled):"
    echo "   • eza (modern ls)"
    echo "   • fd (faster find)"
    echo "   • ripgrep (fast search)"
    echo "   • bat (syntax-highlighted cat)"
    echo "   • zoxide (smart cd)"
    echo "   • oh-my-zsh (plugin framework)"
    echo ""
    echo "✨ Optional extras (toggled via SPARKDOCK_ENABLE_*):"
    echo "   • starship prompt"
    echo "   • fzf fuzzy finder"
    echo "   • atuin history sync"
    echo ""
    echo "📁 Terminal configs (symlinked if not present):"
    echo "   • ~/.config/alacritty/alacritty.toml"
    echo "   • ~/.config/ghostty/config"
    echo "   • ~/.config/eza/theme.yml"
    echo "   • ~/.config/starship.toml (if starship enabled)"
    echo ""
    echo "🔍 Detected in ${ZSHRC_FILE}:"
    if [[ "${HAS_OMZ}" == "true" ]]; then
        echo "  • ✅ oh-my-zsh already configured → Sparkdock keeps your plugin setup"
    else
        echo "  • ⚪ oh-my-zsh not detected → Sparkdock will initialize it if present"
    fi

    if [[ "${HAS_STARSHIP}" == "true" ]]; then
        DEFAULT_STARSHIP="0"
        STARSHIP_COMMENT="Already configured; Sparkdock skips initialization"
        echo "  • ✅ starship already configured → Sparkdock will skip its own init"
    else
        echo "  • ⚡ starship not detected → Sparkdock enables SPARKDOCK_ENABLE_STARSHIP=1"
    fi

    if [[ "${HAS_ATUIN}" == "true" ]]; then
        DEFAULT_ATUIN="0"
        ATUIN_COMMENT="Already configured; Sparkdock skips initialization"
        DEFAULT_FZF="0"
        FZF_COMMENT="Disabled because atuin manages fuzzy history"
        echo "  • ✅ atuin already configured → Sparkdock leaves SPARKDOCK_ENABLE_ATUIN=0"
        echo "  • 🔄 atuin provides history search → Sparkdock leaves fzf disabled"
    else
        echo "  • 💤 atuin not detected → stays disabled (set SPARKDOCK_ENABLE_ATUIN=1 to enable)"
    fi

    if [[ "${HAS_FZF}" == "true" ]]; then
        DEFAULT_FZF="0"
        FZF_COMMENT="Already configured; Sparkdock skips integration"
        echo "  • ✅ fzf already configured → Sparkdock will not override your setup"
    elif [[ "${HAS_ATUIN}" != "true" ]]; then
        echo "  • ✨ fzf not detected → Sparkdock enables SPARKDOCK_ENABLE_FZF=1"
    fi

    echo ""
    echo "This will add the following configuration to ${ZSHRC_FILE}:"
    echo ""
    echo "  if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
    echo "    export SPARKDOCK_ENABLE_STARSHIP=${DEFAULT_STARSHIP}  # ${STARSHIP_COMMENT}"
    echo "    export SPARKDOCK_ENABLE_FZF=${DEFAULT_FZF}  # ${FZF_COMMENT}"
    echo "    export SPARKDOCK_ENABLE_ATUIN=${DEFAULT_ATUIN}  # ${ATUIN_COMMENT}"
    echo "    source /opt/sparkdock/config/shell/sparkdock.zshrc;"
    echo "  fi"
    echo ""
    echo "📚 Want to explore all features? Run: sjust shell-info"
    echo ""

    read -p "Do you want to enable Sparkdock shell enhancements? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Shell enhancement setup cancelled"
        echo ""
        mkdir -p "${HOME}/.config/spark"
        touch "${DECLINED_FILE}"
        echo "💡 If you change your mind later, run: sjust shell-enable force"
        exit 0
    fi

    # Install oh-my-zsh if not already installed
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        echo ""
        echo "📦 Installing oh-my-zsh..."
        sjust shell-omz-setup
        echo ""
    fi

    BACKUP_FILE="${ZSHRC_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "${ZSHRC_FILE}" "${BACKUP_FILE}"
    echo "✅ Backup created: ${BACKUP_FILE}"
    echo ""
    {
        echo ""
        echo "# Sparkdock shell enhancements"
        echo "if [ -f /opt/sparkdock/config/shell/sparkdock.zshrc ]; then"
        echo "  export SPARKDOCK_ENABLE_STARSHIP=1"
        echo "  export SPARKDOCK_ENABLE_FZF=1"
        echo "  export SPARKDOCK_ENABLE_ATUIN=0"
        echo "  source /opt/sparkdock/config/shell/sparkdock.zshrc;"
        echo "fi"
    } >> "${ZSHRC_FILE}"
    echo "✅ Sparkdock shell enhancements enabled in ${ZSHRC_FILE}"
    echo ""

    # Setup configurations for tools if they will be enabled
    if command -v starship &> /dev/null && [[ "${HAS_STARSHIP}" == "false" ]]; then
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
    BACKUP_FILE="${ZSHRC_FILE}.backup.$(date +%Y%m%d%H%M%S)"
    cp "${ZSHRC_FILE}" "${BACKUP_FILE}"
    echo "✅ Backup created: ${BACKUP_FILE}"

    # Remove the entire Sparkdock configuration block from zshrc
    # This removes the comment line and the entire if block
    sed -i.tmp -e '/# Sparkdock shell enhancements/,/^fi$/d' "${ZSHRC_FILE}"
    rm -f "${ZSHRC_FILE}.tmp"

    echo "✅ Sparkdock shell enhancements disabled from ${ZSHRC_FILE}"
    echo "💡 You can remove \"~/.oh-my-zsh\" if you no longer need it."
    echo "💡 Backup saved to ${BACKUP_FILE}"
    echo "💡 Run 'source ~/.zshrc' or restart your terminal to deactivate"

# Show information about Sparkdock shell enhancements and aliases.
[group('shell')]
shell-info:
    #!/usr/bin/env bash
    set -euo pipefail
    source /opt/sparkdock/sjust/libs/libshell.sh
    print_shell_info

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
    source /opt/sparkdock/sjust/libs/libshell.sh

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
