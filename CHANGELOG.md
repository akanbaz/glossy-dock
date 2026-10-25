# Changelog

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
- install.sh / uninstall.sh, lint, isolated Plasma smoke test, reproducible release builds.
