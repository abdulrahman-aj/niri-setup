#!/usr/bin/env bash

install_commands() {
    local directory="${COMMANDS_DIR:-$ROOT_DIR/bin}" command name first_line found=0
    for command in "$directory"/*; do
        [[ -e "$command" ]] || continue
        found=1
        if [[ ! -f "$command" || ! -x "$command" ]]; then
            err "Invalid command in bin/: ${command}"
            return 1
        fi
        IFS= read -r first_line <"$command" || true
        if [[ "$first_line" != '#!'* ]]; then
            err "Invalid command in bin/: ${command}"
            return 1
        fi
        name="$(basename "$command")"
        install_root_symlink_with_backup "$command" "/usr/local/bin/$name"
    done
    ((found)) || { err "No commands found in: $directory"; return 1; }
    log "Repository commands installed"
}
