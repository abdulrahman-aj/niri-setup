import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root

    visibilityCommand: "/usr/local/bin/workstation-update-status"
    visibilityInterval: 1800
    pillClickAction: () => Quickshell.execDetached(["xdg-terminal-exec", "workstation-update"])
    pillRightClickAction: () => root.checkVisibility()

    horizontalBarPill: Component {
        DankIcon {
            name: "system_update_alt"
            size: root.iconSize
            color: Theme.primary
        }
    }

    verticalBarPill: Component {
        DankIcon {
            name: "system_update_alt"
            size: root.iconSize
            color: Theme.primary
        }
    }
}
