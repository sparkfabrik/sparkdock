# vim: set ft=make :

# Why: the Herdr app (herdr-core) restores tabs after a reboot but not the agents
# in them; the legacy herdr TUI did. Upstream waits for OSC 7501 to carry a resume
# reference: https://github.com/herdrdev/herdr-core/issues/13,
# https://github.com/herdrdev/herdr-core/issues/15,
# https://github.com/herdrdev/herdr-app/issues/406
# Opt-in stopgap: drop it once herdr-core resumes agents itself.

_herdr_agent_resume_py := clean(source_directory() / "../../..") / "sjust/scripts/herdr-agent-resume/herdr-agent-resume.py"

# Resume Claude Code and Codex sessions in Herdr terminals after a reboot (opt-in).
[group('herdr')]
herdr-agent-resume-enable:
    @python3 "{{_herdr_agent_resume_py}}" enable

# Remove the hooks, the ~/.zshrc line, the terminal labels and all local state.
[group('herdr')]
herdr-agent-resume-disable:
    @python3 "{{_herdr_agent_resume_py}}" disable

# Show registration, recorded sessions and warnings.
[group('herdr')]
herdr-agent-resume-info:
    @python3 "{{_herdr_agent_resume_py}}" info
