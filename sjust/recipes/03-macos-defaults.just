# vim: set ft=make :
#
# macOS system defaults — declarative, idempotent application of curated
# developer defaults. Implementation lives in sjust/scripts/macos-defaults/.
# See config/macos/defaults.yml for the data; recipes here are thin wrappers.
# `sparkdock_path` is shared across recipes and defined in 00-default.just.

# Show the curated profile with descriptions, grouped by category. Run this
# before `macos-defaults` to understand exactly what will be written.
[group('macos')]
[doc('Show the curated macOS defaults profile (what will be applied) with descriptions.')]
macos-defaults-info $mode="pretty":
    @{{ sparkdock_path }}/sjust/scripts/macos-defaults/info.sh "${mode}"

# Apply or preview the curated macOS defaults.
#   macos-defaults                       # apply (default)
#   macos-defaults dry-run               # preview, never exits non-zero on drift
#   macos-defaults dry-run strict        # preview, exit 2 if any drift exists
#   macos-defaults dry-run "" verbose    # preview, also print unchanged settings
[group('macos')]
[doc('Apply or preview the curated macOS defaults. Modes: apply (default), dry-run [strict] [verbose].')]
macos-defaults $mode="apply" $strict="" $verbose="":
    @{{ sparkdock_path }}/sjust/scripts/macos-defaults/apply.sh "${mode}" "${strict}" "${verbose}"

# Restore the latest snapshot, list snapshots, or restore a specific one.
#   macos-defaults-undo                  # restore latest
#   macos-defaults-undo list             # list snapshots, no mutation
#   macos-defaults-undo <timestamp>      # restore a specific snapshot directory
[group('macos')]
[doc('Restore a snapshot from a previous macos-defaults apply.')]
macos-defaults-undo $action="":
    @{{ sparkdock_path }}/sjust/scripts/macos-defaults/undo.sh "${action}"

# Print, check, or write the macOS defaults docs table embedded in README.md.
#   macos-defaults-docs                  # print Markdown table to stdout
#   macos-defaults-docs check            # exit non-zero if README block is stale
#   macos-defaults-docs write            # rewrite README block with fresh table
[group('macos')]
[doc('Generate / verify the macOS defaults Markdown table embedded in README.md.')]
macos-defaults-docs $mode="print":
    @{{ sparkdock_path }}/sjust/scripts/macos-defaults/docs.sh "${mode}"

# Drop a commented overrides template at ~/.local/spark/macos-defaults/overrides.yml.
[group('macos')]
[doc('Bootstrap a personal overrides file with commented examples of common preferences.')]
macos-defaults-init-overrides:
    @{{ sparkdock_path }}/sjust/scripts/macos-defaults/init-overrides.sh
