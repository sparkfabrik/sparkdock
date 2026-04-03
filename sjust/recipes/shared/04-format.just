# vim: set ft=make :

format_prettier_version := "3"

# Format markdown files using prettier (runs on host, not in Docker).
[no-cd]
[group('format')]
format-md *path:
    @npx --yes prettier@{{format_prettier_version}} --write {{ if path == "" { '"**/*.md" "!pkg/**" "!vendor/**"' } else { path } }}

# Check markdown formatting without writing changes (runs on host, not in Docker).
[no-cd]
[group('format')]
format-md-check *path:
    @npx --yes prettier@{{format_prettier_version}} --check {{ if path == "" { '"**/*.md" "!pkg/**" "!vendor/**"' } else { path } }}
