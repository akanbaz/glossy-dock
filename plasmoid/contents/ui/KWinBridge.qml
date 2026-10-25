/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// KWin D-Bus calls, in their own file so a system without the Plasma D-Bus QML module
// only loses peek and "Show all windows" instead of the whole dock.

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
