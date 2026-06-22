#!/usr/bin/env bash

install_workstation_update_plugin() {
    local plugin_dir="$REAL_HOME/.config/DankMaterialShell/plugins/workstationUpdate"
    install_symlink_with_backup "$ROOT_DIR/assets/dms-plugins/workstation-update" "$plugin_dir"
}
