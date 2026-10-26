# Changelog

## Unreleased

- Settings: dock height (sets the panel's thickness), separate magnification for the icons
  next to the hovered one, and app names off / on hover / always under the icons.
- Icons are drawn at the dock's real icon size (they were rounded down to the nearest
  standard size, e.g. 29px icons drawn at 22px).
- "Even out icon sizes" (on by default): icons whose artwork has built-in empty space are
  measured once and drawn larger (up to 1.3x), so all icons look the same size and hover
  zoom looks the same on all of them.
- Glossy Glass: tight ends on every edge at any panel height (they used to grow on taller
  top, left and right panels), and fixed dark-glass colours so text and indicators stay
  readable with a light colour scheme.

## 1.0.0

First public release.

- Dock widget with fixed pinned slots, open-app slots, hover magnification, open/focused/minimized
  indicators, window previews with peek, and a right-click menu with app actions, window
  controls and pin/unpin.
- Works on bottom, top, left and right panels; icon size follows the panel by default.
- Settings page for pins, icon size, gap, magnification and behaviour.
- Pins whose app isn't installed are skipped instead of showing an empty slot.
- Optional features (thumbnails, peek, app actions) load separately and switch off cleanly
  when their system component is missing.
- Glossy Glass Plasma style and a "Glossy Dock" panel template.
- Right-click menu items, previews and app actions follow the app (and window) they were
  opened for, even if apps open or close while the menu is up.
- Panels stay free to auto-hide after moving between previews and name tooltips.
- The 4px end-gap compensation only applies when the dock is alone in its panel.
- Unpinning removes every pin entry for that app.
- install.sh / uninstall.sh, lint, isolated Plasma smoke test that measures the real dock
  windows through apps opening/closing and pin changes, reproducible release builds.
