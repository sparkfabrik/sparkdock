# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/09-claude-fix-settings.just lives at <sparkdock_root>/sjust/recipes/shared/
_claude_fix_settings_sh := clean(source_directory() / "../../..") / "sjust/scripts/claude-fix-settings.sh"

# Repair sparkdock-managed Claude Code hooks in ~/.claude/settings.json: rewrite
# the caveman hook node path to a stable Homebrew symlink (survives node version
# bumps) and remove the claude-usage session hooks. Idempotent; backs up before
# writing.
[group('claude')]
claude-fix-settings:
    @bash "{{_claude_fix_settings_sh}}" fix

# Show what claude-fix-settings would change, without writing.
[group('claude')]
claude-fix-settings-info:
    @bash "{{_claude_fix_settings_sh}}" info
