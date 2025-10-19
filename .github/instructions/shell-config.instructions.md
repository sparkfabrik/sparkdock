---
applyTo: "**/*.zsh,**/sparkdock.zshrc"
---

# Sparkdock Shell Configuration Instructions

When working with zsh configuration files in this repository, please follow the Sparkdock shell configuration philosophy and conventions.

## Core Philosophy

Sparkdock's shell configuration is designed to be **seamless and non-intrusive**:

- Respects existing user configurations (oh-my-zsh, prompts, plugins)
- Uses conditional loading to avoid conflicts
- Detects what's already configured before initializing
- Provides opt-out mechanisms via environment variables

## Key Reference

For detailed guidance on shell configuration, architecture, and seamless integration patterns, refer to:

#file:../../config/shell/README.md

This file contains:

- Seamless integration philosophy and detection logic
- Conditional loading patterns for oh-my-zsh and starship
- Environment variables for user control
- Architecture and load order
- Troubleshooting guidance

## Shell Script Standards

All zsh scripts and configuration files must follow these standards:

### Bash Scripts (\*.sh)

- Use `#!/usr/bin/env bash` shebang line (hashbang for bash scripts)
- Include `set -euo pipefail` for strict error handling
- Use `${variable}` syntax with braces (never `$variable`)
- Use `local` for function variables to avoid namespace pollution
- Pass `shellcheck` validation before committing

### Zsh Configuration (\*.zsh)

- Guard against double-loading using environment variables
- Use conditional checks before loading plugins or frameworks
- Respect user's existing configuration
- Provide clear opt-out mechanisms
- Document all environment variables used

## Detection Patterns

When initializing tools or frameworks:

1. **Check if already loaded**: Look for environment variables or state
2. **Detect user preferences**: Check for existing configurations or custom setups
3. **Opt-in for advanced features**: Use `SPARKDOCK_ENABLE_*` environment variables
4. **Be transparent**: Add comments explaining conditional logic

### Example Pattern

```zsh
# Only load if not already initialized by user
if [[ -d "$HOME/.oh-my-zsh" ]] && [[ -z "$ZSH" ]]; then
  source "${SPARKDOCK_SHELL_DIR}/omz-init.zsh"
fi

# Opt-in for advanced features via environment variable
if [[ -n "$SPARKDOCK_ENABLE_STARSHIP" ]] && command -v starship &> /dev/null; then
  eval "$(starship init zsh)"
fi
```

## Naming Conventions

- Use descriptive environment variables: `SPARKDOCK_SHELL_LOADED`, `SPARKDOCK_ENABLE_STARSHIP`, `SPARKDOCK_ENABLE_FZF`, `SPARKDOCK_ENABLE_ATUIN`
- Prefix all Sparkdock-specific variables with `SPARKDOCK_`
- Use uppercase for environment variables
- Use lowercase with underscores for local variables in scripts

## Conditional Loading Priority

1. **User's explicit configuration** (already in .zshrc)
2. **Opt-in features** (SPARKDOCK*ENABLE*\* for advanced tools like starship, fzf, atuin)
3. **Auto-detection** (check for existing tools/themes)
4. **Sparkdock defaults** (only if nothing else detected)

## Testing Considerations

When modifying shell configurations, consider these scenarios:

- Fresh user with no existing .zshrc
- User with existing oh-my-zsh configuration
- User with custom prompt (powerlevel10k, pure, etc.)
- User who wants to disable specific features
- Double-sourcing protection

## Just Recipe Parameters for Shell Commands

When creating or modifying shell recipes in `sjust/recipes/03-shell.just`, follow these Just-specific patterns:

### Parameter Syntax

Just recipes accept **positional arguments only**, not `parameter=value` syntax:

```bash
# ✅ Correct
sjust shell-enable force

# ❌ Wrong - This passes "force=true" as the literal string value
sjust shell-enable force=true
```

### Exporting Parameters in Shebang Recipes

For bash shebang recipes (`#!/usr/bin/env bash`), prefix parameters with `$` to export them as environment variables:

```just
shell-enable $force="false":
    #!/usr/bin/env bash
    set -euo pipefail

    # $force is available as environment variable (no interpolation needed)
    if [[ "${force}" == "force" ]]; then
        echo "Force enabled"
    fi
```

**Key Points:**

- `$param` prefix exports the parameter as an environment variable
- No need for `{{param}}` interpolation in shebang recipes
- Parameters are passed positionally: `sjust recipe-name value1 value2`
- Default values in quotes: `$param="default"`

### Alternative: Interpolation Without Export

Without the `$` prefix, use `{{param}}` interpolation (but this only works in recipe command lines, not in bash conditionals within shebang recipes):

```just
simple-recipe param="default":
    echo "Value is {{param}}"  # Works in recipe lines
```

For shebang recipes with bash conditionals, **always use `$` prefix** to export as environment variables.

## Related Files

- `config/shell/sparkdock.zshrc` - Main entry point with guard
- `config/shell/init.zsh` - Tool initialization with conditional loading
- `config/shell/omz-init.zsh` - Oh-my-zsh configuration with plugin checks
- `config/shell/aliases.zsh` - Command aliases
- `sjust/recipes/03-shell.just` - Shell setup commands
