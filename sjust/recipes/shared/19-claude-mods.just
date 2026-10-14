# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/19-claude-mods.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_mods_flag_py := clean(source_directory() / "../../..") / "sjust/scripts/claude-mods-flag.py"

# Clear a cached off value that keeps Claude Code mods from loading (anthropics/claude-code#91870).
[group('claude')]
claude-mods-flag-clear:
    @python3 "{{_claude_mods_flag_py}}" clear

# Show the cached Claude Code mods rollout flag.
[group('claude')]
claude-mods-flag-info:
    @python3 "{{_claude_mods_flag_py}}" info
