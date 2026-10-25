/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

// Body of the hover popup: one card per window of the hovered app, with a live thumbnail
// (Wayland), its title and a close button. Hovering a card peeks that window; clicking it
// raises the window; middle click or the close button closes it.

import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.kirigami as Kirigami
import org.kde.kwindowsystem

Item {
    id: previews

    required property var dock

    readonly property int cardWidth: Kirigami.Units.gridUnit * 12
    readonly property int thumbHeight: Math.round(cardWidth * 9 / 16)
    readonly property int spacing: Kirigami.Units.smallSpacing
    readonly property int count: dock.previewWindows.length
    // Never wider than most of the screen; with many windows the row scrolls.
    readonly property int maxWidth: Math.max(cardWidth, Math.round((Screen.width > 0 ? Screen.width : 1920) * 0.8))

    implicitWidth: Math.min(maxWidth, count * cardWidth + Math.max(0, count - 1) * spacing) + spacing * 2
    implicitHeight: cardHeight + spacing * 2
    readonly property int cardHeight: thumbHeight + Kirigami.Units.gridUnit * 2 + spacing * 3

    ListView {
        anchors.fill: parent
        anchors.margins: previews.spacing
        orientation: ListView.Horizontal
        spacing: previews.spacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: previews.dock.previewWindows

        delegate: Item {
            id: card
            required property var modelData

            width: previews.cardWidth
            height: previews.cardHeight

            PlasmaExtras.Highlight {
                anchors.fill: parent
                visible: cardArea.containsMouse
                pressed: cardArea.containsPress
                hovered: true
            }

            MouseArea {
                id: cardArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                onEntered: previews.dock.highlight(card.modelData.uuid ? [card.modelData.uuid] : [])
                onExited: previews.dock.highlight([])
                onClicked: mouse => {
                    if (mouse.button === Qt.MiddleButton) {
                        previews.dock.closeWindowRow(card.modelData.row)
                        return
                    }
                    previews.dock.activateWindowRow(card.modelData.row)
                    previews.dock.closePreview()
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: previews.spacing
                spacing: previews.spacing

                RowLayout {
                    Layout.fillWidth: true
                    spacing: previews.spacing

                    PlasmaComponents3.Label {
                        Layout.fillWidth: true
                        text: card.modelData.title
                        elide: Text.ElideRight
                        font.weight: card.modelData.active ? Font.DemiBold : Font.Normal
                        opacity: card.modelData.minimized ? 0.6 : 1
                    }

                    PlasmaComponents3.ToolButton {
                        icon.name: "window-close"
                        display: PlasmaComponents3.AbstractButton.IconOnly
                        text: i18n("Close")
                        onClicked: previews.dock.closeWindowRow(card.modelData.row)
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: previews.thumbHeight

                    Loader {
                        id: thumbLoader
                        anchors.fill: parent
                        // Minimized windows can't be captured, and X11 has no stream.
                        active: KWindowSystem.isPlatformWayland && previews.dock.previewShown
                            && !card.modelData.minimized && card.modelData.uuid.length > 0
                        asynchronous: true
                        source: "PipeWireThumbnail.qml"
                        onLoaded: item.uuid = Qt.binding(() => card.modelData.uuid)
                    }

                    Kirigami.Icon {
                        anchors.centerIn: parent
                        width: Kirigami.Units.iconSizes.huge
                        height: width
                        source: previews.dock.previewIcon
                        visible: !(thumbLoader.item && thumbLoader.item.hasThumbnail)
                    }
                }
            }
        }
    }
}
