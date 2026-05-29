# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/07-claude-statusline.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_statusline_sh := clean(source_directory() / "../../..") / "sjust/scripts/claude-statusline.sh"

# Enable the SparkFabrik managed statusline in ~/.claude/settings.json (opt-in, idempotent, overridable).
[group('claude')]
claude-statusline-enable:
    @bash "{{_claude_statusline_sh}}" enable

# Disable the SparkFabrik managed statusline (removes the statusLine key).
[group('claude')]
claude-statusline-disable:
    @bash "{{_claude_statusline_sh}}" disable

# Show the current statusline configuration and the managed script path.
[group('claude')]
claude-statusline-info:
    @bash "{{_claude_statusline_sh}}" info

# Render a live preview of the statusline bar (runs the real renderer).
[group('claude')]
claude-statusline-preview:
    @bash "{{_claude_statusline_sh}}" preview
