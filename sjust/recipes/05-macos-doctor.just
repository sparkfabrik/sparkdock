# vim: set ft=make :
#
# Pluggable macOS health checks. Adding a check means dropping a file into
# sjust/scripts/macos-doctor/checks/; there is no catalog to edit here.
#
# Note this file consumes sparkdock_path from 00-default.just, so like
# 03-macos-defaults.just it cannot be parsed standalone by CI.

# Report on macOS health. Read-only: this never changes anything.
#   macos-doctor                    # every check
#   macos-doctor launchd-orphans    # a single check
#   macos-doctor count              # only the status line, cheap checks (used by the TUI)
[group('macos')]
[doc('Report macOS health issues. Pass a check id for one check, or "count" for a machine-readable summary.')]
macos-doctor $check="":
    @{{ sparkdock_path }}/sjust/scripts/macos-doctor/run.sh "${check}"

# Document every registered check, its flags and how to read its findings.
[group('macos')]
[doc('Explain every macos-doctor check. Modes: pretty (default), raw.')]
macos-doctor-info $mode="pretty":
    @{{ sparkdock_path }}/sjust/scripts/macos-doctor/info.sh "${mode}"

# Apply one check's fix, after showing what it found and asking for confirmation.
# There is deliberately no fix-all.
#   macos-doctor-fix launchd-orphans          # user-owned paths only
#   macos-doctor-fix launchd-orphans system   # also root-owned paths under /Library
[group('macos')]
[doc('Fix one macos-doctor finding set (confirmation required). Pass "system" to include root-owned paths.')]
macos-doctor-fix $check="" $scope="":
    @{{ sparkdock_path }}/sjust/scripts/macos-doctor/fix.sh "${check}" "${scope}"

# List or restore quarantine snapshots. Only fixes from checks that declare
# themselves reversible produce a snapshot.
#   macos-doctor-undo               # list available snapshots (default)
#   macos-doctor-undo restore       # restore the newest snapshot
#   macos-doctor-undo <timestamp>   # restore a specific snapshot
[group('macos')]
[doc('List or restore quarantined paths from a previous macos-doctor fix.')]
macos-doctor-undo $action="":
    @{{ sparkdock_path }}/sjust/scripts/macos-doctor/undo.sh "${action}"
