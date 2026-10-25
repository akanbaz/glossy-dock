/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

// Right-click menu. A Plasma popup window rather than a Qt menu: Plasma anchors it to the
// clicked slot just off the panel, it keeps working on auto-hiding panels, and it closes
// on Esc or a click elsewhere.

import QtQuick
import QtQuick.Layouts
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami

PlasmaCore.PopupPlasmaWindow {
    id: menu

    // [{ text, icon, run }] or { separator: true }
    property var entries: []
    property real contentWidth: Kirigami.Units.gridUnit * 10
    property real contentHeight: 0
    readonly property real rowHeight: Math.round(Kirigami.Units.gridUnit * 1.6)
    readonly property real separatorHeight: Kirigami.Units.smallSpacing * 2 + 1

    function popup(parentItem, newEntries) {
        visible = false
        let textWidth = 0
        for (const e of newEntries) {
            metrics.text = e.text
            textWidth = Math.max(textWidth, metrics.advanceWidth)
        }
        contentWidth = Math.max(Kirigami.Units.gridUnit * 10,
                                Math.ceil(textWidth) + Kirigami.Units.iconSizes.small
                                + Kirigami.Units.smallSpacing * 2 + Kirigami.Units.largeSpacing * 2 + 2)
        contentHeight = newEntries.reduce((h, e) => h + (e.separator ? separatorHeight : rowHeight), 0)
        entries = newEntries
        list.currentIndex = -1
        visualParent = parentItem
        visible = true
        requestActivate()
    }

    margin: 6
    floating: true
    animated: true
    hideOnWindowDeactivate: true
    removeBorderStrategy: PlasmaCore.PopupPlasmaWindow.Never
    // The window does not size itself from its content; size it to the rows exactly.
    width: contentWidth + leftPadding + rightPadding
    height: contentHeight + topPadding + bottomPadding

    TextMetrics {
        id: metrics
        font: Kirigami.Theme.defaultFont
    }

    mainItem: FocusScope {
        width: menu.contentWidth
        height: menu.contentHeight
        implicitWidth: menu.contentWidth
        implicitHeight: menu.contentHeight
        focus: true

        Keys.onEscapePressed: menu.visible = false

        ListView {
            id: list
            anchors.fill: parent
            interactive: false
            focus: true
            highlightFollowsCurrentItem: false
            model: menu.entries

            function trigger(entry) {
                menu.visible = false
                if (entry && entry.run) {
                    entry.run()
                }
            }

            function step(delta) {
                if (count === 0) {
                    return
                }
                let i = currentIndex
                for (let n = 0; n < count; n++) {
                    i = (i + delta + count) % count
                    if (!menu.entries[i].separator) {
                        currentIndex = i
                        return
                    }
                }
            }

            Keys.onReturnPressed: trigger(menu.entries[currentIndex])
            Keys.onEnterPressed: trigger(menu.entries[currentIndex])
            Keys.onUpPressed: step(-1)
            Keys.onDownPressed: step(1)

            delegate: Item {
                id: entry
                required property var modelData
                required property int index

                width: ListView.view.width
                height: modelData.separator ? menu.separatorHeight : menu.rowHeight

                Rectangle {
                    visible: entry.modelData.separator
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Kirigami.Units.smallSpacing
                    anchors.rightMargin: Kirigami.Units.smallSpacing
                    height: 1
                    color: Kirigami.Theme.textColor
                    opacity: 0.15
                }

                PlasmaExtras.Highlight {
                    anchors.fill: parent
                    visible: !entry.modelData.separator && (entryArea.containsMouse || list.currentIndex === entry.index)
                    hovered: true
                    pressed: entryArea.containsPress
                }

                RowLayout {
                    visible: !entry.modelData.separator
                    anchors.fill: parent
                    anchors.leftMargin: Kirigami.Units.largeSpacing
                    anchors.rightMargin: Kirigami.Units.largeSpacing
                    spacing: Kirigami.Units.smallSpacing * 2

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        Layout.preferredHeight: Kirigami.Units.iconSizes.small
                        source: entry.modelData.icon
                    }

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: entry.modelData.text
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: entryArea
                    anchors.fill: parent
                    enabled: !entry.modelData.separator
                    hoverEnabled: true
                    onEntered: list.currentIndex = entry.index
                    onClicked: list.trigger(entry.modelData)
                }
            }
        }
    }
}
