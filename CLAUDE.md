# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Sparkdock is an automated macOS development environment provisioner built with Ansible. It provides containerized workflows and modern tooling with an integrated HTTP proxy system for local development.

## Common Commands

### Running Ansible Provisioning
```bash
# Run full system provisioning
sparkdock

# Run specific Ansible tags
make run-ansible-macos TAGS="docker,http-proxy"
just run-ansible-macos "http-proxy"
```

### SparkJust Task Runner (sjust)
```bash
# Show available commands and list all tasks
sjust
sjust --list

# Install just the sjust tool (for manual migrations)
make install-sjust
```

### HTTP Proxy Management
```bash
spark-http-proxy start           # Start proxy services
spark-http-proxy stop            # Stop proxy services  
spark-http-proxy status          # Check service status
```

### Development Workflow
```bash
# Run specific Ansible tasks by tags
sjust install-tags "docker,keyboard"
```

## Architecture

### Directory Structure
- `/opt/sparkdock/` - Main installation directory
- `ansible/` - Ansible playbooks and configuration
- `sjust/` - SparkJust task runner with recipes
- `config/` - System configuration files and package lists
- `bin/` - Executable scripts
- `http-proxy/` - HTTP proxy system (cloned separately)

### Core Components

**Ansible Provisioning System:**
- Main playbook: `ansible/macos.yml` → `ansible/macos/macos/base.yml`
- Package definitions: `config/packages/all-packages.yml`
- Supports tagging for selective installation

**SparkJust Task Runner:**
- Wrapper around Just task runner: `sjust/sjust.sh`
- Recipe files in `sjust/recipes/` with modular task definitions
- User customizations via `~/.config/sjust/100-custom.just`

**HTTP Proxy Integration:**
- Clones SparkFabrik HTTP proxy to `/opt/sparkdock/http-proxy`
- Configures DNS resolver for `.loc` domains
- Manages SSL certificates with mkcert

### Package Management
- Homebrew packages and casks defined in YAML
- Automatic tap management and cleanup
- Version-specific packages (Node 20, PHP 8.2)
- Removed packages tracking for clean uninstalls

## Shell Script Standards

Per `.github/copilot-instructions.md`, all shell scripts must:
- Use `#!/usr/bin/env bash` shebang
- Include `set -euo pipefail` for error handling
- Use `${variable}` syntax with braces
- Use `local` for function variables
- Pass shellcheck validation

## Testing

- Ansible playbooks should be idempotent
- Test HTTP proxy with `test-http-proxy` command
- Verify package installations with assertion tasks
- Check system state with `sjust device-info`

## Sparkdock Manager (Menu Bar App)

A Swift-based menu bar application provides visual update notifications:

### Building and Testing
```bash
cd src/menubar-app
make build                    # Build the app
make test                     # Test build
make install                  # Install manually (requires sudo)
make uninstall               # Remove installation
```

### Integration
- Built automatically during Ansible provisioning with `menubar` tag
- Replaces old launchd-based update notifications
- Auto-starts at login via launch agent

## Troubleshooting

- Lock file issues: Remove `/tmp/sparkdock.lock`
- DNS issues: Run `sjust clear-dns-cache`
- Update failures trigger automatic rollback
- Menu bar app issues: Check `~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist`
- See `TROUBLESHOOTING.md` for detailed guidance