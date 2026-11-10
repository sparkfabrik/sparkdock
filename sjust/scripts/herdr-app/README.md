# SparkFabrik layout for herdr-app

The Herdr desktop app (`herdr-app`) in the SparkFabrik design system. `setup.sh install` copies the pack in `sparkfabrik/` into the app's home; `setup.sh uninstall` removes it. On macOS provisioning runs the install (`herdr-layout` tag); anyone can run it with `sjust herdr-layout-install`.

When the app is installed (the macOS cask, Herdr's Linux installer or a package) but was never opened, the install creates its home first, so the first start already shows the layout. The install also selects the layout once per app home, existing installs included: over the app's control socket (`herdr-app.sock` in its home) when a window is open, else in the app's `shared.json`, so it shows on the next start. A `.sparkdock-layout-selected` file in the home records it, so later runs only keep the files current and a person who switches back to Herdr's own layout keeps that choice; uninstalling removes the file. `SPARKDOCK_HERDR_LAYOUT_SELECT=0` turns the selection off when you run the recipe; provisioning does not read the shell environment, and neither does it read `HERDR_APP_HOME` or `XDG_CONFIG_HOME`.

The layout needs the herdr-app release in `HERDR_APP_MIN_VERSION` (0.1.13) or a later one: every mod passes `herdr-app check` from that release on. The tabs mod keeps the active tab scrolled into view only from 0.1.15, where Herdr gives mods a `ScrollHandle`; on older releases the rest of the tab bar works the same, and an app that updates gets the scrolling on its next start. The script reads the version from the app itself (the macOS bundle, Herdr's Linux installer, a package, or `herdr-app` on PATH). It skips an older app with a message, and installs without selecting when the version cannot be read.

Provisioning runs `setup.sh provision`, `sjust herdr-layout-install` runs `setup.sh install`. They differ only after `sjust herdr-layout-uninstall`: uninstall switches Herdr back to its own layout when SparkFabrik is the one shown, removes the files and writes `.sparkdock-layout-removed`, so provisioning stays away until someone runs the install recipe again. Herdr's Appearance setting (System, Light, Dark) picks one of the two themes. When the layout is removed while selected, Herdr falls back to its own layout on the next start.

## What the pack contains

| Path                               | What it is                                                                                                                                                                                    |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `layouts/sparkfabrik.json`, `.svg` | The layout, derived from Herdr's `main` layout, and its preview in the layout picker. It sets `theme` to `{light, dark}` and `ui_font` to Barlow, and leaves the terminal font to the person. |
| `themes/sparkfabrik.json`          | Dark theme: navy interface and terminal.                                                                                                                                                      |
| `themes/sparkfabrik-light.json`    | Light theme: paper interface, light terminal.                                                                                                                                                 |
| `mods/sparkfabrik-*`               | Forks of Herdr's own mods, restyled with the app kit (see below).                                                                                                                             |
| `HERDR_APP_VERSION`                | The herdr-app release the mods were forked from; a newer app gets a drift warning when files are installed.                                                                                   |

The colours come from the tokens of the SparkFabrik design system. The fonts (Barlow, Barlow Condensed, Azeret Mono) are OFL licensed, with each license next to its files.

## The forked mods

| Mod                  | Forked from        | What changes                                                                                                                                                                                                                                                                |
| -------------------- | ------------------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `sparkfabrik-chrome` | `workspace-chrome` | Brand row and sidebar footer. Also holds the app kit's LED icons in `icons/` and copies of the Herdr icons the forks use in `herdr-icons/` (Lucide, ISC), so an upstream rename cannot break them; `verify-setup.sh` checks that every mod loads assets only from the pack. |
| `sparkfabrik-spaces` | `spaces`           | Spaces list with LED seeds instead of colour chips.                                                                                                                                                                                                                         |
| `sparkfabrik-agents` | `agents`           | Agents list with LED seeds for the agent state.                                                                                                                                                                                                                             |
| `sparkfabrik-tabs`   | `tabs`             | Text tabs and bordered buttons.                                                                                                                                                                                                                                             |
| `sparkfabrik-pane`   | `pane`             | Pane header with the state as seed and word.                                                                                                                                                                                                                                |
| `sparkfabrik-status` | `workspace-status` | Status bar with the SparkFabrik harness mark and keycaps.                                                                                                                                                                                                                   |

Each fork keeps the behaviour of the original and changes only how it looks. Sizes are logical pixels (Herdr multiplies them by the person's zoom), mapped from the app kit with `u(px) = 11.8 * px / 15`.

## After a herdr-app upgrade

`setup.sh` warns, when it installs files, that the installed herdr-app is newer than the release in `HERDR_APP_VERSION`. Then:

1. Compare each original mod with the release it was forked from, in the [herdr-app repository](https://github.com/herdrdev/herdr-app) under `defaults/mods/`.
2. Port the upstream changes into the matching `sparkfabrik-*` fork, keeping the SparkFabrik styling.
3. Check each fork with `herdr-app check <mod folder>` on a copy installed in a test home (never on this folder: the check writes editor files into it), test it as described below, and update `HERDR_APP_VERSION`.
4. When a fork starts using an API newer than `HERDR_APP_MIN_VERSION`, use it only where it exists (see how the tabs mod reads `ScrollHandle`) or raise the minimum. To check an older release, download it from `https://releases.herdr.dev/app/<version>/manifest.json`, verify its sha256, and run its `check` in a container: herdr-app 0.1.13's `check` stops the local herdr-core and every terminal session.

## Testing

`verify-setup.sh` checks the pack and the install, reinstall and uninstall paths under a temporary `HOME`; CI runs it on Linux and macOS. To see the layout, use a separate app home so your own window is untouched:

```bash
HERDR_APP_HOME=~/.config/herdr-app-test sjust/scripts/herdr-app/setup.sh install
HERDR_APP_HOME=~/.config/herdr-app-test HERDR_APP_ID=herdr-app-test herdr-app
HERDR_APP_HOME=~/.config/herdr-app-test herdr-app do layout.switch --name sparkfabrik
HERDR_APP_HOME=~/.config/herdr-app-test herdr-app shot layout.png
```

herdr-app loads new mods only when it starts, so restart the test window after installing.
