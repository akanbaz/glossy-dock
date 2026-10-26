# Glossy Dock

A centered, frosted-glass app dock for KDE Plasma 6, made of three pieces you can use
together or separately:

| Piece | What it is | Installs as |
|---|---|---|
| **Glossy Dock** | The dock widget | Plasma widget `io.github.akanbaz.glossydock` |
| **Glossy Glass** | Dark frosted panel backgrounds; bottom panels hug their icons | Plasma style `glossy-glass` |
| **Glossy Dock panel** | One-click "Add Panel" entry: a centered, floating, auto-hiding dock | Panel template |

## Features

- **One fixed slot per pinned app.** Opening an app never adds, duplicates or shifts a pinned icon.
- **Open apps that aren't pinned** get a slot after the pins (can be turned off).
- **Icons that look the same size.** Icons with built-in empty space around their artwork
  are measured and drawn larger to match the others (can be turned off).
- **Hover magnification.** The hovered icon grows, its neighbours a little (both adjustable);
  the bar never resizes.
- **App names** off, on hover, or always shown under the icons.
- **Window state at a glance.** A short line under an open app, a longer bright one for the
  focused app, a faint one for a minimized app.
- **Clicks that do what you mean.** Click to launch, raise, minimize (if focused) or restore;
  middle click for a new window.
- **Window previews.** Hover an open app for a live thumbnail of each of its windows; hover a
  thumbnail to peek at just that window; click to switch; close from the preview.
- **A right-click menu** with the app's own actions (e.g. *New Incognito Window*), minimize,
  maximize, *Show all windows*, *Pin to Dock* / *Unpin from Dock*, and close.
- **Works on any edge**: bottom, top, left or right; icons size themselves to the panel.
- **Settings page** for pins (reorder, remove, add), icon size, dock height, gap,
  magnification, app names and behaviour.

## Requirements

- **KDE Plasma 6.** Developed and tested on Plasma 6.8 (Wayland). It's written against Plasma
  6.0 APIs, but versions before 6.8 haven't been tested yet; reports welcome.
- **Wayland** for live window thumbnails. On X11 everything else works and previews show the
  app icon instead.
- Optional, usually installed with Plasma: `kpipewire` (thumbnails), `plasma5support` (app
  actions in the menu), KWin's *Highlight Window* and *Window View* effects (peek and
  *Show all windows*). If one is missing, only that feature is switched off.

## Install

### From a release

Download `glossy-dock-<version>.tar.gz` from the
[releases page](https://github.com/akanbaz/glossy-dock/releases), then:

```bash
tar xf glossy-dock-*.tar.gz
cd glossy-dock-*/
./install.sh --add-dock
```

Or install just the widget: `kpackagetool6 -t Plasma/Applet -i glossy-dock-<version>.plasmoid`.

### From source

```bash
git clone https://github.com/akanbaz/glossy-dock.git
cd glossy-dock
./install.sh --add-dock
```

Everything installs into `~/.local/share/plasma` for your user only; no root needed.

`install.sh` options:

| Option | Effect |
|---|---|
| `--add-dock` | Add a dock to every screen that doesn't have one (prefers the bottom edge) |
| `--apply-style` | Switch the Plasma style to Glossy Glass (changes the look of all panels) |
| `--no-style` / `--no-template` | Skip the Plasma style / panel template |
| `--restart` | Restart Plasma afterwards; use this when upgrading |

## Use

- **Add a dock**: right-click the desktop → *Add Panel* → *Glossy Dock*.
- **The glass look**: System Settings → *Colors & Themes* → *Plasma Style* → *Glossy Glass*.
  The dock works with any Plasma style; Glossy Glass is what gives it the frosted look and
  ends that stay tight at any dock height. Its text and indicators are always light, since
  the glass is always dark.
- **Size**: *Icon size* (fit the panel, or fixed), *Dock height* (sets the panel's
  thickness) and *Gap between icons* in the dock's settings. With app names under the
  icons, a dock height of 56 px or more leaves room for both.
- **Pin an app**: open it, right-click its icon in the dock → *Pin to Dock*. Or add it by
  desktop-file name in the settings (e.g. `org.kde.dolphin`).
- **Settings**: right-click the dock → *Configure Glossy Dock…*

Pins are stored per dock, so each screen can have its own. Open/focused state is shared.

## Upgrade

Run `./install.sh --restart` from the new version. Plasma only loads widget code at start-up,
so without `--restart` the new version takes effect at your next login.

## Uninstall

```bash
./uninstall.sh --remove-docks
```

`--remove-docks` also deletes panels that contain nothing but a Glossy Dock;
`--keep-style` keeps the Glossy Glass Plasma style.

## Troubleshooting

- **The dock is empty or shows a faded icon**: none of its pinned apps are installed, and
  nothing is open. Right-click an open app → *Pin to Dock*, or add pins in the settings.
- **A pinned app disappeared**: its `.desktop` file is gone (app uninstalled or renamed).
  The settings page lists it as *not installed*.
- **No thumbnails in previews**: you're on X11, or `kpipewire` isn't installed.
- **See what went wrong**: `journalctl --user -b | grep -i glossydock`

## Development

```bash
scripts/lint.sh        # metadata, config schema, shell, QML syntax and type checks
scripts/smoke-test.sh  # boots a throwaway Plasma (virtual KWin, temporary HOME): install,
                       # --add-dock, panel template, docks on three edges, apps opening and
                       # closing, pin changes, settings page, uninstall; checks real window
                       # sizes through KWin and fails on any error from the dock
scripts/build.sh       # release files in dist/
tools/gen-panel-svg.py # regenerate the Glossy Glass SVGs after changing the generator
```

The smoke test never touches your running desktop or settings: it runs its own KWin
off-screen with a private D-Bus session and a temporary home folder.
It needs a GPU render device (`/dev/dri/renderD*`) for the steps that open app windows;
without one, as on GitHub's CI runners, it runs everything else and reports those steps as
skipped. Run it locally before releases.

Releases: bump `Version` in the three `metadata.json` files (lint checks they match), add a
CHANGELOG entry, then tag `v<version>` and push the tag; CI builds and publishes the release.

## License

GPL-2.0-or-later. See [LICENSE](LICENSE).
