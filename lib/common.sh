#!/usr/bin/env bash

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; MAGENTA='\033[0;35m'; CYAN='\033[0;36m'
BOLD='\033[1m'; NC='\033[0m'

log()  { printf '%b\n' "${GREEN}[✓]${NC} $*"; }
warn() { printf '%b\n' "${YELLOW}[!]${NC} $*"; }
info() { printf '%b\n' "${BLUE}[i]${NC} $*"; }
banner() { printf '%b\n' "${CYAN}${BOLD}$*${NC}"; }
step() { printf '\n%b\n\n' "${MAGENTA}${BOLD}[==]${NC} ${BOLD}$*${NC}"; }
err()  { printf '%b\n' "${RED}[✗]${NC} $*" >&2; }

s() {
    printf '%b\n' "${CYAN}  >${NC} sudo $*"
    sudo "$@"
}

have_command() { command -v "$1" &>/dev/null; }
current_euid() { printf '%s\n' "$EUID"; }

require_regular_user() {
    if [[ "$(current_euid)" -eq 0 ]]; then
        err "Run this script as a regular user, not through sudo."
        exit 1
    fi
    sudo -v &>/dev/null || { err "This setup requires sudo access."; exit 1; }
}

require_bootstrap_commands() {
    local name missing=()
    for name in sudo rpm dnf getent sed tr cut id uname; do
        have_command "$name" || missing+=("$name")
    done
    if ((${#missing[@]})); then
        err "Missing Fedora bootstrap commands: ${missing[*]}"
        exit 1
    fi
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
    require_bootstrap_commands
    require_regular_user
    resolve_identity
    detect_fedora
    require_x86_64
    install_bootstrap_packages
    require_commands
    require_intel_graphics
}

verify_checksum() {
    local actual
    actual="$(sha256sum "$1" | awk '{print $1}')"
    [[ "$actual" == "$2" ]]
}

download_and_verify() {
    local url=$1 sha256=$2 dest=$3
    curl -fsSL "$url" -o "$dest" || { err "Download failed: ${url}"; return 1; }
    verify_checksum "$dest" "$sha256" || { err "Checksum verification failed: ${url}"; return 1; }
}

timestamp() { date +%Y%m%d-%H%M%S; }

backup_path() {
    local path=$1 backup
    [[ -e "$path" || -L "$path" ]] || return 0
    backup="${path}.backup-$(timestamp)"
    cp -a -- "$path" "$backup"
    info "Backed up ${path} to ${backup}"
}

install_file_with_backup() {
    local source_file=$1 destination=$2 mode=${3:-0644}
    mkdir -p "$(dirname "$destination")"
    if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
        return 0
    fi
    backup_path "$destination"
    install -m "$mode" "$source_file" "$destination"
}

install_file_atomically_with_backup() {
    local source_file=$1 destination=$2 mode=${3:-0644} staged
    mkdir -p "$(dirname "$destination")"
    if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
        return 0
    fi
    backup_path "$destination"
    staged="$(mktemp "${destination}.tmp.XXXXXX")"
    if ! install -m "$mode" "$source_file" "$staged"; then
        rm -f "$staged"
        return 1
    fi
    if ! mv -f "$staged" "$destination"; then
        rm -f "$staged"
        return 1
    fi
}

install_generated_file_atomically() {
    local source_file=$1 destination=$2 mode=${3:-0644} staged
    mkdir -p "$(dirname "$destination")"
    if [[ -f "$destination" ]] && cmp -s "$source_file" "$destination"; then
        return 0
    fi
    staged="$(mktemp "${destination}.tmp.XXXXXX")"
    if ! install -m "$mode" "$source_file" "$staged"; then
        rm -f "$staged"
        return 1
    fi
    if ! mv -f "$staged" "$destination"; then
        rm -f "$staged"
        return 1
    fi
}

install_root_file_with_backup() {
    local source_file=$1 destination=$2 mode=${3:-0644} backup
    if sudo test -f "$destination" && sudo cmp -s "$source_file" "$destination"; then
        return 0
    fi
    if sudo test -e "$destination"; then
        backup="${destination}.backup-$(timestamp)"
        s cp -a -- "$destination" "$backup"
        info "Backed up ${destination} to ${backup}"
    fi
    s install -m "$mode" "$source_file" "$destination"
}

install_symlink_with_backup() {
    local target=$1 destination=$2
    mkdir -p "$(dirname "$destination")"
    if [[ -L "$destination" && "$(readlink "$destination")" == "$target" ]]; then
        return 0
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then
        backup_path "$destination"
        rm -rf -- "$destination"
    fi
    ln -s "$target" "$destination"
}

install_root_symlink_with_backup() {
    local target=$1 destination=$2 backup
    if sudo test -L "$destination" && [[ "$(sudo readlink "$destination")" == "$target" ]]; then
        return 0
    fi
    if sudo test -e "$destination" || sudo test -L "$destination"; then
        backup="${destination}.backup-$(timestamp)"
        s cp -a -- "$destination" "$backup"
        s rm -rf -- "$destination"
        info "Backed up ${destination} to ${backup}"
    fi
    s ln -s "$target" "$destination"
}

install_required_group() {
    local label=$1
    shift
    info "Installing required package group: ${label}"
    s dnf install -y "$@"
}
