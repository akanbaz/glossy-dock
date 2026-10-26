/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCMUtils
import org.kde.taskmanager as TaskManager

KCMUtils.SimpleKCM {
    id: page

    property string cfg_launchers
    property alias cfg_syncAllDocks: syncAllDocks.checked
    property alias cfg_showOpenApps: showOpenApps.checked
    property alias cfg_showPreviews: showPreviews.checked
    property alias cfg_peekWindows: peekWindows.checked
    property bool cfg_showNameTooltips
    property bool cfg_showLabels
    property alias cfg_dimMinimized: dimMinimized.checked
    property int cfg_iconSize
    property alias cfg_evenIconSizes: evenIconSizes.checked
    property int cfg_dockHeight
    property alias cfg_iconSpacing: spacing.value
    property alias cfg_zoomPercent: zoom.value
    property alias cfg_neighbourZoomPercent: neighbourZoom.value

    // App names: 0 = off, 1 = on hover (tooltip), 2 = always, under the icons.
    readonly property int nameMode: cfg_showLabels ? 2 : cfg_showNameTooltips ? 1 : 0
    function setNameMode(mode) {
        cfg_showLabels = mode === 2
        cfg_showNameTooltips = mode === 1
    }

    // Clicking a control overwrites its `checked`/`value` binding, after which it would stop
    // following the setting (e.g. "Defaults", or another dock sharing a new value while this
    // window is open, and Apply would then write the stale value back). Each handler below
    // re-binds its control after acting.

    // For tests: the controls whose bindings must survive interaction.
    readonly property var controls: ({ autoIconSize: autoIconSize, iconSize: iconSize, fixedHeight: fixedHeight,
        dockHeight: dockHeight, namesOff: namesOff, namesHover: namesHover, namesAlways: namesAlways })

    readonly property var pinList: cfg_launchers.split(",").map(s => s.trim()).filter(s => s.length > 0)

    function setPins(list) {
        cfg_launchers = list.join(",")
    }

    function movePin(from, to) {
        const list = pinList.slice()
        const [moved] = list.splice(from, 1)
        list.splice(to, 0, moved)
        setPins(list)
    }

    function removePin(index) {
        const list = pinList.slice()
        list.splice(index, 1)
        setPins(list)
    }

    // Accepts "org.kde.dolphin", "org.kde.dolphin.desktop", "applications:...",
    // "preferred://browser" or a path to a .desktop file.
    function normalizeLauncher(text) {
        let t = text.trim()
        if (t.length === 0) {
            return ""
        }
        if (/^(applications:|preferred:\/\/|file:\/\/)/.test(t)) {
            return t
        }
        if (t.startsWith("/")) {
            return "file://" + t
        }
        if (!t.endsWith(".desktop")) {
            t += ".desktop"
        }
        return "applications:" + t
    }

    function prettyLauncher(url) {
        return url.replace(/^applications:/, "").replace(/^file:\/\//, "").replace(/\.desktop$/, "")
    }

    Kirigami.FormLayout {
        ColumnLayout {
            Kirigami.FormData.label: i18n("Pinned apps:")
            Kirigami.FormData.buddyFor: addField
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing

            Repeater {
                model: page.pinList

                delegate: RowLayout {
                    id: pinRow
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true

                    // Resolves the launcher to its name and icon the same way the dock does.
                    TaskManager.TasksModel {
                        id: resolver
                        launcherList: [pinRow.modelData]
                        separateLaunchers: true
                        launchInPlace: false
                        groupMode: TaskManager.TasksModel.GroupDisabled
                        filterByVirtualDesktop: false
                        filterByActivity: false
                        filterByScreen: true
                        screenGeometry: Qt.rect(-100000, -100000, 1, 1)
                    }
                    // Plasma fills in a launcher's details after the row appears, so re-read
                    // them whenever the model changes, not just when the row is created.
                    property int revision: 0
                    Connections {
                        target: resolver
                        function onDataChanged() { pinRow.revision++ }
                        function onRowsInserted() { pinRow.revision++ }
                        function onRowsRemoved() { pinRow.revision++ }
                        function onModelReset() { pinRow.revision++ }
                    }
                    function field(role) {
                        return pinRow.revision >= 0 && resolver.count > 0 ? resolver.data(resolver.index(0, 0), role) : undefined
                    }
                    // A missing .desktop file still gets a placeholder row, but without an app id.
                    readonly property bool installed: String(field(TaskManager.AbstractTasksModel.AppId) || "").length > 0

                    Kirigami.Icon {
                        Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                        Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                        source: pinRow.installed ? pinRow.field(Qt.DecorationRole) : "dialog-warning"
                    }

                    QQC2.Label {
                        Layout.fillWidth: true
                        Layout.minimumWidth: Kirigami.Units.gridUnit * 10
                        elide: Text.ElideRight
                        text: pinRow.installed
                            ? String(pinRow.field(Qt.DisplayRole) || page.prettyLauncher(pinRow.modelData))
                            : i18n("%1 (not installed, hidden)", page.prettyLauncher(pinRow.modelData))
                        opacity: pinRow.installed ? 1 : 0.6
                    }

                    QQC2.ToolButton {
                        icon.name: "go-up"
                        enabled: pinRow.index > 0
                        onClicked: page.movePin(pinRow.index, pinRow.index - 1)
                        QQC2.ToolTip.text: i18n("Move up")
                        QQC2.ToolTip.visible: hovered
                    }

                    QQC2.ToolButton {
                        icon.name: "go-down"
                        enabled: pinRow.index < page.pinList.length - 1
                        onClicked: page.movePin(pinRow.index, pinRow.index + 1)
                        QQC2.ToolTip.text: i18n("Move down")
                        QQC2.ToolTip.visible: hovered
                    }

                    QQC2.ToolButton {
                        icon.name: "list-remove"
                        onClicked: page.removePin(pinRow.index)
                        QQC2.ToolTip.text: i18n("Unpin")
                        QQC2.ToolTip.visible: hovered
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true

                QQC2.TextField {
                    id: addField
                    Layout.fillWidth: true
                    placeholderText: i18n("Desktop file name, e.g. org.kde.dolphin")
                    onAccepted: addButton.clicked()
                }

                QQC2.Button {
                    id: addButton
                    icon.name: "list-add"
                    text: i18n("Pin")
                    enabled: addField.text.trim().length > 0
                    onClicked: {
                        const url = page.normalizeLauncher(addField.text)
                        if (url.length > 0 && page.pinList.indexOf(url) < 0) {
                            page.setPins(page.pinList.concat([url]))
                        }
                        addField.clear()
                    }
                }
            }

            QQC2.Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                font: Kirigami.Theme.smallFont
                opacity: 0.7
                text: i18n("Tip: right-click any open app in the dock and choose “Pin to Dock”.")
            }
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: syncAllDocks
            Kirigami.FormData.label: i18n("All docks:")
            text: i18n("Use these settings on all docks")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Size, spacing, magnification, names and behaviour then match on every Glossy Dock. Pins and \u201cShow open apps\u201d stay per dock.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: autoIconSize
            Kirigami.FormData.label: i18n("Icon size:")
            text: i18n("Fit the panel")
            checked: page.cfg_iconSize === 0
            onToggled: {
                page.cfg_iconSize = checked ? 0 : iconSize.value
                checked = Qt.binding(() => page.cfg_iconSize === 0)
            }
        }

        QQC2.SpinBox {
            id: iconSize
            enabled: !autoIconSize.checked
            from: 16
            to: 256
            value: page.cfg_iconSize > 0 ? page.cfg_iconSize : 32
            onValueModified: {
                page.cfg_iconSize = value
                value = Qt.binding(() => page.cfg_iconSize > 0 ? page.cfg_iconSize : 32)
            }
            textFromValue: (v, locale) => i18n("%1 px", v)
            valueFromText: (text, locale) => parseInt(text)
        }

        QQC2.CheckBox {
            id: evenIconSizes
            text: i18n("Even out icon sizes")
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Some icons come with empty space around them and look smaller than others; draw those larger so all icons look the same size.")
        }

        QQC2.CheckBox {
            id: fixedHeight
            Kirigami.FormData.label: i18n("Dock height:")
            text: i18n("Set the panel height")
            checked: page.cfg_dockHeight > 0
            onToggled: {
                page.cfg_dockHeight = checked ? dockHeight.value : 0
                checked = Qt.binding(() => page.cfg_dockHeight > 0)
            }
        }

        QQC2.SpinBox {
            id: dockHeight
            enabled: fixedHeight.checked
            from: 24
            to: 256
            value: page.cfg_dockHeight > 0 ? page.cfg_dockHeight : 42
            onValueModified: {
                page.cfg_dockHeight = value
                value = Qt.binding(() => page.cfg_dockHeight > 0 ? page.cfg_dockHeight : 42)
            }
            textFromValue: (v, locale) => i18n("%1 px", v)
            valueFromText: (text, locale) => parseInt(text)
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Applied when you change it. Plasma's own panel settings can still change the height afterwards.")
        }

        QQC2.SpinBox {
            id: spacing
            Kirigami.FormData.label: i18n("Gap between icons:")
            from: 0
            to: 128
            textFromValue: (v, locale) => i18n("%1 px", v)
            valueFromText: (text, locale) => parseInt(text)
        }

        QQC2.SpinBox {
            id: zoom
            Kirigami.FormData.label: i18n("Hover magnification:")
            from: 0
            to: 100
            stepSize: 4
            textFromValue: (v, locale) => v === 0 ? i18n("Off") : i18n("%1 %", v)
            valueFromText: (text, locale) => parseInt(text) || 0
        }

        QQC2.SpinBox {
            id: neighbourZoom
            Kirigami.FormData.label: i18n("Next icons grow:")
            enabled: zoom.value > 0
            from: 0
            to: 100
            stepSize: 4
            textFromValue: (v, locale) => v === 0 ? i18n("Not at all") : i18n("%1 %", v)
            valueFromText: (text, locale) => parseInt(text) || 0
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            text: i18n("Icons never grow taller than the panel, so large values need a taller dock.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.RadioButton {
            Kirigami.FormData.label: i18n("App names:")
            id: namesOff
            text: i18n("Off")
            checked: page.nameMode === 0
            onToggled: {
                if (checked) {
                    page.setNameMode(0)
                }
                checked = Qt.binding(() => page.nameMode === 0)
            }
        }

        QQC2.RadioButton {
            id: namesHover
            text: i18n("On hover, for apps without a preview")
            checked: page.nameMode === 1
            onToggled: {
                if (checked) {
                    page.setNameMode(1)
                }
                checked = Qt.binding(() => page.nameMode === 1)
            }
        }

        QQC2.RadioButton {
            id: namesAlways
            text: i18n("Always, under the icons")
            checked: page.nameMode === 2
            onToggled: {
                if (checked) {
                    page.setNameMode(2)
                }
                checked = Qt.binding(() => page.nameMode === 2)
            }
        }

        QQC2.Label {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            font: Kirigami.Theme.smallFont
            opacity: 0.7
            visible: page.nameMode === 2
            text: i18n("Names take room from the icons; a dock height of 56 px or more works well.")
        }

        Item {
            Kirigami.FormData.isSection: true
        }

        QQC2.CheckBox {
            id: showOpenApps
            Kirigami.FormData.label: i18n("Behavior:")
            text: i18n("Show open apps that aren't pinned")
        }

        QQC2.CheckBox {
            id: showPreviews
            text: i18n("Show window previews on hover")
        }

        QQC2.CheckBox {
            id: peekWindows
            enabled: showPreviews.checked
            text: i18n("Hide other windows while hovering a preview")
        }

        QQC2.CheckBox {
            id: dimMinimized
            text: i18n("Dim icons of minimized apps")
        }
    }
}
