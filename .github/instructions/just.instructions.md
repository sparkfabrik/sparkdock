---
applyTo: "**/*.just"
---

# Just Recipe Development Guidelines

When working with Just recipes in this project, always consult the Just documentation via the Context7 MCP server.

## MCP Context7 Integration

**IMPORTANT**: Before writing or modifying any Just recipe, use the `#mcp_context7` tool with library ID `/casey/just` to get up-to-date documentation and examples.

Example queries:

- For recipe syntax: Query for "just recipe syntax parameters dependencies"
- For variables: Query for "just variables assignment export environment"
- For modules: Query for "just modules import submodules"
- For attributes: Query for "just recipe attributes group private"

## Recipe Organization Conventions

Follow the established patterns in the Sparkdock project:

### Keep Recipes Clean

- Just recipes should focus on **task orchestration**, not implementation
- Extract complex logic into reusable shell functions in `sjust/libs/libshell.sh`
- Use `source "{{source_directory()}}/../libs/libshell.sh"` to load shared utilities
- Recipes should primarily **call library functions**, not implement full logic inline

### Library Functions Pattern

```just
# Good: Recipe calls library function
[group('shell')]
shell-ghostty-setup:
    #!/usr/bin/env bash
    source "{{source_directory()}}/../libs/libshell.sh"
    sparkdock_setup_ghostty_config

# Bad: Recipe contains full implementation
[group('shell')]
shell-ghostty-setup:
    #!/usr/bin/env bash
    USER_CONFIG="${HOME}/.config/ghostty/config"
    # ... 60 lines of logic here ...
```

### Shell Script Standards in Recipes

All shell scripts in recipes must follow these patterns:

- Use `#!/usr/bin/env bash` shebang line
- Include `set -euo pipefail` for strict error handling
- Use `${variable}` syntax with braces (never `$variable`)
- Use `local` for function variables to avoid namespace pollution
- Pass `shellcheck` validation before committing

### Recipe File Organization

- `00-default.just`: Core system tasks (cleanup, updates, device info)
- `01-lima.just`: Lima container environment tasks
- `02-docker-desktop.just`: Docker Desktop specific tasks
- `03-shell.just`: Shell configuration and setup tasks
- `~/.config/sjust/100-custom.just`: User customizations (optional import)

## Just Best Practices

### Use Attributes

```just
[group('shell')]
[private]
_helper-function:
    echo "internal helper"
```

### Recipe Dependencies

```just
build: dependencies
    make build

test: build
    make test
```

### Parameters with Defaults

```just
deploy environment="staging":
    ./deploy.sh {{environment}}
```

### Variadic Parameters

```just
# One or more
backup +FILES:
    scp {{FILES}} server:/backup/

# Zero or more
commit MESSAGE *FLAGS:
    git commit {{FLAGS}} -m "{{MESSAGE}}"
```

## Documentation

Always add documentation comments to recipes:

```just
# Build the project artifacts
build:
    make build
```

## Reference Documentation

For any Just-related questions, **always use the Context7 MCP server** with library ID `/casey/just` to get accurate, up-to-date information from the official Just documentation.
