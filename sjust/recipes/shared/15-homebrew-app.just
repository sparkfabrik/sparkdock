# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/15-homebrew-app.just lives at <sparkdock_root>/sjust/recipes/shared/
_homebrew_app_sh := clean(source_directory() / "../../..") / "sjust/scripts/homebrew-app.sh"

# Install the official Homebrew desktop app, BrewUI (opt-in, macOS 26 or later).
[group('desktop-apps')]
homebrew-app-install:
    @bash "{{_homebrew_app_sh}}" install
