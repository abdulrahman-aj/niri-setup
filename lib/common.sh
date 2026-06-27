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
