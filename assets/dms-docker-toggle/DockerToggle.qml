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
        if (!lazydockerStartProcess.running)
            lazydockerStartProcess.running = true;
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
        command: ["/usr/local/bin/docker-toggle", "status"]
        stdout: StdioCollector {
            onStreamFinished: root.lastStatusOutput = text.trim()
        }
        onExited: (exitCode) => root.dockerActive = exitCode === 0 && root.lastStatusOutput === "active"
    }

    Process {
        id: toggleProcess
        command: ["/usr/local/bin/docker-toggle", "toggle"]
        onExited: (exitCode) => {
            root.refreshStatus();
            if (exitCode === 0)
                ToastService.showInfo(root.dockerActive ? "Stopping Docker" : "Starting Docker");
            else
                ToastService.showError("Docker toggle failed");
        }
    }

    Process {
        id: lazydockerStartProcess
        command: ["/usr/local/bin/docker-toggle", "start"]
        onExited: (exitCode) => {
            root.refreshStatus();
            if (exitCode === 0)
                Quickshell.execDetached(["xdg-terminal-exec", "--", "lazydocker"]);
            else
                ToastService.showError("Could not start Docker for lazydocker");
        }
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "deployed_code"
                size: root.iconSize
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
        DankIcon {
            name: "deployed_code"
            size: root.iconSize
            color: root.dockerActive ? Theme.primary : Theme.surfaceVariantText
        }
    }
}
