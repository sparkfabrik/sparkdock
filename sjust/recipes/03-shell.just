
# Enable Sparkdock shell enhancements in your zshrc.
[group('shell')]
shell-enable:
    #!/usr/bin/env bash
    set -euo pipefail

    ZSHRC_FILE="${HOME}/.zshrc"
    SPARKDOCK_SOURCE_LINE="if [ -d /opt/sparkdock ]; then source /opt/sparkdock/config/shell/sparkdock.zshrc; fi"

    # Create zshrc if it doesn't exist
    touch "${ZSHRC_FILE}"

    # Check if already enabled
    if grep -qF "${SPARKDOCK_SOURCE_LINE}" "${ZSHRC_FILE}"; then
        echo "ℹ️  Sparkdock shell enhancements are already enabled in ${ZSHRC_FILE}"
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

    echo ""
    echo "🔍 Detected configurations in ${ZSHRC_FILE}:"
    if [[ "${HAS_OMZ}" == "true" ]]; then
        echo "  ✅ oh-my-zsh is configured → Sparkdock will respect your existing configuration"
    else
        echo "  ⚪ oh-my-zsh not detected → Sparkdock will initialize it if installed"
    fi

    if [[ "${HAS_STARSHIP}" == "true" ]]; then
        echo "  ✅ starship is configured → Sparkdock will not load starship (yours will be used)"
    else
        echo "  ⚪ starship not detected → Available as opt-in (set SPARKDOCK_ENABLE_STARSHIP=1)"
    fi

    if [[ "${HAS_ATUIN}" == "true" ]]; then
        echo "  ✅ atuin is configured → Sparkdock will not load atuin or fzf (yours will be used)"
    else
        echo "  ⚪ atuin not detected → Available as opt-in (set SPARKDOCK_ENABLE_ATUIN=1)"
    fi

    if [[ "${HAS_FZF}" == "true" ]]; then
        echo "  ✅ fzf is configured → Sparkdock will skip fzf initialization"
    else
        echo "  ⚪ fzf not detected → Sparkdock will initialize fzf if installed"
    fi

    echo ""
    echo "This will add the following line to ${ZSHRC_FILE}:"
    echo "  ${SPARKDOCK_SOURCE_LINE}"
    echo ""
    echo "📦 Core tools auto-enabled: eza, fd, ripgrep, bat, fzf, zoxide"
    echo "🔧 Optional tools (add env vars to enable): starship, atuin"
    echo ""
    echo "💡 To see what features and aliases will be available, run:"
    echo "   sjust shell-info"
    echo ""

    read -p "Do you want to enable Sparkdock shell enhancements? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "${ZSHRC_FILE}" "${ZSHRC_FILE}.sparkdockbackup"
        echo ""
        echo "✅ Backup created: ${ZSHRC_FILE}.sparkdockbackup"
        echo ""
        {
            echo ""
            echo "# Sparkdock shell enhancements"
            echo "${SPARKDOCK_SOURCE_LINE}"
        } >> "${ZSHRC_FILE}"
        echo "✅ Sparkdock shell enhancements enabled in ${ZSHRC_FILE}"
        echo ""
        echo "💡 Run 'source ~/.zshrc' or restart your terminal to activate"
    else
        echo "❌ Shell enhancement setup cancelled"
    fi

# Disable Sparkdock shell enhancements from your zshrc.
[group('shell')]
shell-disable:
    #!/usr/bin/env bash
    set -euo pipefail

    ZSHRC_FILE="${HOME}/.zshrc"
    SPARKDOCK_SOURCE_LINE="if [ -d /opt/sparkdock ]; then source /opt/sparkdock/config/shell/sparkdock.zshrc; fi"

    if ! grep -qF "${SPARKDOCK_SOURCE_LINE}" "${ZSHRC_FILE}"; then
        echo "ℹ️  Sparkdock shell enhancements are not enabled in ${ZSHRC_FILE}"
        exit 0
    fi

    # Create a backup
    cp "${ZSHRC_FILE}" "${ZSHRC_FILE}.backup"

    # Remove the Sparkdock lines from zshrc
    sed -i.tmp -e '/# Sparkdock shell enhancements/d' -e "\|${SPARKDOCK_SOURCE_LINE}|d" "${ZSHRC_FILE}"
    rm -f "${ZSHRC_FILE}.tmp"

    echo "✅ Sparkdock shell enhancements disabled from ${ZSHRC_FILE}"
    echo "💡 Backup saved to ${ZSHRC_FILE}.backup"
    echo "💡 Run 'source ~/.zshrc' or restart your terminal to deactivate"

# Show information about Sparkdock shell enhancements and aliases.
[group('shell')]
shell-info:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=========================================="
    echo "Sparkdock Shell Enhancements"
    echo "=========================================="
    echo ""
    echo "🎨 Configuration Status:"
    ZSHRC_FILE="${HOME}/.zshrc"
    SPARKDOCK_SOURCE_LINE="if [ -d /opt/sparkdock ]; then source /opt/sparkdock/config/shell/sparkdock.zshrc; fi"

    if [[ -f "${ZSHRC_FILE}" ]] && grep -qF "${SPARKDOCK_SOURCE_LINE}" "${ZSHRC_FILE}"; then
        echo "  ✅ Enabled in ${ZSHRC_FILE}"
    else
        echo "  ❌ Not enabled - Run 'sjust shell-enable' to enable"
    fi

    if [[ -d "$HOME/.oh-my-zsh" ]]; then
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

    echo ""
    echo "✨ Key Features:"
    echo "  • ls/cat → eza/bat (modern replacements)"
    echo "  • cd → smart zoxide integration with fallback"
    echo "  • ff → fuzzy file finder | Ctrl+R → history search"
    echo "  • z <dir> → smart directory jump | .., ..., .... shortcuts"
    echo "  • Docker, Git, Kubernetes aliases (dc, gs, k, etc.)"
    echo "  • oh-my-zsh plugins (autosuggestions, syntax highlighting)"
    echo ""
    echo "==========================================="
    echo "Available Aliases & Commands"
    echo "==========================================="
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
    echo "  sjust shell-enable     - Enable shell enhancements"
    echo "  sjust shell-omz-setup         - Install oh-my-zsh and plugins"
    echo "  sjust shell-omz-update-plugins - Update oh-my-zsh plugins"
    echo ""
    echo "🔧 Optional Features (add to ~/.zshrc before sourcing):"
    echo "  export SPARKDOCK_ENABLE_STARSHIP=1  - Enable starship"
    echo "  export SPARKDOCK_ENABLE_ATUIN=1     - Enable atuin"
    echo ""
    echo "📚 Configuration:"
    echo "  /opt/sparkdock/config/shell/sparkdock.zshrc"
    echo "  /opt/sparkdock/config/shell/README.md"
    echo "  ~/.config/spark/shell.zsh (customizations)"
    echo "=========================================="

# Setup oh-my-zsh and zsh plugins.
[group('shell')]
shell-omz-setup:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "=========================================="
    echo "Setting up oh-my-zsh and zsh plugins"
    echo "=========================================="
    echo ""

    # Check if oh-my-zsh is already configured in user's .zshrc
    ZSHRC_FILE="${HOME}/.zshrc"
    OMZ_ALREADY_CONFIGURED=false

    if [[ -f "${ZSHRC_FILE}" ]]; then
        if grep -q "oh-my-zsh.sh" "${ZSHRC_FILE}" || grep -q "ZSH=" "${ZSHRC_FILE}"; then
            OMZ_ALREADY_CONFIGURED=true
            echo "ℹ️  oh-my-zsh appears to be already configured in your .zshrc"
            echo "   Sparkdock will respect your existing configuration"
            echo ""
        fi
    fi

    # Install oh-my-zsh if not already installed
    if [[ ! -d "$HOME/.oh-my-zsh" ]]; then
        if [[ "${OMZ_ALREADY_CONFIGURED}" == "true" ]]; then
            echo "⚠️  Warning: oh-my-zsh is referenced in .zshrc but not installed at ~/.oh-my-zsh"
            echo ""
        fi
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
        echo "✅ oh-my-zsh already installed"
        if [[ "${OMZ_ALREADY_CONFIGURED}" == "true" ]]; then
            echo "   Using your existing oh-my-zsh configuration from .zshrc"
        fi
    fi
    echo ""

    # If user has their own oh-my-zsh config, ask if they want Sparkdock plugins
    if [[ "${OMZ_ALREADY_CONFIGURED}" == "true" ]]; then
        echo "Sparkdock provides these oh-my-zsh plugins:"
        echo "  - zsh-completions (additional completion definitions)"
        echo "  - zsh-autosuggestions (fish-like autosuggestions)"
        echo "  - zsh-syntax-highlighting (syntax highlighting for commands)"
        echo ""
        echo "These will be downloaded to ~/.config/spark/zsh-plugins and symlinked"
        echo "to your oh-my-zsh custom plugins directory. You can then add them to"
        echo "your plugins array in .zshrc if you want to use them."
        echo ""
        read -p "Do you want to install Sparkdock's plugin collection? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "⏭️  Skipping plugin installation"
            echo "   You can run this command again later to install them"
            exit 0
        fi
        echo ""
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

    if [[ "${OMZ_ALREADY_CONFIGURED}" == "true" ]]; then
        echo "To use these plugins, add them to your plugins array in ~/.zshrc:"
        echo "  plugins=(... zsh-completions zsh-autosuggestions zsh-syntax-highlighting)"
        echo ""
        echo "Note: When you source sparkdock.zshrc, it will respect your plugin configuration."
    else
        echo "Plugins are automatically enabled when you source sparkdock.zshrc"
        echo "Configuration is in: /opt/sparkdock/config/shell/omz-init.zsh"
    fi

# Update oh-my-zsh plugins.
[group('shell')]
shell-omz-update-plugins:
    #!/usr/bin/env bash
    set -euo pipefail

    PLUGINS_DIR="${HOME}/.config/spark/zsh-plugins"

    if [[ ! -d "${PLUGINS_DIR}" ]]; then
        echo "❌ Plugins directory not found: ${PLUGINS_DIR}"
        echo "💡 Run 'sjust shell-omz-setup' first to install plugins"
        exit 1
    fi

    echo "=========================================="
    echo "Updating oh-my-zsh plugins"
    echo "=========================================="
    echo ""

    # Update zsh-completions
    if [[ -d "${PLUGINS_DIR}/zsh-completions" ]]; then
        echo "📦 Updating zsh-completions..."
        git -C "${PLUGINS_DIR}/zsh-completions" pull --quiet
        echo "✅ zsh-completions updated"
    else
        echo "⚠️  zsh-completions not found, installing..."
        git clone --quiet https://github.com/zsh-users/zsh-completions "${PLUGINS_DIR}/zsh-completions"
        ln -sf "${PLUGINS_DIR}/zsh-completions" "$HOME/.oh-my-zsh/custom/plugins/zsh-completions"
        echo "✅ zsh-completions installed"
    fi

    # Update zsh-autosuggestions
    if [[ -d "${PLUGINS_DIR}/zsh-autosuggestions" ]]; then
        echo "📦 Updating zsh-autosuggestions..."
        git -C "${PLUGINS_DIR}/zsh-autosuggestions" pull --quiet
        echo "✅ zsh-autosuggestions updated"
    else
        echo "⚠️  zsh-autosuggestions not found, installing..."
        git clone --quiet https://github.com/zsh-users/zsh-autosuggestions "${PLUGINS_DIR}/zsh-autosuggestions"
        ln -sf "${PLUGINS_DIR}/zsh-autosuggestions" "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
        echo "✅ zsh-autosuggestions installed"
    fi

    # Update zsh-syntax-highlighting
    if [[ -d "${PLUGINS_DIR}/zsh-syntax-highlighting" ]]; then
        echo "📦 Updating zsh-syntax-highlighting..."
        git -C "${PLUGINS_DIR}/zsh-syntax-highlighting" pull --quiet
        echo "✅ zsh-syntax-highlighting updated"
    else
        echo "⚠️  zsh-syntax-highlighting not found, installing..."
        git clone --quiet https://github.com/zsh-users/zsh-syntax-highlighting "${PLUGINS_DIR}/zsh-syntax-highlighting"
        ln -sf "${PLUGINS_DIR}/zsh-syntax-highlighting" "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
        echo "✅ zsh-syntax-highlighting installed"
    fi

    echo ""
    echo "✅ All plugins updated!"
    echo "💡 Restart your shell or run 'source ~/.zshrc' to apply updates"
