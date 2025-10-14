# Sparkdock Development Guide

Sparkdock is an automated macOS development environment provisioner built with Ansible, featuring containerized workflows, an HTTP proxy system, and a Swift menu bar app for update notifications.

## Core Architecture

**Three-Layer System:**

- **Ansible Provisioning**: Core system configuration (`ansible/macos.yml` → `ansible/macos/macos/base.yml`)
- **SparkJust Task Runner**: Development workflow automation (`sjust/` with modular recipes)
- **Menu Bar Manager**: Swift app for update notifications (`src/menubar-app/`)

**Key Integration Points:**

- Package definitions in `config/packages/all-packages.yml` drive Ansible provisioning
- SparkJust wrapper (`sjust/sjust.sh`) delegates to Just task runner with custom recipes
- HTTP proxy system cloned separately to `/opt/sparkdock/http-proxy` during installation

## Essential Workflows

**Installation Chain**: `bin/install.macos` → `bin/sparkdock.macos` → Ansible provisioning → HTTP proxy setup → Menu bar app
**Update Workflow**: Auto-update via git fetch/reset → rollback capability → background notifications
**Task Execution**: `sjust` → Just recipes in `sjust/recipes/` → Ansible tags or shell commands

## Project Conventions

**Package Management Pattern:**

```yaml
# config/packages/all-packages.yml structure
taps: [koekeishiya/formulae]
cask_packages: [docker-desktop, visual-studio-code]
homebrew_packages: [awscli, kubernetes-cli]
removed_cask_packages: [] # Track for clean uninstalls
```

**Ansible Tag Strategy:**

- Tags like `docker`, `http-proxy`, `menubar` enable selective provisioning
- Use `sjust install-tags "docker,keyboard"` for targeted installs
- All tasks must be idempotent with proper assertion checks

**SparkJust Recipe Organization:**

- `00-default.just`: Core system tasks (cleanup, updates, device info)
- `01-lima.just`: Lima container environment tasks
- `~/.config/sjust/100-custom.just`: User customizations (optional import)

## Swift Menu Bar App Patterns

**Modern Concurrency**: Uses structured concurrency with `withTaskCancellationHandler` for process timeout
**Event-Driven Updates**: Triggers on network changes and system wake (no polling)
**Resource Fallbacks**: Custom logo → SF Symbols, JSON config → minimal menu
**Integration**: Installed via Ansible `menubar` tag, auto-starts via LaunchAgent

Example structured concurrency pattern:

```swift
let result = await withTaskCancellationHandler(
    operation: { try await withTimeout(seconds: 30) { /* async work */ } },
    onCancel: { process.terminate() }
)
```

## Shell Script Standards

All shell scripts must follow these patterns:

- Use `#!/usr/bin/env bash` shebang line
- Include `set -euo pipefail` for strict error handling
- Use `${variable}` syntax with braces (never `$variable`)
- Use `local` for function variables to avoid namespace pollution
- Pass `shellcheck` validation before committing
- When implementing commands, when things exist, do not use `else` branches unless necessary, for example:

Prefer to do this:

```bash
#!/usr/bin/env bash
if ! tart list | grep -q "sparkdock-test"; then
    tart clone {{IMAGE}} sparkdock-test
    echo "✅ VM 'sparkdock-test' created successfully"
fi
```

Instead of this:

Do not do this:

```bash
#!/usr/bin/env bash
 if ! tart list | grep -q "sparkdock-test"; then
        tart clone {{IMAGE}} sparkdock-test
        echo "✅ VM 'sparkdock-test' created successfully"
    else
        echo "VM 'sparkdock-test' already exists"
    fi
```

Instead of this:

```bash
    if ! command -v cirrus >/dev/null 2>&1; then
        echo "Installing Cirrus CLI via Homebrew..."
        brew install cirruslabs/cli/cirrus
    else
        echo "Cirrus CLI is already installed"
    fi
```

Do this:

```bash
    if ! command -v cirrus >/dev/null 2>&1; then
        echo "Installing Cirrus CLI via Homebrew..."
        brew install cirruslabs/cli/cirrus
    fi
```

**Critical: No Trailing Whitespace**

- Git warns about trailing whitespace in commits
- Clean up before staging changes across ALL file types
- Use editor whitespace visualization to identify issues

## HTTP Proxy Integration

**Architecture**: Separate repository cloned to `/opt/sparkdock/http-proxy`
**DNS Resolution**: `.loc` domains automatically resolved via DNS resolver configuration
**SSL Certificates**: mkcert integration for local HTTPS development
**Management**: `spark-http-proxy start/stop/status` commands

## Build and Test Patterns

**Ansible**: `make run-ansible-playbook TAGS="docker,http-proxy"` for targeted provisioning
**Swift App**: `cd src/menubar-app && make build/test/install` for menu bar development
**System Updates**: `sjust upgrade-system` for Homebrew maintenance
**Debugging**: Use `sjust device-info` for system diagnostics

## Git Workflow Specifics

**Default Branch**: `master` (project-specific, not `main`)
**Update Safety**: Automatic stashing of local changes during updates
**Lock File**: `/tmp/sparkdock.lock` prevents concurrent updates
**Rollback**: Built-in rollback on failed updates using stored commit hashes

## Shell Aliases Maintenance

**When updating shell aliases in `config/shell/aliases.zsh`:**

- Update the `shell-aliases-help` command in `sjust/recipes/00-default.just` to reflect changes
- Keep the alias list organized by category (File & Directory, Search & Find, Docker, Git, Kubernetes, System)
- Include descriptions and practical usage tips
- Test that the help output remains clear and accurate

**Categories to maintain:**
- 📁 File & Directory Navigation
- 🔍 Search & Find
- 📄 File Viewing
- 🐳 Docker
- 🔧 Git
- ☸️  Kubernetes
- 🔧 System

## Changelog

- Maintain a CHANGELOG.md file
- Document all changes, including bug fixes and new features
- Keep each changelog entry to just one line for clarity and consistency
