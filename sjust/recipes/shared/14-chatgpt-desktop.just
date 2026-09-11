# vim: set ft=make :

# Path to the helper script, resolved from this recipe file's location:
# shared/14-chatgpt-desktop.just lives at <sparkdock_root>/sjust/recipes/shared/
_chatgpt_desktop_sh := clean(source_directory() / "../../..") / "sjust/scripts/chatgpt-desktop.sh"

# Install or update the ChatGPT desktop app (opt-in): Homebrew cask on macOS, sf-toolbox on Linux.
[group('desktop-apps')]
chatgpt-desktop-install:
    @bash "{{_chatgpt_desktop_sh}}" install
