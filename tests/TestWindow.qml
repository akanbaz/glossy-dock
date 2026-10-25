/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// A plain window with no .desktop file: the smoke test opens it as an "unpinned open app".

import QtQuick
import QtQuick.Window

Window {
    visible: true
    width: 320
    height: 200
    title: "Glossy Dock test window"
    color: "#336699"
}
