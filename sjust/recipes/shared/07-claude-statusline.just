# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/07-claude-statusline.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_statusline_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-statusline.py"

# Enable the SparkFabrik managed statusline in ~/.claude/settings.json (opt-in, idempotent, overridable).
[group('claude')]
claude-statusline-enable:
    @python3 "{{_claude_statusline_py}}" enable

# Disable the SparkFabrik managed statusline (removes the statusLine key).
[group('claude')]
claude-statusline-disable:
    @python3 "{{_claude_statusline_py}}" disable

# Show the current statusline configuration and the managed script path.
[group('claude')]
claude-statusline-info:
    @python3 "{{_claude_statusline_py}}" info

# Render a live preview of the statusline bar (runs the real renderer). Pass "full" to show every segment it can draw.
[group('claude')]
claude-statusline-preview variant="":
    @python3 "{{_claude_statusline_py}}" preview {{ if variant == "" { "" } else { quote(variant) } }}
