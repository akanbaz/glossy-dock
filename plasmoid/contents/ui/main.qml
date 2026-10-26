/*
    SPDX-FileCopyrightText: 2026 Anand Kumar Anbazhagan
    SPDX-License-Identifier: GPL-2.0-or-later
*/

pragma ComponentBehavior: Bound

import QtQuick
import QtQml
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import org.kde.taskmanager as TaskManager

PlasmoidItem {
    id: root

    preferredRepresentation: fullRepresentation
    Plasmoid.constraintHints: Plasmoid.CanFillArea
    // An auto-hiding or dodge-windows panel hides as soon as the pointer leaves it, which
    // would take the menu or the window previews down with it. Ask the panel to stay up.
    Plasmoid.status: menu.visible || previewShown
        ? PlasmaCore.Types.RequiresAttentionStatus
        : PlasmaCore.Types.ActiveStatus

    // ---------------------------------------------------------------- settings

    readonly property var pins: String(Plasmoid.configuration.launchers || "")
        .split(",").map(s => s.trim()).filter(s => s.length > 0)
    readonly property bool showOpenApps: Plasmoid.configuration.showOpenApps
    readonly property bool showPreviews: Plasmoid.configuration.showPreviews
    readonly property bool peekWindows: Plasmoid.configuration.peekWindows
    readonly property bool showNames: Plasmoid.configuration.showNameTooltips
    readonly property bool showLabels: Plasmoid.configuration.showLabels
    readonly property bool dimMinimized: Plasmoid.configuration.dimMinimized
    readonly property bool evenIconSizes: Plasmoid.configuration.evenIconSizes

    // ---------------------------------------------------------------- geometry

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool inPanel: vertical || Plasmoid.formFactor === PlasmaCore.Types.Horizontal
    // Size across the dock: the panel's thickness.
    readonly property real thickness: vertical ? width : height

    // App names under the icons. On a horizontal dock they share the panel's thickness
    // with the icon; on a vertical dock they make each slot longer instead.
    TextMetrics {
        id: labelMetrics
        font: Kirigami.Theme.smallFont
        text: "Hg"
    }
    readonly property int labelGap: 1
    readonly property int labelBlock: showLabels ? Math.ceil(labelMetrics.height) + labelGap : 0
    readonly property int crossLabel: vertical ? 0 : labelBlock

    readonly property int iconSize: {
        const fit = Math.max(16, Math.floor(thickness) - crossLabel - 2)
        if (Plasmoid.configuration.iconSize > 0) {
            return inPanel ? Math.min(Plasmoid.configuration.iconSize, fit) : Plasmoid.configuration.iconSize
        }
        if (!inPanel) {
            return Kirigami.Units.iconSizes.large
        }
        return Math.max(16, Math.round((thickness - crossLabel) * (crossLabel > 0 ? 0.78 : 0.69)))
    }
    // Where the icon starts across the dock: icon and name centered together.
    readonly property int iconCrossStart: Math.floor((thickness - iconSize - crossLabel) / 2)
    readonly property int gap: Math.max(0, Plasmoid.configuration.iconSpacing)
    // Length of one slot along the dock (icon, plus its name on a vertical dock).
    readonly property int itemLength: iconSize + (vertical ? labelBlock : 0)
    readonly property int pitch: itemLength + gap
    readonly property int slotCount: slots.length
    // Length along the dock: slots plus the gaps between them, nothing else.
    readonly property int dockLength: slotCount > 0 ? slotCount * itemLength + (slotCount - 1) * gap : itemLength

    // Hover magnification, capped so a grown icon never pokes out of the panel. With names
    // shown under the icons, icons grow upward from their bottom edge instead of the middle.
    readonly property real zoomCap: {
        if (!inPanel) {
            return 2
        }
        if (crossLabel > 0) {
            return (iconCrossStart + iconSize - 1) / iconSize
        }
        return (thickness - 2) / iconSize
    }
    readonly property real hoverScale: Math.max(1, Math.min(1 + Plasmoid.configuration.zoomPercent / 100, zoomCap))
    readonly property real neighbourScale: Math.max(1, Math.min(1 + Plasmoid.configuration.neighbourZoomPercent / 100, hoverScale))

    // The panel puts one grid spacing between its last applet and a hidden trailing
    // spacer. When the dock is the panel's only widget, report that much less length and
    // draw into it, so both rounded ends get the same inset and the background hugs the
    // icons. Next to other widgets that spacing separates the dock from them; leave it.
    readonly property bool aloneInPanel: inPanel && !!Plasmoid.containment
        && Plasmoid.containment.applets.length === 1
    readonly property int trailingGap: aloneInPanel ? Kirigami.Units.smallSpacing : 0
    readonly property int reportedLength: Math.max(1, dockLength - trailingGap)

    Layout.fillWidth: vertical
    Layout.fillHeight: !vertical
    Layout.minimumWidth: vertical ? 0 : reportedLength
    Layout.preferredWidth: vertical ? -1 : reportedLength
    Layout.maximumWidth: vertical ? Number.POSITIVE_INFINITY : reportedLength
    Layout.minimumHeight: vertical ? reportedLength : 0
    Layout.preferredHeight: vertical ? reportedLength : -1
    Layout.maximumHeight: vertical ? reportedLength : Number.POSITIVE_INFINITY

    // Which way popups open, away from the screen edge the panel sits on.
    readonly property int popupEdge: {
        switch (Plasmoid.location) {
        case PlasmaCore.Types.TopEdge: return Qt.BottomEdge
        case PlasmaCore.Types.LeftEdge: return Qt.RightEdge
        case PlasmaCore.Types.RightEdge: return Qt.LeftEdge
        default: return Qt.TopEdge
        }
    }

    property int hoverIndex: -1
    property int tick: 0

    // ---------------------------------------------------------------- models

    // One launcher model per pin. Windows are filtered out (bogus screen) so they never
    // replace the launcher. A starting app briefly swaps its launcher for a startup row;
    // that row has the same icon and app id, and the last known icon is kept regardless.
    Instantiator {
        id: pinModels
        model: root.pins
        // A pin's first refresh runs while it's still being created, when objectAt() can't
        // return it yet; rebuild the slots once it has actually been added (or removed).
        onObjectAdded: root.tick++
        onObjectRemoved: root.tick++

        delegate: QtObject {
            id: pinModel
            required property string modelData
            property int launcher: -1
            property int anyRow: -1
            property var icon: ""
            property string name: ""
            property string appId: ""
            property string url: ""
            // False for a pin whose app isn't installed; the dock leaves it out. Plasma still
            // makes a placeholder row for a missing .desktop file, but it has no app id.
            readonly property bool available: appId.length > 0

            function refresh() {
                const A = TaskManager.AbstractTasksModel
                let l = -1
                let any = -1
                for (let r = 0; r < pinTasks.count; r++) {
                    if (root.role(pinTasks, r, A.IsLauncher) === true) {
                        l = r
                    } else if (any < 0 && root.role(pinTasks, r, A.IsStartup) === true) {
                        any = r
                    }
                }
                launcher = l
                anyRow = l >= 0 ? l : any
                if (anyRow >= 0) {
                    const ic = root.role(pinTasks, anyRow, Qt.DecorationRole)
                    if (ic) {
                        icon = ic
                    }
                    const n = String(root.role(pinTasks, anyRow, Qt.DisplayRole) || "")
                    if (n.length > 0) {
                        name = n
                    }
                    const id = String(root.role(pinTasks, anyRow, A.AppId) || "").toLowerCase()
                    if (id.length > 0) {
                        appId = id
                    }
                    const u = root.plainUrl(root.role(pinTasks, anyRow, A.LauncherUrlWithoutIcon))
                    if (u.length > 0 && u !== url) {
                        url = u
                        root.requestActions(u)
                    }
                }
                root.tick++
            }

            property TaskManager.TasksModel tasks: TaskManager.TasksModel {
                id: pinTasks
                sortMode: TaskManager.TasksModel.SortManual
                groupMode: TaskManager.TasksModel.GroupDisabled
                separateLaunchers: true
                launchInPlace: false
                taskReorderingEnabled: false
                filterByVirtualDesktop: false
                filterByActivity: false
                filterByScreen: true
                screenGeometry: Qt.rect(-100000, -100000, 1, 1)
            }

            property Connections watcher: Connections {
                target: pinTasks
                function onCountChanged() { pinModel.refresh() }
                function onDataChanged() { pinModel.refresh() }
                function onModelReset() { pinModel.refresh() }
                function onRowsInserted() { pinModel.refresh() }
                function onRowsRemoved() { pinModel.refresh() }
            }

            Component.onCompleted: {
                pinTasks.launcherList = [pinModel.modelData]
                pinModel.refresh()
            }
        }
    }

    // Windows only, from every screen, so open/focused state is the same on every dock.
    TaskManager.TasksModel {
        id: tasksModel
        sortMode: TaskManager.TasksModel.SortDisabled
        groupMode: TaskManager.TasksModel.GroupDisabled
        filterByVirtualDesktop: false
        filterByScreen: false
        filterByActivity: false
    }
    readonly property var windowsModel: tasksModel

    Connections {
        target: tasksModel
        function onCountChanged() { root.tick++ }
        function onDataChanged() { root.tick++ }
        function onModelReset() { root.tick++ }
        function onRowsInserted() { root.tick++ }
        function onRowsRemoved() { root.tick++ }
        function onRowsMoved() { root.tick++ }
    }

    function role(model, row, r) {
        return model.data(model.index(row, 0), r)
    }

    function plainUrl(url) {
        return String(url || "").split("?")[0]
    }

    function windowId(row) {
        return String((role(tasksModel, row, TaskManager.AbstractTasksModel.WinIdList) || [])[0] || "")
    }

    // Slots and window rows shift whenever an app opens or closes, so anything that acts
    // later (menu items, previews) remembers a stable key and looks the position up then.
    function slotIndex(key) {
        return key ? slots.findIndex(s => s.key === key) : -1
    }

    function windowRow(id) {
        if (!id) {
            return -1
        }
        for (let r = 0; r < tasksModel.count; r++) {
            if (windowId(r) === id) {
                return r
            }
        }
        return -1
    }

    // Per slot: launcher row, icon, name, app id, and the window rows with their state.
    // Installed pins come first in their fixed order; unpinned open apps follow, one each.
    readonly property var slots: {
        if (tick < 0) { // never true; makes the list rebuild whenever tick changes
            return []
        }
        const A = TaskManager.AbstractTasksModel
        const out = []
        for (let i = 0; i < pins.length; i++) {
            const pm = pinModels.objectAt(i)
            if (!pm || !pm.available || (pm.appId && out.some(s => s.appId === pm.appId))) {
                continue
            }
            out.push({ key: pm.appId, pinIndex: i, pinned: true, launcher: pm.launcher, icon: pm.icon, name: pm.name,
                       appId: pm.appId, url: pm.url || pins[i], windows: [], active: -1, visible: -1, minimized: -1 })
        }
        for (let r = 0; r < tasksModel.count; r++) {
            if (role(tasksModel, r, A.IsWindow) !== true) {
                continue
            }
            const appId = String(role(tasksModel, r, A.AppId) || "").toLowerCase()
            let pos = appId.length > 0 ? out.findIndex(s => s.appId === appId) : -1
            if (pos < 0) {
                if (!showOpenApps) {
                    continue
                }
                out.push({ key: appId || ("window:" + windowId(r)), pinIndex: -1, pinned: false, launcher: -1,
                           icon: role(tasksModel, r, Qt.DecorationRole) || "",
                           name: String(role(tasksModel, r, A.AppName) || role(tasksModel, r, Qt.DisplayRole) || ""),
                           appId: appId || ("window:" + windowId(r)),
                           url: plainUrl(role(tasksModel, r, A.LauncherUrlWithoutIcon)),
                           windows: [], active: -1, visible: -1, minimized: -1 })
                pos = out.length - 1
            }
            const s = out[pos]
            s.windows.push(r)
            if (role(tasksModel, r, A.IsActive) === true) {
                s.active = r
            } else if (role(tasksModel, r, A.IsMinimized) === true) {
                if (s.minimized < 0) {
                    s.minimized = r
                }
            } else if (s.visible < 0) {
                s.visible = r
            }
        }
        return out
    }

    // Troubleshooting and tests: log the apps the dock shows, in order ("+" = not pinned).
    readonly property bool debugLog: Plasmoid.configuration.debugLog
    function logSlots() {
        if (debugLog) {
            console.info("glossydock-slots:", Plasmoid.id, slots.map(s => (s.pinned ? "" : "+") + (s.name || s.appId)).join(" | "))
        }
    }
    onSlotsChanged: {
        logSlots()
        measureIcons()
    }
    onSlotCountChanged: hoverIndex = -1

    // ---------------------------------------------------------------- even icon sizes

    // How much of its box each icon's artwork fills, per app and size ("key@size" -> 0..1].
    // Icons with built-in transparent padding are drawn larger so all icons look alike.
    property var iconFill: ({})
    property int fillTick: 0
    readonly property real maxIconBoost: 1.3

    IconFitter {
        id: fitter
        onMeasured: (key, fill) => {
            root.iconFill[key] = fill
            root.fillTick++
            if (root.debugLog) {
                console.info("glossydock-fit:", Plasmoid.id, key.split("@")[0], fill.toFixed(3))
            }
        }
    }

    function fillKey(s) {
        return s.key + "@" + iconSize
    }

    function measureIcons() {
        if (!evenIconSizes) {
            return
        }
        for (const s of slots) {
            const k = fillKey(s)
            if (s.icon && iconFill[k] === undefined) {
                iconFill[k] = -1 // queued
                fitter.measure(k, s.icon, iconSize)
            }
        }
    }
    onIconSizeChanged: measureIcons()
    onEvenIconSizesChanged: measureIcons()

    // Size to draw an icon at so its artwork matches a full-bleed icon of iconSize.
    function drawnSize(s) {
        if (fillTick < 0 || !evenIconSizes || !s || !s.key) {
            return iconSize
        }
        const fill = iconFill[fillKey(s)]
        if (!(fill > 0) || fill >= 0.98) {
            return iconSize
        }
        return Math.round(iconSize * Math.min(maxIconBoost, 1 / fill))
    }
    onDebugLogChanged: logSlots()

    // ---------------------------------------------------------------- actions

    function scaleFor(i) {
        if (hoverIndex < 0) {
            return 1
        }
        const d = Math.abs(hoverIndex - i)
        return d === 0 ? hoverScale : d === 1 ? neighbourScale : 1
    }

    // Tell KWin where each window's icon is, for the minimize animation.
    function publishGeometry(i) {
        const s = slots[i]
        const cell = repeater.itemAt(i)
        if (!s || !cell) {
            return
        }
        const p = cell.iconItem.mapToGlobal(0, 0)
        const rect = Qt.rect(p.x, p.y, iconSize, iconSize)
        for (const r of s.windows) {
            tasksModel.requestPublishDelegateGeometry(tasksModel.index(r, 0), rect, cell.iconItem)
        }
    }

    function pinModelFor(s) {
        return s && s.pinIndex >= 0 ? pinModels.objectAt(s.pinIndex) : null
    }

    function launch(i) {
        const s = slots[i]
        const pm = pinModelFor(s)
        if (pm && pm.launcher >= 0) {
            pm.tasks.requestActivate(pm.tasks.index(pm.launcher, 0))
        }
    }

    // Left click: closed -> launch, background -> raise, focused -> minimize, minimized -> restore.
    function toggle(i) {
        const s = slots[i]
        if (!s) {
            return
        }
        publishGeometry(i)
        if (s.active >= 0) {
            tasksModel.requestToggleMinimized(tasksModel.index(s.active, 0))
        } else if (s.visible >= 0) {
            tasksModel.requestActivate(tasksModel.index(s.visible, 0))
        } else if (s.minimized >= 0) {
            tasksModel.requestActivate(tasksModel.index(s.minimized, 0))
        } else {
            launch(i)
        }
    }

    // Menu "Open": launch when closed, otherwise bring it forward.
    function open(i) {
        const s = slots[i]
        if (!s) {
            return
        }
        publishGeometry(i)
        const r = s.active >= 0 ? s.active : s.visible >= 0 ? s.visible : s.minimized
        if (r >= 0) {
            tasksModel.requestActivate(tasksModel.index(r, 0))
        } else {
            launch(i)
        }
    }

    function newWindow(i) {
        const s = slots[i]
        const pm = pinModelFor(s)
        if (pm && pm.anyRow >= 0) {
            pm.tasks.requestNewInstance(pm.tasks.index(pm.anyRow, 0))
        } else if (s && s.windows.length > 0) {
            tasksModel.requestNewInstance(tasksModel.index(s.windows[0], 0))
        }
    }

    function closeAll(i) {
        const s = slots[i]
        if (!s) {
            return
        }
        const indexes = s.windows.map(r => tasksModel.index(r, 0))
        for (const idx of indexes) {
            tasksModel.requestClose(idx)
        }
    }

    function activateWindowRow(row) {
        tasksModel.requestActivate(tasksModel.index(row, 0))
    }

    function closeWindowRow(row) {
        tasksModel.requestClose(tasksModel.index(row, 0))
    }

    function setPinned(i, pinned) {
        const s = slots[i]
        if (!s) {
            return
        }
        const list = pins.slice()
        if (pinned) {
            if (!s.url || list.indexOf(s.url) >= 0) {
                return
            }
            list.push(s.url)
        } else if (s.pinIndex >= 0) {
            // Also drop other entries for the same app (e.g. "Browser" and the browser's own
            // launcher), which the dock shows only once.
            const keep = pins.filter((pin, k) => {
                const pm = pinModels.objectAt(k)
                return k !== s.pinIndex && !(pm && pm.appId && pm.appId === s.appId)
            })
            list.splice(0, list.length, ...keep)
        }
        Plasmoid.configuration.launchers = list.join(",")
    }

    // ---------------------------------------------------------------- optional services
    // Each of these imports a module some systems may lack. Loading them separately means
    // a missing module only disables that feature instead of breaking the whole dock.

    Loader {
        id: kwin
        source: "DBusBridge.qml"
    }

    // "Dock height" setting: resize this dock's panel when the setting changes (not at
    // start-up, so a height changed later in Plasma's own panel editor is left alone).
    readonly property int dockHeight: Plasmoid.configuration.dockHeight
    onDockHeightChanged: {
        if (dockHeight > 0 && inPanel && kwin.item) {
            kwin.item.setPanelThickness(Plasmoid.id, dockHeight)
        }
    }

    // Window peek: KWin hides every other window while a preview is hovered.
    function highlight(ids) {
        if (kwin.item && (peekWindows || ids.length === 0)) {
            kwin.item.highlightWindows(ids)
        }
    }

    function windowView(ids) {
        if (kwin.item) {
            kwin.item.showWindows(ids)
        }
    }

    Loader {
        id: actionRunner
        source: "ActionRunner.qml"
    }

    Connections {
        target: actionRunner.item
        function onListed(url, actions) {
            root.actionCache[url] = actions
            const p = root.pendingMenu
            if (p && p.url === url) {
                root.pendingMenu = null
                pendingMenuTimer.stop()
                root.showMenu(root.slotIndex(p.key), p.parent)
            }
        }
    }

    // App actions ("Desktop Action" entries of the .desktop file), cached per launcher.
    property var actionCache: ({})
    property var pendingMenu: null

    function requestActions(url) {
        if (url && actionRunner.item && actionCache[url] === undefined) {
            actionRunner.item.list(url)
        }
    }

    function runAction(url, actionId) {
        if (actionRunner.item) {
            actionRunner.item.run(url, actionId)
        }
    }

    // Never leave the user waiting: open the menu without app actions if they're slow.
    Timer {
        id: pendingMenuTimer
        interval: 300
        onTriggered: {
            const p = root.pendingMenu
            root.pendingMenu = null
            if (p) {
                root.showMenu(root.slotIndex(p.key), p.parent)
            }
        }
    }

    // ---------------------------------------------------------------- window previews

    // Which app the preview popup belongs to, and how many slots currently show it (the
    // shared popup can briefly be "shown" by two slots while moving between icons).
    property string previewKey: ""
    property int previewsShowing: 0
    readonly property bool previewShown: previewsShowing > 0
    readonly property int previewIndex: tick >= 0 ? slotIndex(previewKey) : -1
    readonly property var previewWindows: {
        if (tick < 0) { // never true; recompute whenever tick changes
            return []
        }
        const A = TaskManager.AbstractTasksModel
        const s = slots[previewIndex]
        if (!s) {
            return []
        }
        return s.windows.map(r => ({
            row: r,
            uuid: windowId(r),
            title: String(role(tasksModel, r, Qt.DisplayRole) || ""),
            minimized: role(tasksModel, r, A.IsMinimized) === true,
            active: role(tasksModel, r, A.IsActive) === true
        }))
    }
    readonly property var previewIcon: (slots[previewIndex] || { icon: "" }).icon

    function closePreview() {
        highlight([])
        const cell = repeater.itemAt(previewIndex)
        if (cell) {
            cell.hideImmediately()
        }
    }

    // One preview body shared by every slot; the tooltip reparents it into its popup.
    property Item previewPanel: WindowPreviews {
        dock: root
    }

    Component.onDestruction: highlight([])

    // ---------------------------------------------------------------- the dock

    // Shown only when there is nothing to show yet, so the dock never collapses to nothing.
    Kirigami.Icon {
        visible: root.slotCount === 0
        anchors.centerIn: parent
        width: root.iconSize
        height: root.iconSize
        source: Plasmoid.icon
        opacity: 0.4
    }

    Repeater {
        id: repeater
        model: root.slotCount

        // Each slot covers its icon plus half the gap on either side, so hover and clicks
        // have no dead space between icons.
        delegate: PlasmaCore.ToolTipArea {
            id: cell
            required property int index

            readonly property var st: root.slots[index] || ({ windows: [], active: -1, visible: -1, icon: "", name: "" })
            readonly property bool isOpen: st.windows.length > 0
            readonly property bool isActive: st.active >= 0
            readonly property bool isMinimized: isOpen && st.active < 0 && st.visible < 0
            readonly property bool usePreview: isOpen && root.showPreviews
            readonly property real slotStart: index === 0 ? 0 : index * root.pitch - root.gap / 2
            readonly property real slotEnd: index === root.slotCount - 1 ? root.dockLength : index * root.pitch + root.itemLength + root.gap / 2
            // The icon's box: where the icon sits, what names, indicators and the minimize
            // animation line up with. The drawn icon may be larger (see drawnSize).
            property alias iconItem: iconBox

            x: root.vertical ? 0 : slotStart
            y: root.vertical ? slotStart : 0
            width: root.vertical ? root.width : slotEnd - slotStart
            height: root.vertical ? slotEnd - slotStart : root.height

            Accessible.role: Accessible.Button
            Accessible.name: st.name
            Accessible.onPressAction: root.toggle(index)

            location: Plasmoid.location
            interactive: usePreview
            timeout: usePreview ? -1 : 4000
            active: !menu.visible && (usePreview || (root.showNames && !root.showLabels && st.name.length > 0))
            mainItem: usePreview ? root.previewPanel : null
            mainText: usePreview ? "" : st.name
            property bool showingPreview: false
            onAboutToShow: {
                if (usePreview) {
                    root.previewKey = st.key
                }
            }
            onToolTipVisibleChanged: toolTipVisible => {
                const now = toolTipVisible && usePreview
                if (now !== showingPreview) {
                    showingPreview = now
                    root.previewsShowing += now ? 1 : -1
                }
                if (!toolTipVisible) {
                    root.highlight([])
                }
            }
            Component.onDestruction: {
                if (showingPreview) {
                    root.previewsShowing -= 1
                }
            }

            onXChanged: root.publishGeometry(index)
            onYChanged: root.publishGeometry(index)

            Item {
                id: iconBox
                readonly property real along: cell.index * root.pitch - cell.slotStart
                x: root.vertical ? Math.round((parent.width - width) / 2) : along
                y: root.vertical ? along : root.iconCrossStart
                width: root.iconSize
                height: root.iconSize
            }

            Kirigami.Icon {
                id: icon
                readonly property int drawn: root.drawnSize(cell.st)
                x: iconBox.x + Math.round((root.iconSize - drawn) / 2)
                y: iconBox.y + Math.round((root.iconSize - drawn) / 2)
                width: drawn
                height: drawn
                source: cell.st.icon
                // Draw at the real size; rounding to a standard icon size (22, 32...) would
                // shrink a 29px icon to 22.
                roundToIconSize: false
                animated: false
                opacity: root.dimMinimized && cell.isMinimized ? 0.5 : 1
                transformOrigin: root.showLabels ? Item.Bottom : Item.Center
                scale: root.scaleFor(cell.index)
                Behavior on scale {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            PlasmaComponents3.Label {
                visible: root.showLabels
                width: root.vertical ? parent.width - 4 : root.pitch - 2
                x: root.vertical ? 2 : Math.round(iconBox.x + (root.iconSize - width) / 2)
                y: iconBox.y + root.iconSize + root.labelGap
                height: root.labelBlock - root.labelGap
                text: cell.st.name
                font: Kirigami.Theme.smallFont
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
                maximumLineCount: 1
                opacity: root.dimMinimized && cell.isMinimized ? 0.5 : 0.9
            }

            // Open indicator, on the side of the icon that faces the screen edge:
            // short = open, long and bright = focused, faint = minimized.
            Rectangle {
                property real length: cell.isActive ? Math.round(root.iconSize * 0.48) : Math.max(4, Math.round(root.iconSize * 0.17))
                readonly property int edge: Plasmoid.location
                visible: cell.isOpen
                width: root.vertical ? 2 : length
                height: root.vertical ? length : 2
                x: root.vertical
                    ? (edge === PlasmaCore.Types.LeftEdge ? iconBox.x - 4 : iconBox.x + root.iconSize + 2)
                    : Math.round(iconBox.x + (root.iconSize - width) / 2)
                y: root.vertical
                    ? Math.round(iconBox.y + (root.iconSize - height) / 2)
                    : (edge === PlasmaCore.Types.TopEdge
                        ? Math.max(0, iconBox.y - 4)
                        : Math.min(parent.height - 2, iconBox.y + root.iconSize + root.crossLabel + 2))
                radius: 1
                color: Kirigami.Theme.textColor
                opacity: cell.isActive ? 1 : cell.isMinimized ? 0.35 : 0.6
                Behavior on length {
                    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                onEntered: root.hoverIndex = cell.index
                onExited: {
                    if (root.hoverIndex === cell.index) {
                        root.hoverIndex = -1
                    }
                }
                onClicked: mouse => {
                    cell.hideImmediately()
                    if (mouse.button === Qt.RightButton) {
                        root.openMenu(cell.index, cell)
                    } else if (mouse.button === Qt.MiddleButton) {
                        root.newWindow(cell.index)
                    } else {
                        root.toggle(cell.index)
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- right-click menu

    DockMenu {
        id: menu
        popupDirection: root.popupEdge
    }

    function openMenu(i, parent) {
        const s = slots[i]
        if (!s) {
            return
        }
        if (s.url && actionRunner.item && actionCache[s.url] === undefined) {
            pendingMenu = { key: s.key, url: s.url, parent: parent }
            requestActions(s.url)
            pendingMenuTimer.restart()
            return
        }
        showMenu(i, parent)
    }

    function showMenu(i, parent) {
        const s = slots[i]
        if (!s) {
            return
        }
        const A = TaskManager.AbstractTasksModel
        const isOpen = s.windows.length > 0
        const rep = s.active >= 0 ? s.active : s.visible >= 0 ? s.visible : s.minimized
        const url = s.url
        const key = s.key
        const repId = rep >= 0 ? windowId(rep) : ""
        const entries = []
        const item = (text, icon, run) => entries.push({ text: text, icon: icon || "", run: run, separator: false })
        const separator = () => entries.push({ text: "", icon: "", run: null, separator: true })
        // Menu items run later; find the app and window again then, by key and window id.
        const forSlot = action => () => {
            const j = root.slotIndex(key)
            if (j >= 0) {
                action(j)
            }
        }
        const forWindow = action => () => {
            const r = root.windowRow(repId)
            if (r >= 0) {
                action(tasksModel.index(r, 0))
            }
        }

        item(i18n("Open"), "", forSlot(j => root.open(j)))
        if (s.pinned || isOpen) {
            item(i18n("New window"), "window-new", forSlot(j => root.newWindow(j)))
        }

        const actions = actionCache[url] || []
        if (actions.length > 0) {
            separator()
            for (const a of actions) {
                item(a.name, a.icon, () => root.runAction(url, a.id))
            }
        }

        if (isOpen && rep >= 0) {
            separator()
            const minimized = role(tasksModel, rep, A.IsMinimized) === true
            const maximized = role(tasksModel, rep, A.IsMaximized) === true
            item(minimized ? i18n("Restore") : i18n("Minimize"), minimized ? "window-restore" : "window-minimize",
                 forWindow(idx => minimized ? tasksModel.requestActivate(idx) : tasksModel.requestToggleMinimized(idx)))
            item(maximized ? i18n("Restore size") : i18n("Maximize"), maximized ? "window-restore" : "window-maximize",
                 forWindow(idx => tasksModel.requestToggleMaximized(idx)))
            if (s.windows.length > 1 && kwin.item) {
                const ids = s.windows.map(r => windowId(r)).filter(id => id.length > 0)
                item(i18n("Show all windows"), "window", () => root.windowView(ids))
            }
        }

        if (s.pinned || url) {
            separator()
            if (s.pinned) {
                item(i18n("Unpin from Dock"), "window-unpin", forSlot(j => root.setPinned(j, false)))
            } else {
                item(i18n("Pin to Dock"), "window-pin", forSlot(j => root.setPinned(j, true)))
            }
        }

        if (isOpen) {
            separator()
            item(s.windows.length > 1 ? i18n("Close all %1 windows", s.windows.length) : i18n("Close"),
                 "window-close", forSlot(j => root.closeAll(j)))
        }

        menu.popup(parent, entries)
    }
}


