/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Live window thumbnail through KWin's screencast stream (Wayland only). Loaded on demand,
// so a system without KPipeWire just shows the app icon in previews.

import QtQuick
import org.kde.pipewire as PipeWire
import org.kde.taskmanager as TaskManager

PipeWire.PipeWireSourceItem {
    id: thumbnail

    property string uuid
    readonly property bool hasThumbnail: ready

    nodeId: request.nodeId

    TaskManager.ScreencastingRequest {
        id: request
        uuid: thumbnail.uuid
    }
}
