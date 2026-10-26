/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// D-Bus calls to KWin and Plasma, in their own file so a system without the Plasma D-Bus
// QML module only loses peek, "Show all windows" and the dock height setting instead of
// the whole dock.

import QtQuick
import org.kde.plasma.workspace.dbus as DBus

Item {
    // Hide every window except these while a preview is hovered; [] shows them all again.
    function highlightWindows(ids) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin.HighlightWindow",
            path: "/org/kde/KWin/HighlightWindow",
            iface: "org.kde.KWin.HighlightWindow",
            member: "highlightWindows",
            arguments: [ids.map(id => String(id))],
            signature: "(as)"
        })
    }

    // Run a Plasma desktop script (the same API as Plasma's scripting console).
    function evaluateScript(script) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: [String(script)],
            signature: "(s)"
        })
    }

    // Set the thickness of the panel that holds this applet, through Plasma's scripting API
    // (a widget can't resize its own panel).
    function setPanelThickness(appletId, px) {
        const id = Math.round(Number(appletId))
        const size = Math.round(Number(px))
        if (!(id > 0) || !(size > 0)) {
            return
        }
        DBus.SessionBus.asyncCall({
            service: "org.kde.plasmashell",
            path: "/PlasmaShell",
            iface: "org.kde.PlasmaShell",
            member: "evaluateScript",
            arguments: ["panels().forEach(function (p) { if (p.widgetIds.indexOf(" + id + ") >= 0) { p.height = " + size + "; } });"],
            signature: "(s)"
        })
    }

    // KWin's "Window View" overview, limited to these windows.
    function showWindows(ids) {
        DBus.SessionBus.asyncCall({
            service: "org.kde.KWin.Effect.WindowView1",
            path: "/org/kde/KWin/Effect/WindowView1",
            iface: "org.kde.KWin.Effect.WindowView1",
            member: "activate",
            arguments: [ids.map(id => String(id))],
            signature: "(as)"
        })
    }
}
