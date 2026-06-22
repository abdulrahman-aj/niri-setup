#!/usr/bin/env bash

set -euo pipefail

readonly REPO_URL="https://github.com/abdulrahman-aj/niri-setup.git"
readonly INSTALL_DIR="${NIRI_SETUP_DIR:-$HOME/.local/share/niri-setup}"

ensure_git() {
    command -v git &>/dev/null || sudo dnf install -y git
}

sync_managed_checkout() {
    if [[ ! -e "$INSTALL_DIR" ]]; then
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone --branch main "$REPO_URL" "$INSTALL_DIR"
        return
    fi
    [[ -d "$INSTALL_DIR/.git" ]] || {
        printf 'Install path exists but is not a Git repository: %s\n' "$INSTALL_DIR" >&2
        return 1
    }
    [[ "$(git -C "$INSTALL_DIR" remote get-url origin)" == "$REPO_URL" ]] || {
        printf 'Managed checkout has an unexpected origin: %s\n' "$INSTALL_DIR" >&2
        return 1
    }
    [[ -z "$(git -C "$INSTALL_DIR" status --porcelain)" ]] || {
        printf 'Managed checkout has local changes; refusing to update: %s\n' "$INSTALL_DIR" >&2
        return 1
    }
    git -C "$INSTALL_DIR" pull --ff-only origin main
}

stdin_is_tty() { [[ -t 0 ]]; }

pause_for_completion() {
    local status=$1 message
    if stdin_is_tty; then
        if ((status == 0)); then
            message='Workstation update complete. Press any key to close...'
        else
            message="Workstation update failed with status ${status}. Press any key to close..."
        fi
        printf '\n'
        read -r -n 1 -s -p "$message" || true
        printf '\n'
    fi
    return "$status"
}

run_update() {
    local status=0
    ensure_git && sync_managed_checkout && "$INSTALL_DIR/setup.sh" || status=$?
    pause_for_completion "$status"
}

main() { run_update; }

if [[ -z "${BASH_SOURCE[0]-}" || "${BASH_SOURCE[0]-}" == "$0" ]]; then
    main "$@"
fi
