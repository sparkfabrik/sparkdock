# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/17-harness-tools-upgrade.just lives at <sparkdock_root>/sjust/recipes/shared/
_harness_tools_upgrade_sh := clean(source_directory() / "../../..") / "sjust/scripts/harness-tools-upgrade.sh"

# Upgrade Claude Code and Codex to the latest version through their install channel.
[group('ai-coding-harness')]
sf-harness-tools-upgrade:
    @bash "{{_harness_tools_upgrade_sh}}"
