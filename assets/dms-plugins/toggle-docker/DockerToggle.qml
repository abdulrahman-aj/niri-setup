import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    property bool dockerActive: false
    property string lastStatusOutput: ""

    function refreshStatus() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function toggleDocker() {
        if (!toggleProcess.running)
            toggleProcess.running = true;
    }

    function openLazydocker() {
        Quickshell.execDetached(["/usr/local/bin/launch-or-focus-tui", "lazydocker"]);
    }

    pillClickAction: () => toggleDocker()
    pillRightClickAction: () => openLazydocker()

    Component.onCompleted: refreshStatus()

    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: root.refreshStatus()
    }

    Process {
        id: statusProcess
        command: ["/usr/local/bin/toggle-docker", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.lastStatusOutput = text.trim()
        }
        onExited: (exitCode) => root.dockerActive = exitCode === 0 && root.lastStatusOutput === "active"
    }

    Process {
        id: toggleProcess
        command: ["/usr/local/bin/toggle-docker", "toggle"]
        onExited: (exitCode) => {
            root.refreshStatus();
            if (exitCode === 0)
                ToastService.showInfo(root.dockerActive ? "Stopping Docker" : "Starting Docker");
            else
                ToastService.showError("Docker toggle failed");
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "\uf308"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: root.iconSize
                color: root.dockerActive ? Theme.primary : Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: root.dockerActive ? "On" : "Off"
                font.pixelSize: Theme.fontSizeSmall
                color: root.dockerActive ? Theme.primary : Theme.surfaceVariantText
            }
        }
    }

    verticalBarPill: Component {
        StyledText {
            text: "\uf308"
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: root.iconSize
            color: root.dockerActive ? Theme.primary : Theme.surfaceVariantText
        }
    }
}
