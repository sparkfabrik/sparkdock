# Shell scripts

When asked to write or suggest shell scripts, use all best practices for shell scripting, including:

- Use `#!/usr/bin/env bash` as the shebang line.
- Use `set -euo pipefail` to ensure the script exits on errors, undefined variables, or failed commands in a pipeline.
- Use curly braces for variable expansion, e.g., `${variable}`. Completely avoid using `$variable` without braces.
- Use `local` for variables inside functions to avoid polluting the global namespace.
