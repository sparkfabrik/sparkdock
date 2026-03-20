# vim: set ft=make :

# Configure OpenSpec with custom profile and all workflows.
# Pass 'force' to overwrite existing config without prompting.
[group('ai-coding-agents')]
sf-openspec-configure $force="":
    {{sparkdock_path}}/sjust/scripts/openspec/configure.sh "${force}"
