# SparkFabrik layout for herdr-app

The Herdr desktop app (`herdr-app`) in the SparkFabrik design system. `setup.sh install` copies the pack in `sparkfabrik/` into the app's home; `setup.sh uninstall` removes it. On macOS provisioning runs the install (`herdr-layout` tag); anyone can run it with `sjust herdr-layout-install`.

The install also selects the layout once per app home, existing installs included: over the app's control socket (`herdr-app.sock` in its home) when a window is open, else in the app's `shared.json`, so it shows on the next start. A `.sparkdock-layout-selected` file in the home records it, so later runs only keep the files current and a person who switches back to Herdr's own layout keeps that choice; uninstalling removes the file. `SPARKDOCK_HERDR_LAYOUT_SELECT=0` turns the selection off. Herdr's Appearance setting (System, Light, Dark) picks one of the two themes. When the layout is removed while selected, Herdr falls back to its own layout on the next start.

## What the pack contains

| Path                               | What it is                                                                                                                                                                                    |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `layouts/sparkfabrik.json`, `.svg` | The layout, derived from Herdr's `main` layout, and its preview in the layout picker. It sets `theme` to `{light, dark}` and `ui_font` to Barlow, and leaves the terminal font to the person. |
| `themes/sparkfabrik.json`          | Dark theme: navy interface and terminal.                                                                                                                                                      |
| `themes/sparkfabrik-light.json`    | Light theme: paper interface, light terminal.                                                                                                                                                 |
| `mods/sparkfabrik-*`               | Forks of Herdr's own mods, restyled with the app kit (see below).                                                                                                                             |
| `HERDR_APP_VERSION`                | The herdr-app release the mods were forked from.                                                                                                                                              |

The colours come from the tokens of the SparkFabrik design system. The fonts (Barlow, Barlow Condensed, Azeret Mono) are OFL licensed, with each license next to its files.

## The forked mods

| Mod                  | Forked from        | What changes                                                                                                                  |
| -------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `sparkfabrik-chrome` | `workspace-chrome` | Brand row and sidebar footer. Also holds the app kit's LED icons in `icons/`, used by the spaces, agents, tabs and pane mods. |
| `sparkfabrik-spaces` | `spaces`           | Spaces list with LED seeds instead of colour chips.                                                                           |
| `sparkfabrik-agents` | `agents`           | Agents list with LED seeds for the agent state.                                                                               |
| `sparkfabrik-tabs`   | `tabs`             | Text tabs and bordered buttons.                                                                                               |
| `sparkfabrik-pane`   | `pane`             | Pane header with the state as seed and word.                                                                                  |
| `sparkfabrik-status` | `workspace-status` | Status bar with the SparkFabrik harness mark and keycaps.                                                                     |

Each fork keeps the behaviour of the original and changes only how it looks. Sizes are logical pixels (Herdr multiplies them by the person's zoom), mapped from the app kit with `u(px) = 11.8 * px / 15`.

## After a herdr-app upgrade

`setup.sh` warns when the installed herdr-app is not the release in `HERDR_APP_VERSION`. Then:

1. Compare each original mod with the release it was forked from, in the [herdr-app repository](https://github.com/herdrdev/herdr-app) under `defaults/mods/`.
2. Port the upstream changes into the matching `sparkfabrik-*` fork, keeping the SparkFabrik styling.
3. Check each fork with `herdr-app check <mod folder>`, test it as described below, and update `HERDR_APP_VERSION`.

## Testing

`verify-setup.sh` checks the pack and the install, reinstall and uninstall paths under a temporary `HOME`; CI runs it on Linux and macOS. To see the layout, use a separate app home so your own window is untouched:

```bash
HERDR_APP_HOME=~/.config/herdr-app-test sjust/scripts/herdr-app/setup.sh install
HERDR_APP_HOME=~/.config/herdr-app-test HERDR_APP_ID=herdr-app-test herdr-app
HERDR_APP_HOME=~/.config/herdr-app-test herdr-app do layout.switch --name sparkfabrik
HERDR_APP_HOME=~/.config/herdr-app-test herdr-app shot layout.png
```

herdr-app loads new mods only when it starts, so restart the test window after installing.
