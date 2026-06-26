import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var workspaces: []
    property var windows: []
    property bool inOverview: false

    function paintChevron(ctx, p) {
        ctx.reset()
        ctx.strokeStyle = "#CCFFFFFF"
        ctx.lineWidth = 3
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.beginPath()
        ctx.moveTo(p[0], p[1])
        ctx.lineTo(p[2], p[3])
        ctx.lineTo(p[4], p[5])
        ctx.stroke()
    }

    function handleEvent(event) {
        if (event.WorkspacesChanged) {
            workspaces = event.WorkspacesChanged.workspaces
        } else if (event.WorkspaceActivated) {
            const data = event.WorkspaceActivated
            const selected = workspaces.find(ws => ws.id === data.id)
            if (!selected)
                return
            workspaces = workspaces.map(ws => Object.assign({}, ws,
                ws.output === selected.output && { is_active: ws.id === data.id },
                data.focused && { is_focused: ws.id === data.id }
            ))
        } else if (event.WorkspaceActiveWindowChanged) {
            const data = event.WorkspaceActiveWindowChanged
            workspaces = workspaces.map(ws => ws.id !== data.workspace_id ? ws : Object.assign({}, ws, { active_window_id: data.active_window_id }))
        } else if (event.WindowsChanged) {
            windows = event.WindowsChanged.windows
        } else if (event.WindowOpenedOrChanged) {
            const w = event.WindowOpenedOrChanged.window
            const updated = windows.slice()
            const idx = updated.findIndex(c => c.id === w.id)
            idx >= 0 ? updated[idx] = w : updated.push(w)
            windows = updated
        } else if (event.WindowClosed) {
            windows = windows.filter(w => w.id !== event.WindowClosed.id)
        } else if (event.WindowFocusChanged) {
            windows = windows.map(w => Object.assign({}, w, { is_focused: w.id === event.WindowFocusChanged.id }))
        } else if (event.OverviewOpenedOrClosed) {
            inOverview = event.OverviewOpenedOrClosed.is_open
        } else if (event.WindowLayoutsChanged) {
            const layouts = {}
            for (const change of event.WindowLayoutsChanged.changes || [])
                layouts[change[0]] = change[1]
            windows = windows.map(w => layouts[w.id] ? Object.assign({}, w, { layout: layouts[w.id] }) : w)
        }
    }

    function hasWorkspace(screenName, direction) {
        const screenWs = workspaces.filter(ws => ws.output === screenName).sort((a, b) => a.idx - b.idx)
        const focusedIdx = screenWs.findIndex(ws => ws.is_focused)
        if (focusedIdx < 0)
            return false
        return direction < 0 ? focusedIdx > 0 : focusedIdx < screenWs.length - 1
    }

    function hasColumn(screenName, direction, screenWidth) {
        const workspace = workspaces.find(candidate => candidate.output === screenName && candidate.is_active)
        if (!workspace)
            return false
        const active = windows.find(window => window.id === workspace.active_window_id)
            || windows.find(window => window.workspace_id === workspace.id && window.is_focused)
        if (!active || active.is_floating || !active.layout?.pos_in_scrolling_layout)
            return false
        const focusedColumn = active.layout.pos_in_scrolling_layout[0]
        const columnWidths = {}
        let maximumColumn = focusedColumn
        for (const window of windows) {
            if (window.workspace_id !== workspace.id || window.is_floating || !window.layout?.pos_in_scrolling_layout)
                continue
            const col = window.layout.pos_in_scrolling_layout[0]
            maximumColumn = Math.max(maximumColumn, col)
            if (window.layout?.tile_size)
                columnWidths[col] = Math.max(columnWidths[col] ?? 0, window.layout.tile_size[0])
        }
        if (direction < 0 ? focusedColumn <= 1 : focusedColumn >= maximumColumn)
            return false
        return Object.values(columnWidths).reduce((sum, w) => sum + w, 0) > screenWidth
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

            anchors.top: true
            anchors.left: true

            WlrLayershell.margins {
                top: Math.round(modelData.height * 9 / 20)
            }

            Rectangle {
                x: root.inOverview ? 0 : 6
                y: root.inOverview ? 0 : Math.round((parent.height - 52) / 2)
                width: root.inOverview ? parent.width : 26
                height: root.inOverview ? parent.height : 52
                radius: width / 2
                color: "#28000000"

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-column-left"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 11
                    height: 20
                    onPaint: root.paintChevron(getContext("2d"), [width-1, 1, 2, height/2, width-1, height-1])
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

            anchors.top: true

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "#28000000"

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-workspace-up"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 20
                    height: 11
                    onPaint: root.paintChevron(getContext("2d"), [1, height-1, width/2, 2, width-1, height-1])
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

            anchors.bottom: true

            Rectangle {
                anchors.fill: parent
                radius: height / 2
                color: "#28000000"

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-workspace-down"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 20
                    height: 11
                    onPaint: root.paintChevron(getContext("2d"), [1, 1, width/2, height-2, width-1, 1])
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

            anchors.top: true
            anchors.right: true

            WlrLayershell.margins {
                top: Math.round(modelData.height * 9 / 20)
            }

            Rectangle {
                x: root.inOverview ? 0 : parent.width - 26 - 6
                y: root.inOverview ? 0 : Math.round((parent.height - 52) / 2)
                width: root.inOverview ? parent.width : 26
                height: root.inOverview ? parent.height : 52
                radius: width / 2
                color: "#28000000"

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["niri", "msg", "action", "focus-column-right"])
                }

                Canvas {
                    anchors.centerIn: parent
                    width: 11
                    height: 20
                    onPaint: root.paintChevron(getContext("2d"), [2, 1, width-1, height/2, 2, height-1])
                }
            }
        }
    }
}
