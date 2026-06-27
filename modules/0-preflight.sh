#!/usr/bin/env bash

readonly BOOTSTRAP_PACKAGES=(git pciutils)

install_bootstrap_packages() {
    install_required_group "bootstrap prerequisites" "${BOOTSTRAP_PACKAGES[@]}"
}

require_regular_user() {
    if [[ "$(current_euid)" -eq 0 ]]; then
        err "Run this script as a regular user, not through sudo."
        exit 1
    fi
    sudo -v &>/dev/null || { err "This setup requires sudo access."; exit 1; }
}

resolve_identity() {
    local passwd_entry
    REAL_USER="$(id -un)"
    passwd_entry="$(getent passwd "$REAL_USER" || true)"
    REAL_HOME="$(cut -d: -f6 <<<"$passwd_entry")"
    if [[ -z "$REAL_USER" || -z "$REAL_HOME" || ! -d "$REAL_HOME" ]]; then
        err "Could not resolve a valid home directory for the current user."
        exit 1
    fi
    info "Running as ${REAL_USER} (${REAL_HOME})"
}

require_commands() {
    local name missing=()
    for name in sudo rpm dnf curl sha256sum gzip tar mktemp getent lspci git sed grep awk install cmp chmod cut id systemctl timedatectl localectl tr uname rm cp mv mkdir find visudo readlink ln; do
        have_command "$name" || missing+=("$name")
    done
    if ((${#missing[@]})); then
        err "Missing required bootstrap commands: ${missing[*]}"
        exit 1
    fi
}

detect_fedora() {
    local file="${OS_RELEASE_FILE:-/etc/os-release}" distro_id version_id variant_id
    [[ -r "$file" ]] || { err "Cannot read ${file}."; exit 1; }
    distro_id="$(sed -n 's/^ID=//p' "$file" | tr -d '"')"
    version_id="$(sed -n 's/^VERSION_ID=//p' "$file" | tr -d '"')"
    variant_id="$(sed -n 's/^VARIANT_ID=//p' "$file" | tr -d '"')"
    if [[ "$distro_id" != fedora || "$version_id" != "$REQUIRED_FEDORA_VERSION" ]]; then
        err "This script supports Fedora ${REQUIRED_FEDORA_VERSION} only (found ${distro_id:-unknown} ${version_id:-unknown})."
        exit 1
    fi
    if [[ "$variant_id" != workstation ]]; then
        err "This script requires Fedora Workstation (found variant ${variant_id:-unknown})."
        exit 1
    fi
    FEDORA_VERSION="$version_id"
    info "Fedora ${FEDORA_VERSION} detected"
}

require_x86_64() {
    [[ "$(uname -m)" == x86_64 ]] || { err "This setup supports x86_64 only."; exit 1; }
}

require_intel_graphics() {
    lspci -nn | grep -Eiq '(VGA|3D|Display).*Intel' || { err "This setup supports Intel graphics only."; exit 1; }
    info "Intel graphics detected"
}

preflight() {
    step "Checking prerequisites"
    require_regular_user
    resolve_identity
    detect_fedora
    require_x86_64
    install_bootstrap_packages
    require_commands
    require_intel_graphics
}
