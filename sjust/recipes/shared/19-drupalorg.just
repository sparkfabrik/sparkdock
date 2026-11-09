# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/19-drupalorg.just lives at <sparkdock_root>/sjust/recipes/shared/
_drupalorg_cli_sh := clean(source_directory() / "../../..") / "sjust/scripts/drupalorg-cli.sh"

# Actions: install (also updates), info, uninstall, mcp, mcp-remove. No action prints usage.
# Releases younger than 7 days are skipped; set DRUPALORG_MIN_AGE_DAYS=0 to disable.
# Examples: sjust drupal-org-cli install, sjust drupal-org-cli info
# Install, update or remove the Drupal.org CLI (drupalorg) and its agent skill. Requires PHP 8.1+.
[group('drupal')]
drupal-org-cli $action="":
    @bash "{{_drupalorg_cli_sh}}" "${action}"
