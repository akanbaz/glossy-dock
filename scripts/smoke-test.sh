#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# End-to-end check in a throwaway Plasma session: a virtual (off-screen) KWin, a private
# D-Bus session and a temporary HOME, so nothing touches the running desktop or your
# settings. Installs the packages, adds docks on the bottom, left and top edges (each with
# a pin whose app doesn't exist), checks their sizes, and fails on any error from the dock.
#
# Usage: scripts/smoke-test.sh [screenshot.png]
# Needs: kwin_wayland, plasmashell, dbus-run-session, qdbus6; optional: Qt 6 qml tool
# (settings page check), spectacle (screenshot).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WIDGET_ID="io.github.akanbaz.glossydock"

if [[ -z "${GLOSSY_SMOKE_INNER:-}" ]]; then
    for tool in kwin_wayland plasmashell dbus-run-session; do
        command -v "$tool" >/dev/null 2>&1 || { echo "smoke test needs $tool" >&2; exit 2; }
    done
    screenshot=${1:-}
    [[ -z "$screenshot" ]] || screenshot=$(realpath -m "$screenshot")

    # Isolate everything BEFORE the private D-Bus session starts: services that D-Bus
    # launches on demand (kded6, portals, kdeconnectd, ...) inherit the daemon's
    # environment, so they must never see the real HOME, runtime dir or display.
    work=$(mktemp -d -t glossy-smoke.XXXXXX)
    export HOME="$work/home"
    export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
    export XDG_CACHE_HOME="$HOME/.cache" XDG_STATE_HOME="$HOME/.local/state"
    export XDG_RUNTIME_DIR="$work/runtime"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    mkdir -m 700 "$XDG_RUNTIME_DIR"
    export WAYLAND_DISPLAY=wayland-glossy QT_QPA_PLATFORM=wayland XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP=KDE KDE_FULL_SESSION=true KDE_SESSION_VERSION=6
    # Qt logs to the journal when stderr is not a terminal; the test needs the logs here.
    export QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_RULES="qml.info=true;js.info=true"
    unset DISPLAY DBUS_SESSION_BUS_ADDRESS SESSION_MANAGER XAUTHORITY
    exec dbus-run-session -- env GLOSSY_SMOKE_INNER=1 GLOSSY_SMOKE_WORK="$work" "$0" "$screenshot"
fi

screenshot=${1:-}
work=${GLOSSY_SMOKE_WORK:?}
case "$HOME" in "$work"/*) ;; *) echo "refusing to run: HOME is not isolated" >&2; exit 2 ;; esac
kwin_pid=""
plasma_pid=""

# Every process attached to this private bus, including services D-Bus started on demand.
session_pids() {
    local p
    for p in /proc/[0-9]*; do
        [[ -r "$p/environ" && "${p#/proc/}" != "$$" ]] || continue
        { tr '\0' '\n' <"$p/environ"; } 2>/dev/null \
            | grep -qxF "DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" && echo "${p#/proc/}"
    done
    return 0
}

cleanup() {
    local status=$?
    set +e
    [[ -n "$plasma_pid" ]] && kill "$plasma_pid" 2>/dev/null
    [[ -n "$kwin_pid" ]] && kill "$kwin_pid" 2>/dev/null
    sleep 1
    # shellcheck disable=SC2046
    kill $(session_pids) 2>/dev/null
    sleep 0.5
    # shellcheck disable=SC2046
    kill -9 $(session_pids) 2>/dev/null
    if [[ -n "${KEEP_SMOKE_LOGS:-}" ]]; then
        echo "logs kept in $work"
    else
        rm -rf "$work"
    fi
    exit "$status"
}
trap cleanup EXIT

qdbus_bin=$(command -v qdbus6 || command -v qdbus)
shell() { "$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"; }

wait_for() {
    local what=$1 tries=$2
    shift 2
    for ((i = 0; i < tries; i++)); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 0.5
    done
    echo "FAIL: timed out waiting for $what" >&2
    return 1
}

echo "==> Starting a virtual KWin"
kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --socket "$WAYLAND_DISPLAY" \
    --width 1920 --height 1080 >"$work/kwin.log" 2>&1 &
kwin_pid=$!
wait_for "KWin" 60 test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" || { cat "$work/kwin.log"; exit 1; }

echo "==> Installing packages into the temporary home"
"$ROOT/install.sh" >"$work/install.log" 2>&1 || { cat "$work/install.log"; exit 1; }

# A fresh HOME has no application cache yet; until it's built, apps can't be looked up.
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    echo "==> Building the application cache"
    kbuildsycoca6 --noincremental >"$work/sycoca.log" 2>&1 || true
fi

echo "==> Starting Plasma"
plasmashell --no-respawn >"$work/plasma.log" 2>&1 &
plasma_pid=$!
wait_for "plasmashell" 90 shell "print('up')" || { tail -50 "$work/plasma.log"; exit 1; }
sleep 3

echo "==> Adding docks on the bottom, left and top edges"
shell "
    panels().forEach(function (p) { p.remove(); });
    ['bottom', 'left', 'top'].forEach(function (edge, n) {
        var panel = new Panel;
        panel.location = edge;
        panel.height = 42;
        panel.floating = true;
        panel.lengthMode = 'fit';
        panel.alignment = 'center';
        panel.hiding = n === 0 ? 'dodgewindows' : 'none';
        var w = panel.addWidget('$WIDGET_ID');
        w.currentConfigGroup = ['General'];
        // Apps every Plasma test environment has, plus one that doesn't exist and must be
        // skipped rather than shown as a blank slot.
        w.writeConfig('debugLog', true);
        w.writeConfig('launchers', 'applications:systemsettings.desktop,applications:does-not-exist.desktop,applications:org.kde.konsole.desktop');
        if (n === 2) {
            w.writeConfig('iconSize', 24);
            w.writeConfig('zoomPercent', 0);
            w.writeConfig('showPreviews', false);
        }
    });
" >/dev/null

# Pins resolve asynchronously; wait until all three docks have their final size.
get_report() {
    shell "
        var out = [];
        panels().forEach(function (p) {
            out.push(p.location + ' length=' + p.length + ' docks=' + p.widgets('$WIDGET_ID').length);
        });
        print(out.join('\n'));
    "
}
want_report=$'bottom length=96 docks=1\nleft length=96 docks=1\ntop length=86 docks=1'
for ((i = 0; i < 80; i++)); do
    report=$(get_report)
    [[ "$(sort <<<"$report")" == "$(sort <<<"$want_report")" ]] && break
    sleep 0.5
done
sleep 1

# Plasma's reported length can disagree with the panel window actually on screen, so also
# ask KWin for the real width of the bottom dock's window.
kwin_bottom_width() {
    local js="$work/measure-$RANDOM.js" id
    cat >"$js" <<'JS'
var widths = [];
workspace.windowList().forEach(function (w) {
    var g = w.frameGeometry;
    if (w.dock && g.width > g.height && g.y > 540) { widths.push(Math.round(g.width)); }
});
console.info("glossy-bottom-width: " + widths.join(","));
JS
    id=$("$qdbus_bin" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" "measure$RANDOM")
    "$qdbus_bin" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null
    sleep 0.5
    "$qdbus_bin" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.stop >/dev/null 2>&1 || true
    grep -oP 'glossy-bottom-width: \K[0-9,]*' "$work/kwin.log" | tail -1
}
bottom_before=$(kwin_bottom_width)
echo "$report" | sed 's/^/    /'

if [[ -n "$screenshot" ]] && command -v spectacle >/dev/null 2>&1; then
    spectacle -b -n -f -o "$screenshot" >/dev/null 2>&1 && echo "==> Screenshot: $screenshot" || echo "(screenshot failed)"
fi

failed=0
# Any QML error or warning from the dock's files fails the test.
if grep -nE "$WIDGET_ID|glossydock" "$work/plasma.log" | grep -iE "error|warning|TypeError|ReferenceError|cannot|failed|not installed|undefined" >"$work/errors.txt"; then
    echo "FAIL: Plasma reported problems with the dock:"
    sed 's/^/    /' "$work/errors.txt"
    failed=1
fi
if [[ $(grep -c "docks=1" <<<"$report") -ne 3 ]]; then
    echo "FAIL: expected three panels with one dock each"
    failed=1
fi
# Two icons each (the missing pin is skipped) with an 18px gap and 10px at each end:
# auto-sized icons are 29px on a 42px panel; the top dock is set to 24px icons.
expect() {
    local edge=$1 want=$2 got
    got=$(grep -oP "^$edge length=\K-?[0-9]+" <<<"$report" || echo none)
    if [[ "$got" != "$want" ]]; then
        echo "FAIL: $edge dock is $got px long, expected $want"
        failed=1
    fi
}
# Each dock must end up showing exactly System Settings and Konsole: the missing pin is
# skipped. Log lines are "glossydock-slots: <applet id> <app> | <app> ...".
shown=$(grep -oP 'glossydock-slots: \K.*' "$work/plasma.log" \
    | awk '{ id = $1; $1 = ""; last[id] = substr($0, 2) } END { for (id in last) print last[id] }' \
    | sort | uniq -c || true)
if [[ "$(awk '{$1=$1; print}' <<<"$shown")" != "3 System Settings | Konsole" ]]; then
    echo "FAIL: docks show:"
    sed 's/^/    /' <<<"$shown"
    echo "    expected all three to show: System Settings | Konsole"
    failed=1
fi

expect bottom $((2 * 29 + 18 + 20))
expect left $((2 * 29 + 18 + 20))
expect top $((2 * 24 + 18 + 20))

# Unpinning an app must shrink the dock window by exactly one icon and one gap (29 + 18).
echo "==> Unpinning an app from the bottom dock"
shell "
    panels().forEach(function (p) {
        if (p.location !== 'bottom') { return; }
        p.widgets('$WIDGET_ID').forEach(function (w) {
            w.currentConfigGroup = ['General'];
            w.writeConfig('launchers', 'applications:systemsettings.desktop');
        });
    });
" >/dev/null
bottom_after=""
for ((i = 0; i < 40; i++)); do
    sleep 0.5
    bottom_after=$(kwin_bottom_width)
    [[ -n "$bottom_after" && -n "$bottom_before" && "$bottom_after" =~ ^[0-9]+$ && "$bottom_before" =~ ^[0-9]+$ ]] \
        && (( bottom_before - bottom_after == 47 )) && break
done
echo "    bottom dock window: ${bottom_before:-?} px -> ${bottom_after:-?} px"
if ! [[ "$bottom_before" =~ ^[0-9]+$ && "$bottom_after" =~ ^[0-9]+$ ]] || (( bottom_before - bottom_after != 47 )); then
    echo "FAIL: the bottom dock window should shrink by 47 px after unpinning one app"
    failed=1
fi

# The settings page, loaded on its own: it must load cleanly and its pin logic must hold.
qml_bin=""
for candidate in /usr/lib/qt6/bin/qml /usr/lib/x86_64-linux-gnu/qt6/bin/qml /usr/lib64/qt6/bin/qml; do
    [[ -x "$candidate" ]] && { qml_bin=$candidate; break; }
done
if [[ -n "$qml_bin" ]]; then
    echo "==> Checking the settings page"
    if timeout 30 "$qml_bin" "$ROOT/tests/ConfigPageTest.qml" >"$work/config.log" 2>&1 \
        && grep -q "PASS: settings page" "$work/config.log" \
        && ! grep -E "ConfigGeneral\.qml.*(Error|error|undefined|Cannot)" "$work/config.log"; then
        echo "    settings page OK"
    else
        echo "FAIL: settings page:"
        sed 's/^/    /' "$work/config.log" | tail -20
        failed=1
    fi
else
    echo "skip: Qt 6 qml tool not found; settings page not checked"
fi

if [[ $failed -ne 0 ]]; then
    KEEP_SMOKE_LOGS=1
    exit 1
fi
echo "Smoke test passed."
