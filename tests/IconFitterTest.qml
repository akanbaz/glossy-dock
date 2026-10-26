/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Checks IconFitter against image files with known artwork sizes (tests/icons/): a full
// 32px square, a 24px square centered in 32px (75%), a 16x8 bar (50%) and an empty icon.
// Prints PASS and exits 0, or FAIL lines and exits 1. Needs a display (Wayland or X11).

import QtQuick
import QtQuick.Window

Window {
    id: win
    width: 200
    height: 120
    visible: true
    color: "transparent"

    property int failures: 0
    property var results: ({})
    property var pending: ["full", "inset", "bar", "empty"]

    function expect(what, got, want) {
        if (Math.abs(got - want) > 0.02) {
            console.error("FAIL:", what, "- fill", got.toFixed(3), "expected", want.toFixed(3))
            failures++
        }
    }

    // Image files with known artwork: a full 32px square, a 24px square inset by 4px, a 16x8
    // bar and an empty (fully transparent) icon.
    Component.onCompleted: Qt.callLater(() => {
        for (const name of ["full", "inset", "bar", "empty"]) {
            win.fitter.measure(name, Qt.resolvedUrl("icons/" + name + ".png"), 32)
        }
    })

    Loader {
        id: loader
        source: Qt.resolvedUrl("../plasmoid/contents/ui/IconFitter.qml")
    }
    readonly property var fitter: loader.item

    Connections {
        target: win.fitter
        function onMeasured(key, fill) {
            win.results[key] = fill
            win.pending = win.pending.filter(k => k !== key)
            if (win.pending.length === 0) {
                win.expect("full square", win.results.full, 1.0)
                win.expect("24px square in 32px", win.results.inset, 0.75)
                win.expect("16x8 bar in 32px", win.results.bar, 0.5)
                win.expect("empty icon is left alone", win.results.empty, 1.0)
                if (win.failures === 0) {
                    console.log("PASS: icon fitter")
                }
                Qt.exit(win.failures === 0 ? 0 : 1)
            }
        }
    }

    Timer {
        interval: 10000
        running: true
        onTriggered: {
            console.error("FAIL: icon fitter timed out; still waiting for", win.pending.join(", "))
            Qt.exit(1)
        }
    }
}
