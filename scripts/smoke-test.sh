#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# End-to-end check in a throwaway Plasma session: a virtual (off-screen) KWin, a private
# D-Bus session and a temporary HOME, so nothing touches the running desktop or your
# settings. Everything is checked against what is really on screen (window geometry from
# KWin), and through changes after start-up, not just the first layout:
#
#   1. install.sh --add-dock adds one dock, and running it again adds no second one
#   2. the "Glossy Dock" panel template adds a dock, then another on a free edge
#   3. docks on the bottom, left and top edges show exactly the installed pins (a pin
#      whose app doesn't exist is skipped) and their windows agree with each other
#   4. opening a pinned app adds nothing; opening an unpinned app adds one slot; closing
#      it, unpinning an open app and closing that app each change the width by exactly
#      one icon and one gap
#   5. the settings page loads and its pin logic holds
#   6. uninstall.sh --remove-docks removes the dock panels and the packages
#
# Any error or warning that Plasma logs from the dock fails the test.
#
# Usage: scripts/smoke-test.sh [screenshot.png]
# Needs: kwin_wayland, plasmashell, dbus-run-session, qdbus6, kpackagetool6, konsole,
#        the Qt 6 qml tool; optional: spectacle (screenshot).

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WIDGET_ID="io.github.akanbaz.glossydock"
TEMPLATE_ID="io.github.akanbaz.glossydock.panel"

if [[ -z "${GLOSSY_SMOKE_INNER:-}" ]]; then
    for tool in kwin_wayland plasmashell dbus-run-session kpackagetool6 konsole; do
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
failed=0

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

fail() { echo "FAIL: $*"; failed=1; }
step() { echo "==> $*"; }

qdbus_bin=$(command -v qdbus6 || command -v qdbus)
qml_bin=""
for candidate in /usr/lib/qt6/bin/qml /usr/lib/x86_64-linux-gnu/qt6/bin/qml /usr/lib64/qt6/bin/qml; do
    [[ -x "$candidate" ]] && { qml_bin=$candidate; break; }
done
[[ -n "$qml_bin" ]] || { echo "smoke test needs the Qt 6 qml tool" >&2; exit 2; }

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

# Run a KWin script and return what it printed (one line, tagged).
kwin_eval() {
    local js="$work/kwin-$RANDOM$RANDOM.js" tag="glossy-kwin-$RANDOM$RANDOM" id
    printf 'console.info("%s " + (function () {\n%s\n})());\n' "$tag" "$1" >"$js"
    id=$("$qdbus_bin" org.kde.KWin /Scripting org.kde.kwin.Scripting.loadScript "$js" "$tag")
    "$qdbus_bin" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.run >/dev/null
    for ((i = 0; i < 20; i++)); do
        grep -q "$tag " "$work/kwin.log" && break
        sleep 0.1
    done
    "$qdbus_bin" org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script.stop >/dev/null 2>&1 || true
    grep -oP "$tag \\K.*" "$work/kwin.log" | tail -1 || true
}

# Real on-screen length of each dock window: "bottom=W left=H top=W" (as present).
dock_windows() {
    kwin_eval '
        var out = [];
        workspace.windowList().forEach(function (w) {
            if (!w.dock) { return; }
            var g = w.frameGeometry;
            if (g.width > g.height) { out.push((g.y > 540 ? "bottom=" : "top=") + Math.round(g.width)); }
            else { out.push((g.x < 960 ? "left=" : "right=") + Math.round(g.height)); }
        });
        return out.sort().join(" ");'
}
dock_len() { grep -oP "(^| )$1=\\K[0-9]+" <<<"$(dock_windows)" || echo 0; }

# Panels as Plasma sees them: "edge:docks" per panel.
panel_summary() {
    shell "
        var out = [];
        panels().forEach(function (p) { out.push(p.location + ':' + p.widgets('$WIDGET_ID').length); });
        print(out.sort().join(' '));
    "
}

# The applet id of the dock on an edge, for matching its log lines.
dock_applet_id() {
    shell "
        panels().forEach(function (p) {
            if (p.location === '$1') { p.widgets('$WIDGET_ID').forEach(function (w) { print(w.id); }); }
        });
    "
}

# Latest list of apps a dock logged (needs debugLog on that dock).
dock_apps() { grep -oP "glossydock-slots: $1 \\K.*" "$work/plasma.log" | tail -1 || true; }

wait_apps() {
    local id=$1 want=$2
    for ((i = 0; i < 80; i++)); do
        [[ "$(dock_apps "$id")" == "$want" ]] && return 0
        sleep 0.25
    done
    fail "dock $id shows [$(dock_apps "$id")], expected [$want]"
    return 0
}

# Wait for the bottom dock window to reach a length (it animates and re-lays out).
wait_bottom() {
    local want=$1 what=$2 got=0
    for ((i = 0; i < 60; i++)); do
        got=$(dock_len bottom)
        [[ "$got" == "$want" ]] && { echo "    $what: bottom dock $got px"; return 0; }
        sleep 0.25
    done
    fail "$what: bottom dock window is $got px, expected $want"
    return 0
}

window_count() {
    kwin_eval "
        var n = 0;
        workspace.windowList().forEach(function (w) { if (w.normalWindow && w.caption.indexOf('$1') >= 0) { n++; } });
        return n;"
}

has_window() { [[ "$(window_count "$1")" -ge 1 ]]; }

# ------------------------------------------------------------------- session

step "Starting a virtual KWin"
kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --socket "$WAYLAND_DISPLAY" \
    --width 1920 --height 1080 >"$work/kwin.log" 2>&1 &
kwin_pid=$!
wait_for "KWin" 60 test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" || { cat "$work/kwin.log"; exit 1; }

step "Installing packages into the temporary home"
"$ROOT/install.sh" >"$work/install.log" 2>&1 || { cat "$work/install.log"; exit 1; }

# A fresh HOME has no application cache yet; until it's built, apps can't be looked up.
kbuildsycoca6 --noincremental >"$work/sycoca.log" 2>&1 || true

step "Starting Plasma"
plasmashell --no-respawn >"$work/plasma.log" 2>&1 &
plasma_pid=$!
wait_for "plasmashell" 90 shell "print('up')" || { tail -50 "$work/plasma.log"; exit 1; }
sleep 3

# ------------------------------------------------------------------- 1. install.sh --add-dock

step "install.sh --add-dock"
shell "panels().forEach(function (p) { p.remove(); });" >/dev/null
"$ROOT/install.sh" --add-dock >"$work/add-dock.log" 2>&1 || { cat "$work/add-dock.log"; fail "install.sh --add-dock"; }
"$ROOT/install.sh" --add-dock >>"$work/add-dock.log" 2>&1 || fail "install.sh --add-dock (second run)"
sleep 2
got=$(panel_summary)
if [[ "$got" == "bottom:1" ]]; then
    echo "    one dock on the bottom, not added twice"
else
    fail "after --add-dock twice, panels are [$got], expected [bottom:1]"
fi

# ------------------------------------------------------------------- 2. panel template

step "Add Panel > Glossy Dock template"
shell "panels().forEach(function (p) { p.remove(); });" >/dev/null
shell "loadTemplate('$TEMPLATE_ID'); loadTemplate('$TEMPLATE_ID');" >/dev/null
sleep 2
got=$(panel_summary)
if [[ "$got" == "bottom:1 left:1" ]]; then
    echo "    first on the bottom, second on the next free edge"
else
    fail "after adding the template twice, panels are [$got], expected [bottom:1 left:1]"
fi

# ------------------------------------------------------------------- 3. three edges

step "Docks on the bottom, left and top edges"
shell "
    panels().forEach(function (p) { p.remove(); });
    ['bottom', 'left', 'top'].forEach(function (edge) {
        var panel = new Panel;
        panel.location = edge;
        panel.height = 42;
        panel.floating = true;
        panel.lengthMode = 'fit';
        panel.alignment = 'center';
        panel.hiding = 'none';
        var w = panel.addWidget('$WIDGET_ID');
        w.currentConfigGroup = ['General'];
        w.writeConfig('debugLog', true);
        // Apps every Plasma test environment has, plus one that doesn't exist and must be
        // skipped rather than shown as a blank slot.
        w.writeConfig('launchers', 'applications:systemsettings.desktop,applications:does-not-exist.desktop,applications:org.kde.konsole.desktop');
        if (edge === 'top') {
            w.writeConfig('iconSize', 24);
            w.writeConfig('zoomPercent', 0);
            w.writeConfig('showPreviews', false);
        }
    });
" >/dev/null

bottom_id=$(dock_applet_id bottom)
left_id=$(dock_applet_id left)
top_id=$(dock_applet_id top)
for id in "$bottom_id" "$left_id" "$top_id"; do
    wait_apps "$id" "System Settings | Konsole"
done
sleep 1

windows=$(dock_windows)
echo "    dock windows: $windows"
b=$(dock_len bottom)
l=$(dock_len left)
t=$(dock_len top)
# Same settings on the bottom and left; the top dock has 24px icons instead of 29.
# (Absolute sizes depend on the Plasma style and fonts, so compare docks with each other.)
[[ "$b" -gt 0 && "$b" == "$l" ]] || fail "bottom ($b) and left ($l) docks should be the same length"
[[ $((b - t)) -eq 10 ]] || fail "bottom dock ($b) should be 10 px longer than the top dock ($t)"
# What Plasma reports must match what is on screen (the same offset for every dock).
reported=$(shell "var o = []; panels().forEach(function (p) { o.push(p.location + '=' + p.length); }); print(o.join(' '));")
rb=$(grep -oP 'bottom=\K[0-9]+' <<<"$reported" || echo 0)
rt=$(grep -oP 'top=\K[0-9]+' <<<"$reported" || echo 0)
[[ $((b - rb)) -eq $((t - rt)) ]] || fail "reported lengths ($reported) disagree with the windows ($windows)"

if [[ -n "$screenshot" ]] && command -v spectacle >/dev/null 2>&1; then
    spectacle -b -n -f -o "$screenshot" >/dev/null 2>&1 && echo "    screenshot: $screenshot"
fi

# ------------------------------------------------------------------- 4. apps opening and closing

step "Apps opening and closing (bottom dock)"
base=$(dock_len bottom)
pitch=47 # one 29px icon plus one 18px gap

konsole --separate >"$work/konsole.log" 2>&1 &
konsole_pid=$!
wait_for "Konsole's window" 40 has_window Konsole || fail "Konsole didn't open"
sleep 1
wait_apps "$bottom_id" "System Settings | Konsole"
wait_bottom "$base" "pinned app opened, nothing added"

"$qml_bin" "$ROOT/tests/TestWindow.qml" >"$work/testwindow.log" 2>&1 &
testwin_pid=$!
wait_for "the test window" 40 has_window "Glossy Dock test window" || fail "test window didn't open"
wait_bottom $((base + pitch)) "unpinned app opened, one slot added"

kill "$testwin_pid" 2>/dev/null || true
wait_bottom "$base" "unpinned app closed, slot removed"

shell "
    panels().forEach(function (p) {
        if (p.location !== 'bottom') { return; }
        p.widgets('$WIDGET_ID').forEach(function (w) {
            w.currentConfigGroup = ['General'];
            w.writeConfig('launchers', 'applications:systemsettings.desktop');
        });
    });
" >/dev/null
wait_apps "$bottom_id" "System Settings | +Konsole"
wait_bottom "$base" "open app unpinned, it stays as an open app"

kill "$konsole_pid" 2>/dev/null || true
wait_apps "$bottom_id" "System Settings"
wait_bottom $((base - pitch)) "that app closed, slot removed"

# ------------------------------------------------------------------- 5. settings page

step "Settings page"
if timeout 30 "$qml_bin" "$ROOT/tests/ConfigPageTest.qml" >"$work/config.log" 2>&1 \
    && grep -q "PASS: settings page" "$work/config.log" \
    && ! grep -E "ConfigGeneral\.qml.*(Error|error|undefined|Cannot)" "$work/config.log"; then
    echo "    settings page OK"
else
    fail "settings page:"
    sed 's/^/    /' "$work/config.log" | tail -20
fi

# ------------------------------------------------------------------- 6. uninstall.sh

# Removing the widget makes Plasma log about it vanishing; judge errors up to this point.
log_lines_before_uninstall=$(wc -l <"$work/plasma.log")

step "uninstall.sh --remove-docks"
"$ROOT/uninstall.sh" --remove-docks >"$work/uninstall.log" 2>&1 || { cat "$work/uninstall.log"; fail "uninstall.sh"; }
sleep 2
got=$(panel_summary)
if [[ -z "$got" ]]; then
    echo "    dock panels removed"
else
    fail "after uninstall, panels are [$got], expected none"
fi
leftover=0
for spec in "Plasma/Applet:$WIDGET_ID" "Plasma/LayoutTemplate:$TEMPLATE_ID" "Plasma/Theme:glossy-glass"; do
    if kpackagetool6 -t "${spec%%:*}" -s "${spec#*:}" >/dev/null 2>&1; then
        fail "${spec#*:} is still installed"
        leftover=1
    fi
done
[[ $leftover -eq 0 ]] && echo "    packages removed"

# ------------------------------------------------------------------- errors

# Any QML error or warning from the dock's files fails the test.
if head -n "$log_lines_before_uninstall" "$work/plasma.log" | grep -nE "$WIDGET_ID|glossydock" | grep -v "glossydock-slots:" \
    | grep -iE "error|warning|TypeError|ReferenceError|cannot|failed|not installed|undefined" >"$work/errors.txt"; then
    fail "Plasma reported problems with the dock:"
    sed 's/^/    /' "$work/errors.txt" | head -20
fi

if [[ $failed -ne 0 ]]; then
    KEEP_SMOKE_LOGS=1
    exit 1
fi
echo "Smoke test passed."
