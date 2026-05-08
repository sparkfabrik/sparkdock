# AGENTS.md

This file provides guidance to AI coding agents when working with code in this repository.

## Platform Support

**Apple Silicon Only**: Sparkdock supports **only Apple Silicon Macs**. Intel-based Macs are **not supported**.

## Overview

Sparkdock is an automated macOS development environment provisioner built with Ansible. It provides containerized workflows and modern tooling with an integrated HTTP proxy system for local development.

## Common Commands

### Running Ansible Provisioning

```bash
# Run full system provisioning
sparkdock

# Run specific Ansible tags
make run-ansible-playbook TAGS="docker,http-proxy"
just run-ansible-playbook "http-proxy"
```

### SparkJust Task Runner (sjust)

```bash
# Show available commands and list all tasks
sjust
sjust --list

# Install just the sjust tool (for manual migrations)
make install-sjust
```

**Important: Just Recipe Parameters**

Just recipes use **positional arguments**, not `parameter=value` syntax:

```bash
# ✅ Correct: positional arguments
sjust shell-enable force

# ❌ Wrong: parameter=value syntax doesn't work
sjust shell-enable force=true
```

**Exporting Parameters as Environment Variables:**

Prefix parameters with `$` to export them as environment variables in shebang recipes:

```just
my-recipe $param="default":
    #!/usr/bin/env bash
    # $param is now available as environment variable
    echo "Value: ${param}"
```

Without the `$` prefix, parameters require `{{param}}` interpolation in recipe lines.

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
- Keep recipe files clean and focused on task orchestration
- Extract complex logic into reusable functions in `sjust/libs/libshell.sh`
- Use `source "{{source_directory()}}/../libs/libshell.sh"` to load shared utilities

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

**Bash version.** Sparkdock scripts target **bash 5.x** (Homebrew's `bash` formula). macOS still ships `/bin/bash` 3.2 because newer bash is GPLv3, but Sparkdock provisioning installs Homebrew's bash and ensures `/opt/homebrew/bin` precedes `/usr/bin` on `PATH`, so `#!/usr/bin/env bash` resolves to the modern interpreter. You can use `declare -A`, `mapfile` / `readarray`, `${arr[-1]}`, `[[ -v var ]]`, and other bash 4+ idioms freely — no need for 3.2-compat workarounds. (`bash` is listed in `config/packages/all-packages.yml`.)

All shell scripts must:

- Use `#!/usr/bin/env bash` shebang
- Include `set -euo pipefail` for error handling
- Use `${variable}` syntax with braces (never bare `$variable`)
- Use `local` for function variables to avoid namespace pollution
- Pass shellcheck validation (see below)
- Prefer early-return / guard-clause style over `else` branches when checking pre-conditions:

```bash
# Good: guard clause, no else
if ! command -v cirrus >/dev/null 2>&1; then
    brew install cirruslabs/cli/cirrus
fi

# Avoid: unnecessary else branch
if ! command -v cirrus >/dev/null 2>&1; then
    brew install cirruslabs/cli/cirrus
else
    echo "Cirrus CLI is already installed"
fi
```

**Shellcheck Validation**

Before committing changes to shell scripts, run shellcheck using the official Docker image:

```bash
docker run --rm -v "$(pwd):/src" koalaman/shellcheck:stable /src/bin/sparkdock-agents-status
```

## Python Standards

- Format all Python files with **ruff** before committing
- Run via Docker: `docker run --rm -v "$(pwd)/src:/src" ghcr.io/astral-sh/ruff:latest format /src`
- Lint check: `docker run --rm -v "$(pwd)/src:/src" ghcr.io/astral-sh/ruff:latest check /src`

## Markdown Formatting

After creating or editing any Markdown file (`.md`), **always** run the
formatter before committing. Never format Markdown by hand -- delegate to
the tool.

## Code Quality Standards

**CRITICAL: Trailing Whitespace**

- **NEVER** commit trailing whitespace (spaces/tabs at end of lines)
- Git will warn about trailing whitespace during commits
- Always clean up trailing whitespace before staging changes
- Use your editor's "show whitespace" feature to identify issues
- This applies to ALL files: Swift, shell scripts, YAML, Markdown, etc.

**JavaScript Style**

- Always use braces for `if`, `for`, `while`, and similar control statements, even for single-line bodies

**CHANGELOG.md Conventions**

**MANDATORY**: Every commit that changes user-visible behavior, adds features, fixes bugs, removes functionality, or refactors existing behavior **MUST** include a corresponding `CHANGELOG.md` entry under `## [Unreleased]`. This is not optional — treat a missing changelog entry as a build failure. The only exceptions are pure documentation or test-only changes with zero user-facing impact.

This project uses a daily Slack digest that parses `CHANGELOG.md` to detect and announce new entries. Malformed sections (duplicate headers, wrong categories) **break the digest silently**. Follow these rules strictly:

- Follow [Keep a Changelog](https://keepachangelog.com/) format
- **One header per section**: Each `### Added`, `### Changed`, `### Fixed`, `### Removed`, `### Deprecated`, `### Security` must appear **exactly once** under `## [Unreleased]`. Never create a duplicate section header — always prepend entries to the existing section
- **Standard section order**: Added, Changed, Deprecated, Removed, Fixed, Security. Do not intersperse or reorder sections
- **Correct categorization**: Entries must match their section. New features/tools/commands go under `### Added`, not `### Changed`. Use `### Changed` only for modifications to existing behavior. Use `### Fixed` for bug fixes. If an entry starts with "Added", it belongs under `### Added`
- **New entries go at the top** of their section — newest first, preserving temporal order
- **Never reorder existing entries** — only prepend above them
- **One line per entry**: Keep entries concise, no excessive detail. Do not use `####` sub-headings or multi-level nesting inside `## [Unreleased]`
- **No trailing whitespace** on any line

## Testing

- Ansible playbooks should be idempotent
- Test HTTP proxy with `test-http-proxy` command
- Verify package installations with assertion tasks
- Check system state with `sjust device-info`

## Sparkdock Manager (Menu Bar App)

A Swift-based menu bar application provides battery-efficient visual update notifications using modern async/await patterns:

### Key Features

- **Event-Driven Updates**: Only checks on system wake and network connectivity changes (no periodic polling)
- **Modern Swift Concurrency**: Uses structured concurrency with proper cancellation and timeout handling
- **Battery Efficient**: NWPathMonitor for lightweight network monitoring
- **Resource Debugging**: Enhanced logging for missing logo/resource troubleshooting

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
- Auto-starts at login via launch agent (local development only)
- CI environments skip LaunchAgent installation for better automation

## AI Coding Agents System

Sparkdock syncs AI coding resources from the upstream `sf-awesome-copilot` repository. This covers two resource types managed by a unified sync system:

- **Skills**: Tool-specific instruction files (e.g., `glab`) installed to `~/.agents/skills/<name>/SKILL.md`
- **Agent profiles**: Per-tool agent configurations (e.g., "The Architect") installed to tool-specific directories (`~/.copilot/agents/`, `~/.config/opencode/agents/`)

### Key Scripts

- `bin/sparkdock-agents-sync` — Unified sync script with tool registry, skill sync, agent sync, v2 manifest
- `bin/sparkdock-agents-status` — Status display for both skills and agent profiles
- `bin/sparkdock-check-updates` — Accepts both `skills` and `agents` subcommands

### Tool Registry

The sync script uses associative arrays to map each coding tool to its install directory and filename pattern. Adding support for a new tool requires only 2 lines (one in each array). Current tools: `copilot`, `opencode`.

### Manifest

Located at `~/.cache/sparkdock/sf-skills-manifest.json`. V2 format with `skills` and `agents` top-level keys. V1 manifests upgrade organically (no migration code). Agent entries use composite keys like `the-architect/copilot`.

### Catalog Metadata

The upstream repo provides `config/catalog.json` with short human-friendly descriptions for each system skill and agent. The status script reads this file from the local cache (`~/.cache/sparkdock/agent-skills/config/catalog.json`) to display a DESCRIPTION column in the table. No sync changes are needed — the file is part of the cloned cache.

### sjust Recipes (`sjust/recipes/05-ai-coding-agents.just`)

- `sf-agents-refresh [force]` — Sync all resources (skills + agents)
- `sf-agents-status` — Show status of all resources

### Ansible Tags

- `ai-coding-agents` (new) and `skills` (kept for backward compat)

### OpenSpec Change

Full design artifacts at `openspec/changes/unified-agents-sync/` (proposal, design, specs, tasks).

## Git Workflow

- **Default branch**: `master` (not `main`)
- Automatic stashing of local changes during updates
- Lock file at `/tmp/sparkdock.lock` prevents concurrent updates
- Built-in rollback on failed updates using stored commit hashes

## Troubleshooting

- Lock file issues: Remove `/tmp/sparkdock.lock`
- DNS issues: Run `sjust clear-dns-cache`
- Update failures trigger automatic rollback
- Menu bar app issues: Check `~/Library/LaunchAgents/com.sparkfabrik.sparkdock.menubar.plist`
- See `TROUBLESHOOTING.md` for detailed guidance
