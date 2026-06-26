import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var workspaces: []
    property var windows: []
    property bool inOverview: false

    function replaceWindow(window) {
        const index = windows.findIndex(candidate => candidate.id === window.id)
        const updated = windows.slice()
        if (index >= 0)
            updated[index] = window
        else
            updated.push(window)
        windows = updated
    }

    function handleEvent(event) {
        if (event.WorkspacesChanged) {
            workspaces = event.WorkspacesChanged.workspaces
        } else if (event.WorkspaceActivated) {
            const data = event.WorkspaceActivated
            const selected = workspaces.find(workspace => workspace.id === data.id)
            if (!selected)
                return
            workspaces = workspaces.map(workspace => {
                const updated = Object.assign({}, workspace)
                if (workspace.output === selected.output)
                    updated.is_active = workspace.id === data.id
                if (data.focused)
                    updated.is_focused = workspace.id === data.id
                return updated
            })
        } else if (event.WorkspaceActiveWindowChanged) {
            const data = event.WorkspaceActiveWindowChanged
            workspaces = workspaces.map(workspace => {
                if (workspace.id !== data.workspace_id)
                    return workspace
                return Object.assign({}, workspace, { active_window_id: data.active_window_id })
            })
        } else if (event.WindowsChanged) {
            windows = event.WindowsChanged.windows
        } else if (event.WindowOpenedOrChanged) {
            replaceWindow(event.WindowOpenedOrChanged.window)
        } else if (event.WindowClosed) {
            const id = event.WindowClosed.id
            windows = windows.filter(window => window.id !== id)
        } else if (event.WindowFocusChanged) {
            const id = event.WindowFocusChanged.id
            windows = windows.map(window => Object.assign({}, window, { is_focused: window.id === id }))
        } else if (event.OverviewOpenedOrClosed) {
            inOverview = event.OverviewOpenedOrClosed.is_open
        } else if (event.WindowLayoutsChanged) {
            const changes = event.WindowLayoutsChanged.changes || []
            const layouts = {}
            for (const change of changes)
                layouts[change[0]] = change[1]
            windows = windows.map(window => layouts[window.id] ? Object.assign({}, window, { layout: layouts[window.id] }) : window)
        }
    }

    function hasWorkspace(screenName, direction) {
        const screenWs = workspaces
            .filter(ws => ws.output === screenName)
            .sort((a, b) => a.idx - b.idx)
        const focusedIdx = screenWs.findIndex(ws => ws.is_focused)
        if (focusedIdx < 0)
            return false
        if (direction < 0)
            return focusedIdx > 0
        return focusedIdx < screenWs.length - 1
    }

    function hasColumn(screenName, direction, screenWidth) {
        const workspace = workspaces.find(candidate => candidate.output === screenName && candidate.is_active)
        if (!workspace)
            return false
        const active = windows.find(window => window.id === workspace.active_window_id)
            || windows.find(window => window.workspace_id === workspace.id && window.is_focused)
        if (!active || active.is_floating || !active.layout || !active.layout.pos_in_scrolling_layout)
            return false
        const focusedColumn = active.layout.pos_in_scrolling_layout[0]
        let maximumColumn = focusedColumn
        for (const window of windows) {
            if (window.workspace_id !== workspace.id || window.is_floating || !window.layout || !window.layout.pos_in_scrolling_layout)
                continue
            maximumColumn = Math.max(maximumColumn, window.layout.pos_in_scrolling_layout[0])
        }
        if (direction < 0 ? focusedColumn <= 1 : focusedColumn >= maximumColumn)
            return false
        const columnWidths = {}
        for (const window of windows) {
            if (window.workspace_id !== workspace.id || window.is_floating || !window.layout?.pos_in_scrolling_layout || !window.layout?.tile_size)
                continue
            const col = window.layout.pos_in_scrolling_layout[0]
            columnWidths[col] = Math.max(columnWidths[col] ?? 0, window.layout.tile_size[0])
        }
        const totalWidth = Object.values(columnWidths).reduce((sum, w) => sum + w, 0)
        if (totalWidth <= screenWidth)
            return false
        return true
    }

    Process {
        id: eventStream
        command: ["niri", "msg", "--json", "event-stream"]
        running: true

        stdout: SplitParser {
            onRead: line => {
                try {
                    root.handleEvent(JSON.parse(line))
                } catch (error) {
                    console.warn("niri-edge-indicators: invalid event:", error)
                }
            }
        }

        onExited: reconnectTimer.restart()
    }

    Timer {
        id: reconnectTimer
        interval: 1500
        onTriggered: eventStream.running = true
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: root.hasColumn(modelData.name, -1, modelData.width)
            color: "transparent"
            implicitWidth: 40
            implicitHeight: Math.round(modelData.height / 10)
            WlrLayershell.namespace: "niri-edge-indicator-left"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                left: true
            }

            WlrLayershell.margins {
                top: Math.round(modelData.height * 9 / 20)
                left: 0
            }

            Rectangle {
                id: pill
                x: root.inOverview ? 0 : 6
                y: root.inOverview ? 0 : Math.round((parent.height - 52) / 2)
                width: root.inOverview ? parent.width : 26
                height: root.inOverview ? parent.height : 52
                radius: width / 2
                color: hover.containsMouse ? "#28000000" : (root.inOverview ? "#28000000" : "#28000000")

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-column-left"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 11
                    height: 20
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = "#CCFFFFFF"
                        ctx.lineWidth = 3
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(width - 1, 1)
                        ctx.lineTo(2, height / 2)
                        ctx.lineTo(width - 1, height - 1)
                        ctx.stroke()
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: root.inOverview && root.hasWorkspace(modelData.name, -1)
            color: "transparent"
            implicitWidth: Math.round(modelData.height / 10)
            implicitHeight: 40
            WlrLayershell.namespace: "niri-edge-indicator-up"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
            }

            WlrLayershell.margins {
                top: 0
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: hover.containsMouse ? "#28000000" : "#28000000"


                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-workspace-up"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 20
                    height: 11
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = "#CCFFFFFF"
                        ctx.lineWidth = 3
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(1, height - 1)
                        ctx.lineTo(width / 2, 2)
                        ctx.lineTo(width - 1, height - 1)
                        ctx.stroke()
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: root.inOverview && root.hasWorkspace(modelData.name, 1)
            color: "transparent"
            implicitWidth: Math.round(modelData.height / 10)
            implicitHeight: 40
            WlrLayershell.namespace: "niri-edge-indicator-down"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                bottom: true
            }

            WlrLayershell.margins {
                bottom: 0
            }

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: hover.containsMouse ? "#28000000" : "#28000000"


                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-workspace-down"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 20
                    height: 11
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = "#CCFFFFFF"
                        ctx.lineWidth = 3
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(1, 1)
                        ctx.lineTo(width / 2, height - 2)
                        ctx.lineTo(width - 1, 1)
                        ctx.stroke()
                    }
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: root.hasColumn(modelData.name, 1, modelData.width)
            color: "transparent"
            implicitWidth: 40
            implicitHeight: Math.round(modelData.height / 10)
            WlrLayershell.namespace: "niri-edge-indicator-right"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                right: true
            }

            WlrLayershell.margins {
                top: Math.round(modelData.height * 9 / 20)
                right: 0
            }

            Rectangle {
                id: pill
                x: root.inOverview ? 0 : parent.width - 26 - 6
                y: root.inOverview ? 0 : Math.round((parent.height - 52) / 2)
                width: root.inOverview ? parent.width : 26
                height: root.inOverview ? parent.height : 52
                radius: width / 2
                color: hover.containsMouse ? "#28000000" : (root.inOverview ? "#28000000" : "#28000000")

                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-column-right"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 11
                    height: 20
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.strokeStyle = "#CCFFFFFF"
                        ctx.lineWidth = 3
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(2, 1)
                        ctx.lineTo(width - 1, height / 2)
                        ctx.lineTo(2, height - 1)
                        ctx.stroke()
                    }
                }
            }
        }
    }
}
