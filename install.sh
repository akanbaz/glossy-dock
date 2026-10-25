#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Install or upgrade Glossy Dock for the current user (no root needed).
# Run from a source checkout or an extracted release.

set -euo pipefail

WIDGET_ID="io.github.akanbaz.glossydock"
TEMPLATE_ID="io.github.akanbaz.glossydock.panel"
STYLE_ID="glossy-glass"
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

with_style=1
with_template=1
add_dock=0
apply_style=0
restart=0

usage() {
    cat <<EOF
Usage: $0 [options]

Installs the Glossy Dock widget, the Glossy Glass Plasma style and the
"Glossy Dock" panel template into ~/.local/share/plasma. Re-running upgrades them.

Options:
  --add-dock      Add a Glossy Dock panel to every screen that doesn't have one
  --apply-style   Switch the Plasma style to Glossy Glass (affects all panels)
  --no-style      Don't install the Glossy Glass Plasma style
  --no-template   Don't install the "Glossy Dock" panel template
  --restart       Restart Plasma afterwards so an upgrade takes effect now
  -h, --help      Show this help
EOF
}

for arg in "$@"; do
    case "$arg" in
    --add-dock) add_dock=1 ;;
    --apply-style) apply_style=1 ;;
    --no-style) with_style=0 ;;
    --no-template) with_template=0 ;;
    --restart) restart=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

die() { echo "Error: $*" >&2; exit 1; }
note() { echo "==> $*"; }

command -v kpackagetool6 >/dev/null 2>&1 \
    || die "kpackagetool6 not found. Glossy Dock needs KDE Plasma 6 (package: kpackage)."

if command -v plasmashell >/dev/null 2>&1; then
    version=$(plasmashell --version 2>/dev/null | awk '{print $2}')
    major=${version%%.*}
    if [[ -n "$major" && "$major" =~ ^[0-9]+$ && "$major" -lt 6 ]]; then
        die "Plasma $version found; Glossy Dock needs Plasma 6.0 or newer."
    fi
    note "Plasma ${version:-unknown}"
else
    echo "Warning: plasmashell not found; installing anyway." >&2
fi

if [[ "${XDG_SESSION_TYPE:-}" != "wayland" ]]; then
    echo "Note: not a Wayland session. Everything works, but window previews show the app icon instead of a live thumbnail." >&2
fi

# Install, or upgrade when a package with this id is already there.
install_package() {
    local type=$1 dir=$2 id=$3
    [[ -f "$dir/metadata.json" ]] || die "missing $dir/metadata.json"
    if kpackagetool6 -t "$type" -s "$id" >/dev/null 2>&1; then
        note "Upgrading $id"
        kpackagetool6 -t "$type" -u "$dir" >/dev/null
    else
        note "Installing $id"
        kpackagetool6 -t "$type" -i "$dir" >/dev/null
    fi
}

install_package Plasma/Applet "$ROOT/plasmoid" "$WIDGET_ID"
if [[ $with_style -eq 1 ]]; then
    install_package Plasma/Theme "$ROOT/plasma-style/$STYLE_ID" "$STYLE_ID"
fi
if [[ $with_template -eq 1 ]]; then
    install_package Plasma/LayoutTemplate "$ROOT/panel-template" "$TEMPLATE_ID"
fi

qdbus_bin=$(command -v qdbus6 || command -v qdbus || true)

plasma_script() {
    [[ -n "$qdbus_bin" ]] || die "qdbus6 not found; can't talk to Plasma (package: qt6-tools)."
    "$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
}

if [[ $apply_style -eq 1 ]]; then
    if [[ $with_style -eq 1 ]] && command -v plasma-apply-desktoptheme >/dev/null 2>&1; then
        note "Applying the Glossy Glass Plasma style"
        plasma-apply-desktoptheme "$STYLE_ID" >/dev/null
    else
        echo "Warning: can't apply the style (not installed, or plasma-apply-desktoptheme missing)." >&2
    fi
fi

if [[ $restart -eq 1 ]]; then
    note "Restarting Plasma"
    if systemctl --user is-active --quiet plasma-plasmashell.service 2>/dev/null; then
        systemctl --user restart plasma-plasmashell.service
    else
        (kquitapp6 plasmashell >/dev/null 2>&1 || true) && (setsid -f plasmashell >/dev/null 2>&1 </dev/null || true)
    fi
    sleep 3
fi

if [[ $add_dock -eq 1 ]]; then
    note "Adding a dock to every screen that doesn't have one"
    plasma_script "
        var widget = '$WIDGET_ID';
        var hasDock = {};
        panels().forEach(function (p) {
            if (p.widgets(widget).length > 0) { hasDock[p.screen] = true; }
        });
        for (var s = 0; s < screenCount; ++s) {
            if (hasDock[s]) { continue; }
            var taken = {};
            panels().forEach(function (p) { if (p.screen == s) { taken[p.location] = true; } });
            var edge = ['bottom', 'left', 'right', 'top'].filter(function (e) { return !taken[e]; })[0];
            if (!edge) { print('screen ' + s + ': no free edge, skipped\n'); continue; }
            var panel = new Panel;
            panel.screen = s;
            panel.location = edge;
            panel.height = Math.round(gridUnit * 42 / 18);
            panel.floating = true;
            panel.lengthMode = 'fit';
            panel.alignment = 'center';
            panel.hiding = 'dodgewindows';
            panel.opacity = 'translucent';
            panel.addWidget(widget);
            print('screen ' + s + ': added a dock on the ' + edge + ' edge\n');
        }
    "
fi

cat <<EOF

Done.
  * Add a dock:   right-click the desktop > Add Panel > Glossy Dock
                  (or re-run with --add-dock)
  * Glass look:   System Settings > Colors & Themes > Plasma Style > Glossy Glass
                  (or re-run with --apply-style)
  * Settings:     right-click the dock > Configure Glossy Dock
EOF
if [[ $restart -eq 0 ]]; then
    echo "  * Upgrading?   run with --restart (or log out and in) so Plasma loads the new version."
fi
