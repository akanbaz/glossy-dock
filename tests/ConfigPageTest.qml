/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Loads the settings page outside Plasma and checks its pin logic.
// Run with Qt's qml tool inside a Wayland session (scripts/smoke-test.sh does this);
// prints PASS and exits 0, or prints FAIL lines and exits 1.

import QtQuick

Item {
    id: harness

    // Plasma provides i18n() at runtime; a minimal stand-in for the test.
    function i18n(text, ...args) {
        let s = String(text)
        args.forEach((a, i) => { s = s.replace("%" + (i + 1), a) })
        return s
    }

    property int failures: 0

    function expect(what, got, want) {
        if (got !== want) {
            console.error("FAIL:", what, "- got", JSON.stringify(got), "expected", JSON.stringify(want))
            failures++
        }
    }

    Loader {
        id: loader
        source: Qt.resolvedUrl("../plasmoid/contents/ui/ConfigGeneral.qml")
    }

    Timer {
        interval: 2000
        running: true
        onTriggered: {
            if (loader.status !== Loader.Ready) {
                console.error("FAIL: settings page did not load:", loader.sourceComponent ? "" : loader.source)
                Qt.exit(1)
                return
            }
            const page = loader.item

            page.cfg_launchers = "applications:systemsettings.desktop, applications:does-not-exist.desktop,,"
            harness.expect("pins are trimmed and empty entries dropped", page.pinList.join(","),
                           "applications:systemsettings.desktop,applications:does-not-exist.desktop")

            page.movePin(0, 1)
            harness.expect("move down", page.cfg_launchers,
                           "applications:does-not-exist.desktop,applications:systemsettings.desktop")
            page.removePin(0)
            harness.expect("remove", page.cfg_launchers, "applications:systemsettings.desktop")

            harness.expect("bare id", page.normalizeLauncher(" org.kde.dolphin "), "applications:org.kde.dolphin.desktop")
            harness.expect("desktop file name", page.normalizeLauncher("org.kde.dolphin.desktop"), "applications:org.kde.dolphin.desktop")
            harness.expect("preferred url", page.normalizeLauncher("preferred://browser"), "preferred://browser")
            harness.expect("path", page.normalizeLauncher("/opt/app/app.desktop"), "file:///opt/app/app.desktop")
            harness.expect("empty", page.normalizeLauncher("   "), "")
            harness.expect("pretty name", page.prettyLauncher("applications:org.kde.dolphin.desktop"), "org.kde.dolphin")

            page.cfg_iconSize = 0
            harness.expect("icon size 0 means automatic", page.cfg_iconSize, 0)

            // App names: one choice drives two settings.
            page.setNameMode(2)
            harness.expect("names always: labels on", page.cfg_showLabels, true)
            harness.expect("names always: hover off", page.cfg_showNameTooltips, false)
            harness.expect("names always: mode", page.nameMode, 2)
            page.setNameMode(1)
            harness.expect("names on hover: labels off", page.cfg_showLabels, false)
            harness.expect("names on hover: hover on", page.cfg_showNameTooltips, true)
            harness.expect("names on hover: mode", page.nameMode, 1)
            page.setNameMode(0)
            harness.expect("names off", [page.cfg_showLabels, page.cfg_showNameTooltips, page.nameMode].join(), "false,false,0")

            // Controls must keep following their setting after being clicked: a click
            // overwrites a control's binding, then "Defaults" or another dock changes the
            // setting. (A click sets the value, then emits the signal; done the same here.)
            const c = page.controls
            page.cfg_iconSize = 0
            c.autoIconSize.checked = false; c.autoIconSize.toggled()
            harness.expect("untick Fit the panel: fixed size", page.cfg_iconSize > 0, true)
            page.cfg_iconSize = 0
            harness.expect("Fit the panel follows a later change", c.autoIconSize.checked, true)
            c.iconSize.value = 40; c.iconSize.valueModified()
            harness.expect("icon size typed", page.cfg_iconSize, 40)
            page.cfg_iconSize = 20
            harness.expect("icon size box follows a later change", c.iconSize.value, 20)
            harness.expect("Fit the panel unticked by a fixed size", c.autoIconSize.checked, false)

            page.cfg_dockHeight = 0
            c.fixedHeight.checked = true; c.fixedHeight.toggled()
            harness.expect("tick Set the panel height", page.cfg_dockHeight > 0, true)
            page.cfg_dockHeight = 0
            harness.expect("panel height box follows a later change", c.fixedHeight.checked, false)
            c.dockHeight.value = 60; c.dockHeight.valueModified()
            page.cfg_dockHeight = 50
            harness.expect("dock height follows a later change", c.dockHeight.value, 50)

            c.namesAlways.checked = true; c.namesAlways.toggled()
            harness.expect("pick names under icons", page.nameMode, 2)
            page.cfg_showLabels = false
            harness.expect("names radio follows a later change (always)", c.namesAlways.checked, false)
            harness.expect("names radio follows a later change (off)", c.namesOff.checked, true)

            if (harness.failures === 0) {
                console.log("PASS: settings page")
            }
            Qt.exit(harness.failures === 0 ? 0 : 1)
        }
    }
}
