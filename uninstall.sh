#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Remove Glossy Dock for the current user.

set -euo pipefail

WIDGET_ID="io.github.akanbaz.glossydock"
TEMPLATE_ID="io.github.akanbaz.glossydock.panel"
STYLE_ID="glossy-glass"

remove_docks=0
keep_style=0

usage() {
    cat <<EOF
Usage: $0 [options]

Removes the Glossy Dock widget, the "Glossy Dock" panel template and the
Glossy Glass Plasma style from ~/.local/share/plasma.

Options:
  --remove-docks  Also delete panels whose only widget is Glossy Dock
  --keep-style    Keep the Glossy Glass Plasma style installed
  -h, --help      Show this help
EOF
}

for arg in "$@"; do
    case "$arg" in
    --remove-docks) remove_docks=1 ;;
    --keep-style) keep_style=1 ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
done

note() { echo "==> $*"; }

command -v kpackagetool6 >/dev/null 2>&1 || { echo "Error: kpackagetool6 not found." >&2; exit 1; }

if [[ $remove_docks -eq 1 ]]; then
    qdbus_bin=$(command -v qdbus6 || command -v qdbus || true)
    if [[ -n "$qdbus_bin" ]]; then
        note "Removing dock panels"
        "$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
            panels().forEach(function (p) {
                var all = p.widgets();
                if (all.length > 0 && p.widgets('$WIDGET_ID').length === all.length) { p.remove(); }
            });
        " >/dev/null
    else
        echo "Warning: qdbus6 not found; remove the dock panels by hand." >&2
    fi
fi

remove_package() {
    local type=$1 id=$2
    if kpackagetool6 -t "$type" -s "$id" >/dev/null 2>&1; then
        note "Removing $id"
        kpackagetool6 -t "$type" -r "$id" >/dev/null
    fi
}

if [[ $keep_style -eq 0 ]]; then
    current=$(kreadconfig6 --file plasmarc --group Theme --key name 2>/dev/null || true)
    if [[ "$current" == "$STYLE_ID" ]]; then
        echo "Note: Glossy Glass is the active Plasma style; switching back to Breeze." >&2
        plasma-apply-desktoptheme default >/dev/null 2>&1 || true
    fi
    remove_package Plasma/Theme "$STYLE_ID"
fi
remove_package Plasma/LayoutTemplate "$TEMPLATE_ID"
remove_package Plasma/Applet "$WIDGET_ID"

echo
echo "Done. Panels that still hold the dock show it as missing until you remove them."
