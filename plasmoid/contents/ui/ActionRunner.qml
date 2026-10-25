/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

// Reads and starts an app's own actions ("Desktop Action" entries in its .desktop file)
// through code/actions.sh. Kept in its own file so a system without the Plasma5Support
// QML module only loses app actions in the menu.

import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: runner

    // Emitted once per list() call with [{ id, name, icon }], possibly empty.
    signal listed(string url, var actions)

    readonly property string script: decodeURIComponent(
        Qt.resolvedUrl("../code/actions.sh").toString().replace(/^file:\/\//, ""))
    property var pending: ({})

    function quote(text) {
        return "'" + String(text).replace(/'/g, "'\\''") + "'"
    }

    function list(url) {
        const cmd = "sh " + quote(script) + " list " + quote(url)
        if (pending[cmd] !== undefined) {
            return
        }
        pending[cmd] = url
        exec.connectSource(cmd)
    }

    function run(url, actionId) {
        exec.connectSource("sh " + quote(script) + " run " + quote(url) + " " + quote(actionId))
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        onNewData: (source, data) => {
            disconnectSource(source)
            const url = runner.pending[source]
            if (url === undefined) {
                return
            }
            delete runner.pending[source]
            const actions = []
            for (const line of String(data.stdout || "").split("\n")) {
                const parts = line.split("\t")
                if (parts.length >= 2 && parts[0].length > 0 && parts[1].length > 0) {
                    actions.push({ id: parts[0], name: parts[1], icon: parts[2] || "" })
                }
            }
            runner.listed(url, actions)
        }
    }
}
