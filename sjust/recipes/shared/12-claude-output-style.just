# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/12-claude-output-style.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_output_style_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-output-style.py"

# Set the default Claude Code output style (Concise) in ~/.claude/settings.json. Only writes when no style is set, so your own choice is never overwritten.
[group('claude')]
claude-output-style-set style="":
    @python3 "{{_claude_output_style_py}}" set {{style}}

# Remove the output style key, restoring Claude Code's Default style.
[group('claude')]
claude-output-style-reset:
    @python3 "{{_claude_output_style_py}}" reset

# Show the configured output style and where it comes from.
[group('claude')]
claude-output-style-info:
    @python3 "{{_claude_output_style_py}}" info
