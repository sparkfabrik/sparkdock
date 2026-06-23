# vim: set ft=make :

# Configure OpenSpec with custom profile and all workflows.
# Pass 'force' to overwrite existing config without prompting.
[group('ai-coding-harness')]
sf-openspec-configure $force="":
    {{sparkdock_path}}/sjust/scripts/openspec/configure.sh "${force}"

# Install or update OpenSpec skills and prompts globally in ~/.claude.
# Pass a comma-separated tool list for first-time init (default: claude).
[group('ai-coding-harness')]
sf-openspec-install-global $tools="claude":
    {{sparkdock_path}}/sjust/scripts/openspec/install-global-skills.sh "${tools}"
