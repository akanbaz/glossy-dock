#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
# SPDX-License-Identifier: GPL-2.0-or-later
#
# End-to-end check in a throwaway Plasma session: a virtual (off-screen) KWin, a private
# D-Bus session and a temporary HOME, so nothing touches the running desktop or your
# settings. Everything is checked against what is really on screen (window geometry from
# KWin), and through changes after start-up, not just the first layout:
#
#   1. on two screens, install.sh --add-dock adds one dock per screen, and running it again
#      adds no more
#   2. the "Glossy Dock" panel template adds a dock, then another on a free edge
#   3. docks on the bottom, left and top edges show exactly the installed pins (a pin
#      whose app doesn't exist is skipped) and their windows agree with each other
#   4. opening a pinned app adds nothing; opening an unpinned app adds one slot; closing
#      it, unpinning an open app and closing that app each change the width by exactly
#      one icon and one gap
#   5. the dock height setting resizes the panel; names under the icons lengthen a
#      vertical dock by the same amount per icon and leave a horizontal dock's length alone
#   6. the settings page loads and its pin and name logic holds
#   7. with "use these settings on all docks", a dock's settings reach the others, while
#      each dock keeps its own pins; the dock notices widgets joining its panel; Configure,
#      Edit Panel and the optional features are available
#   (GPU only) the right-click menu and window preview open attached to the dock (measured),
#   "Show open apps" adds and removes slots, "Even out icon sizes" changes drawn sizes, and
#   a dock moved to another edge keeps its length
#   8. uninstall.sh --remove-docks removes the dock panels and the packages
#
# Any error or warning that Plasma logs from the dock fails the test.
#
# Usage: scripts/smoke-test.sh [screenshot.png]
# With SMOKE_LOG_DIR set, a failing run copies its logs there (CI uploads them).
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
    # Any failure, including an unexpected abort, keeps the logs.
    [[ $status -ne 0 ]] && KEEP_SMOKE_LOGS=1
    [[ -n "$plasma_pid" ]] && kill "$plasma_pid" 2>/dev/null
    [[ -n "$kwin_pid" ]] && kill "$kwin_pid" 2>/dev/null
    sleep 1
    # shellcheck disable=SC2046
    kill $(session_pids) 2>/dev/null
    sleep 0.5
    # shellcheck disable=SC2046
    kill -9 $(session_pids) 2>/dev/null
    if [[ -n "${KEEP_SMOKE_LOGS:-}" && -n "${SMOKE_LOG_DIR:-}" ]]; then
        mkdir -p "$SMOKE_LOG_DIR" && cp "$work"/*.log "$work"/*.txt "$SMOKE_LOG_DIR"/ 2>/dev/null
        echo "logs copied to $SMOKE_LOG_DIR"
        rm -rf "$work"
    elif [[ -n "${KEEP_SMOKE_LOGS:-}" ]]; then
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

# Real on-screen thickness of the dock window on an edge.
dock_thickness() {
    kwin_eval "
        var t = 0;
        workspace.windowList().forEach(function (w) {
            if (!w.dock) { return; }
            var g = w.frameGeometry, edge;
            if (g.width > g.height) { edge = g.y > 540 ? 'bottom' : 'top'; } else { edge = g.x < 960 ? 'left' : 'right'; }
            if (edge === '$1') { t = Math.round(g.width > g.height ? g.height : g.width); }
        });
        return t;"
}

# Change one setting of the dock on an edge.
set_dock() {
    shell "
        panels().forEach(function (p) {
            if (p.location !== '$1') { return; }
            p.widgets('$WIDGET_ID').forEach(function (w) {
                w.currentConfigGroup = ['General'];
                w.writeConfig('$2', $3);
            });
        });
    " >/dev/null
}

wait_value() {
    local what=$1 want=$2 got=""
    shift 2
    for ((i = 0; i < 60; i++)); do
        got=$("$@")
        [[ "$got" == "$want" ]] && { echo "    $what: $got"; return 0; }
        sleep 0.25
    done
    fail "$what: got $got, expected $want"
    return 0
}

# Geometry "x y w h" of the bottom dock window on the first screen.
bottom_geom() {
    kwin_eval '
        var r = "";
        workspace.windowList().forEach(function (w) {
            var g = w.frameGeometry;
            if (w.dock && g.width > g.height && g.y > 540 && g.x < 1920) { r = [g.x, g.y, g.width, g.height].map(Math.round).join(" "); }
        });
        return r;'
}

# Plasma's own popups (menu, tooltip): "x y w h" of the first one found.
plasma_popup() {
    kwin_eval '
        var r = "";
        workspace.windowList().forEach(function (w) {
            if (w.dock || w.desktop || r) { return; }
            if (w.resourceClass === "org.kde.plasmashell" || w.resourceClass === "plasmashell") {
                var g = w.frameGeometry;
                if (g.width < 1900) { r = [g.x, g.y, g.width, g.height].map(Math.round).join(" "); }
            }
        });
        return r;'
}

# Ask a dock to open its menu / preview, set hover, or close popups (debugLog test hook).
debug_action() { set_dock "$1" debugAction "'$2#$RANDOM'"; }

# A dock's latest layout or drawn-size log line.
dock_layout() { grep -oP "glossydock-layout: $1 \\K.*" "$work/plasma.log" | tail -1 || true; }
dock_drawn() { grep -oP "glossydock-drawn: $1 \\K.*" "$work/plasma.log" | tail -1 || true; }

wait_log() {
    local what=$1 want=$2
    shift 2
    for ((i = 0; i < 60; i++)); do
        [[ "$("$@")" == *"$want"* ]] && { echo "    $what"; return 0; }
        sleep 0.25
    done
    fail "$what: log shows [$("$@")], expected it to contain [$want]"
    return 0
}

# A popup is attached when its bottom edge is within 12px above the dock's glass (the dock
# window starts 8px above the glass: the floating margin) and it spans slot $3's centre.
check_attached() {
    local what=$1 popup=$2 slot=$3 px py pw ph bx by bw bh
    read -r px py pw ph <<<"$popup"
    read -r bx by bw bh <<<"$(bottom_geom)"
    if [[ -z "$px" || -z "$bx" ]]; then
        fail "$what: no popup window found"
        return 0
    fi
    local glass=$((by + 8)) bottom=$((py + ph)) centre=$((bx + 8 + 10 + slot * 47 + 14))
    if (( bottom <= glass + 2 && bottom >= glass - 12 && px <= centre && centre <= px + pw && ph < 500 && pw < 450 )); then
        echo "    $what: ${pw}x${ph}, bottom edge $((glass - bottom)) px above the glass, over icon $((slot + 1))"
    else
        fail "$what: popup at [$popup] isn't attached over icon $((slot + 1)) of the dock at [$bx $by $bw $bh]"
    fi
    return 0
}

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

# Stop at once (with KWin's last words) if the compositor has gone away.
require_kwin() {
    if ! kill -0 "$kwin_pid" 2>/dev/null; then
        echo "FAIL: KWin is no longer running ($1). Last lines of its log:"
        tail -40 "$work/kwin.log" | sed 's/^/    /'
        exit 1
    fi
}

# ------------------------------------------------------------------- session

step "Starting a virtual KWin"
# KWin's off-screen backend needs a GPU render device. Without one (e.g. GitHub's CI
# containers) KWin can't draw: panels get their first layout on screen, but later changes
# never reach it (Plasma waits for frames that never come), and KWin quits as soon as an
# app window has to be drawn. (6.8 has no CPU renderer for this backend, and Xvfb lacks the
# DRI3 that nesting needs.) So the steps that change docks after start-up or open app
# windows are skipped there.
has_gpu=1
compgen -G "/dev/dri/renderD*" >/dev/null || has_gpu=0
[[ $has_gpu -eq 1 ]] || echo "    no GPU render device: steps that change docks after start-up or open app windows will be skipped"
kwin_wayland --virtual --no-lockscreen --no-global-shortcuts --socket "$WAYLAND_DISPLAY" \
    --width 1920 --height 1080 --output-count 2 >"$work/kwin.log" 2>&1 &
kwin_pid=$!
wait_for "KWin" 60 test -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" || { cat "$work/kwin.log"; exit 1; }

step "Installing packages into the temporary home, with the Glossy Glass style"
"$ROOT/install.sh" --apply-style >"$work/install.log" 2>&1 || { cat "$work/install.log"; exit 1; }
style=$(kreadconfig6 --file plasmarc --group Theme --key name 2>/dev/null || true)
[[ "$style" == "glossy-glass" ]] || fail "install.sh --apply-style didn't select Glossy Glass (Plasma style is '$style')"

# A test app whose icon has known built-in padding (artwork fills 75% of the image).
mkdir -p "$XDG_DATA_HOME/applications"
cat >"$XDG_DATA_HOME/applications/glossy-test-padded.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Padded Test App
Exec=true
Icon=$ROOT/tests/icons/inset.png
DESKTOP

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
if [[ "$got" == "bottom:1 bottom:1" ]]; then
    echo "    one dock on the bottom of each of the 2 screens, not added twice"
else
    fail "after --add-dock twice on 2 screens, panels are [$got], expected [bottom:1 bottom:1]"
fi

# ------------------------------------------------------------------- 2. panel template

step "Add Panel > Glossy Dock template"
shell "panels().forEach(function (p) { p.remove(); });" >/dev/null
shell "loadTemplate('$TEMPLATE_ID'); loadTemplate('$TEMPLATE_ID'); panels().forEach(function (p) { p.screen = 0; });" >/dev/null
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
        panel.screen = 0;
        panel.location = edge;
        panel.height = 42;
        panel.floating = true;
        panel.lengthMode = 'fit';
        panel.alignment = 'center';
        panel.hiding = 'none';
        var w = panel.addWidget('$WIDGET_ID');
        w.currentConfigGroup = ['General'];
        // These docks get different settings on purpose; sharing is tested later.
        w.writeConfig('syncAllDocks', false);
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

# Optional, for looking at by eye. (On GitHub's software-rendered KWin the screenshot
# request crashes the compositor, so CI doesn't ask for one.)
# ------------------------------------------------------------------- 5. height and names

if [[ $has_gpu -eq 0 ]]; then
    echo "skip: dock height and app names (changes after start-up don't reach the screen without a GPU)"
else
step "Dock height and app names"
top_thick=$(dock_thickness top)
top_len=$(dock_len top)
set_dock top dockHeight 60
wait_value "top dock thickness after setting the height to 60 (was $top_thick)" $((top_thick + 18)) dock_thickness top
# With Glossy Glass the ends keep the same small inset at any height.
wait_value "top dock length after the height change (unchanged)" "$top_len" dock_len top

left_len=$(dock_len left)
set_dock top showLabels true
set_dock left showLabels true
sleep 2
wait_value "top dock length with names (horizontal: unchanged)" "$top_len" dock_len top
left_with=$(dock_len left)
grown=$((left_with - left_len))
if (( grown > 0 && grown % 2 == 0 )); then
    echo "    left dock length with names: $left_len -> $left_with px (+$((grown / 2)) per icon)"
else
    fail "left (vertical) dock should grow by the same amount for each of its 2 icons: $left_len -> $left_with"
fi
wait_apps "$left_id" "System Settings | Konsole"
fi # has_gpu

if [[ -n "$screenshot" ]] && command -v spectacle >/dev/null 2>&1; then
    spectacle -b -n -f -o "$screenshot" >/dev/null 2>&1 && echo "    screenshot: $screenshot"
fi

# ------------------------------------------------------------------- 4. apps opening and closing

if [[ $has_gpu -eq 0 ]]; then
    echo "skip: apps opening and closing, and the settings page (they need app windows, which need a GPU)"
else
step "Apps opening and closing (bottom dock)"
base=$(dock_len bottom)
pitch=47 # one 29px icon plus one 18px gap

require_kwin "before opening apps"
konsole --separate >"$work/konsole.log" 2>&1 &
konsole_pid=$!
sleep 2
require_kwin "after starting Konsole"
wait_for "Konsole's window" 40 has_window Konsole || fail "Konsole didn't open"
sleep 1
wait_apps "$bottom_id" "System Settings | Konsole"
wait_bottom "$base" "pinned app opened, nothing added"

"$qml_bin" "$ROOT/tests/TestWindow.qml" >"$work/testwindow.log" 2>&1 &
testwin_pid=$!
sleep 2
require_kwin "after opening the test window"
wait_for "the test window" 40 has_window "Glossy Dock test window" || fail "test window didn't open"
wait_bottom $((base + pitch)) "unpinned app opened, one slot added"

set_dock bottom showOpenApps false
wait_bottom "$base" "Show open apps off: slot removed"
set_dock bottom showOpenApps true
wait_bottom $((base + pitch)) "Show open apps on: slot back"

debug_action bottom "menu:0"
sleep 1.5
check_attached "right-click menu" "$(plasma_popup)" 0
debug_action bottom close
sleep 1
debug_action bottom "preview:1"
sleep 2
check_attached "window preview of Konsole" "$(plasma_popup)" 1
debug_action bottom close
sleep 1

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

one_icon=$(dock_len bottom)
shell "panels().forEach(function (p) { if (p.location === 'bottom') { p.location = 'right'; } });" >/dev/null
wait_value "dock moved to the right edge: same length" "$one_icon" dock_len right
shell "panels().forEach(function (p) { if (p.location === 'right') { p.location = 'bottom'; } });" >/dev/null
wait_value "and back to the bottom: same length" "$one_icon" dock_len bottom

# ------------------------------------------------------------------- even icon sizes

step "Even icon sizes"
if timeout 30 "$qml_bin" "$ROOT/tests/IconFitterTest.qml" >"$work/fitter.log" 2>&1 && grep -q "PASS: icon fitter" "$work/fitter.log"; then
    echo "    icon fitter measures known artwork correctly"
else
    fail "icon fitter:"
    sed 's/^/    /' "$work/fitter.log" | tail -10
fi
# The top dock measures its icons; the padded test app must come out near 75%.
set_dock top launchers "'applications:systemsettings.desktop,applications:glossy-test-padded.desktop'"
fill_of() { grep -oP "glossydock-fit: $top_id $1 \\K[0-9.]+" "$work/plasma.log" | tail -1 || true; }
for ((i = 0; i < 60; i++)); do
    [[ -n "$(fill_of glossy-test-padded)" && -n "$(fill_of systemsettings)" ]] && break
    sleep 0.25
done
padded=$(fill_of glossy-test-padded)
settings=$(fill_of systemsettings)
echo "    measured artwork fill: padded test app ${padded:-?}, System Settings ${settings:-?}"
awk -v p="${padded:-0}" 'BEGIN { exit !(p > 0.70 && p < 0.80) }' || fail "padded test app should measure about 0.75, got ${padded:-nothing}"
awk -v s="${settings:-0}" 'BEGIN { exit !(s > 0.85) }' || fail "System Settings should measure close to full, got ${settings:-nothing}"
# 24px icons: the padded app is drawn at 24 x 1.3 (the cap) = 31px; 24px with the option off.
wait_log "padded test app drawn at 31 px" "Padded Test App=31" dock_drawn "$top_id"
set_dock top evenIconSizes false
wait_log "with Even out icon sizes off: 24 px" "Padded Test App=24" dock_drawn "$top_id"
set_dock top evenIconSizes true
wait_log "and back on: 31 px" "Padded Test App=31" dock_drawn "$top_id"

# ------------------------------------------------------------------- 6. settings page

step "Settings page"
if timeout 30 "$qml_bin" "$ROOT/tests/ConfigPageTest.qml" >"$work/config.log" 2>&1 \
    && grep -q "PASS: settings page" "$work/config.log" \
    && ! grep -E "ConfigGeneral\.qml.*(Error|error|undefined|Cannot)" "$work/config.log"; then
    echo "    settings page OK"
else
    fail "settings page:"
    sed 's/^/    /' "$work/config.log" | tail -20
fi
fi # has_gpu

# ------------------------------------------------------------------- 8. uninstall.sh

# ------------------------------------------------------------------- 7. shared settings

step "Layout reactions"
wait_log "Configure, Edit Panel, D-Bus and app actions are available" "configure=true editPanel=true dbus=true actions=true" dock_layout "$top_id"
shell "panels().forEach(function (p) { if (p.location === 'top') { p.addWidget('org.kde.plasma.panelspacer'); } });" >/dev/null
wait_log "a widget added next to the dock turns the end-gap compensation off" "alone=false" dock_layout "$top_id"
shell "panels().forEach(function (p) { if (p.location === 'top') { p.widgets('org.kde.plasma.panelspacer').forEach(function (w) { w.remove(); }); } });" >/dev/null
wait_log "and removing it turns it back on" "alone=true" dock_layout "$top_id"

step "Shared settings across docks"
read_setting() {
    shell "
        panels().forEach(function (p) {
            if (p.location !== '$1') { return; }
            p.widgets('$WIDGET_ID').forEach(function (w) { w.currentConfigGroup = ['General']; print(w.readConfig('$2')); });
        });
    "
}
top_pins=$(read_setting top launchers)
left_pins=$(read_setting left launchers)
set_dock bottom syncAllDocks true
wait_value "top dock's icon size after sharing from the bottom dock" "$(read_setting bottom iconSize)" read_setting top iconSize
set_dock bottom iconSize 30
wait_value "top dock's icon size after changing it on the bottom dock" 30 read_setting top iconSize
wait_value "left dock's icon size after changing it on the bottom dock" 30 read_setting left iconSize
[[ "$(read_setting top launchers)" == "$top_pins" && "$(read_setting left launchers)" == "$left_pins" ]] \
    && echo "    each dock kept its own pins" || fail "sharing settings changed a dock's pins"

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
if head -n "$log_lines_before_uninstall" "$work/plasma.log" | grep -nE "$WIDGET_ID|glossydock|Glossy Dock:" \
    | grep -vE "glossydock-(slots|fit|layout|drawn|debug):" \
    | grep -iE "error|warning|TypeError|ReferenceError|cannot|failed|not installed|undefined" >"$work/errors.txt"; then
    fail "Plasma reported problems with the dock:"
    sed 's/^/    /' "$work/errors.txt" | head -20
fi

if [[ $failed -ne 0 ]]; then
    KEEP_SMOKE_LOGS=1
    exit 1
fi
echo "Smoke test passed."
