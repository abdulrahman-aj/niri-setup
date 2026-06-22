import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: root

    property var workspaces: []
    property var windows: []
    property bool overviewOpen: false

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
        } else if (event.WindowLayoutsChanged) {
            const changes = event.WindowLayoutsChanged.changes || []
            const layouts = {}
            for (const change of changes)
                layouts[change[0]] = change[1]
            windows = windows.map(window => layouts[window.id] ? Object.assign({}, window, { layout: layouts[window.id] }) : window)
        } else if (event.OverviewOpenedOrClosed) {
            overviewOpen = event.OverviewOpenedOrClosed.is_open
        }
    }

    function hasColumn(screenName, direction) {
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
        return direction < 0 ? focusedColumn > 1 : focusedColumn < maximumColumn
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
            visible: !root.overviewOpen && root.hasColumn(modelData.name, -1)
            color: "transparent"
            implicitWidth: 26
            implicitHeight: 52
            WlrLayershell.namespace: "niri-edge-indicator-left"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                left: true
            }

            WlrLayershell.margins {
                top: Math.max(0, Math.round((modelData.height - implicitHeight) / 2))
                left: 6
            }

            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#66000000"

                Text {
                    anchors.centerIn: parent
                    text: "‹"
                    color: "#CCFFFFFF"
                    font.pixelSize: 30
                    font.weight: Font.Medium
                }
            }
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData

            screen: modelData
            visible: !root.overviewOpen && root.hasColumn(modelData.name, 1)
            color: "transparent"
            implicitWidth: 26
            implicitHeight: 52
            WlrLayershell.namespace: "niri-edge-indicator-right"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusiveZone: -1
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            anchors {
                top: true
                right: true
            }

            WlrLayershell.margins {
                top: Math.max(0, Math.round((modelData.height - implicitHeight) / 2))
                right: 6
            }

            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: "#66000000"

                Text {
                    anchors.centerIn: parent
                    text: "›"
                    color: "#CCFFFFFF"
                    font.pixelSize: 30
                    font.weight: Font.Medium
                }
            }
        }
    }
}
