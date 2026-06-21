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

main() {
    ensure_git
    sync_managed_checkout
    exec "$INSTALL_DIR/setup.sh"
}

if [[ -z "${BASH_SOURCE[0]-}" || "${BASH_SOURCE[0]-}" == "$0" ]]; then
    main "$@"
fi
