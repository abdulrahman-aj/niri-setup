#!/usr/bin/env bash
# Personal Fedora 44 workstation bootstrap: Niri + DMS + Ghostty.
# shellcheck disable=SC2034 # Constants and state are consumed by sourced modules.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly ROOT_DIR
readonly REQUIRED_FEDORA_VERSION="44"
readonly DOTFILES_REPO_HTTPS="https://github.com/abdulrahman-aj/dotfiles.git"
readonly DOTFILES_REPO_SSH="git@github.com:abdulrahman-aj/dotfiles.git"
readonly DANKINSTALL_VERSION="v1.4.6"
readonly DANKINSTALL_URL="https://github.com/AvengeMedia/DankMaterialShell/releases/download/${DANKINSTALL_VERSION}/dankinstall-amd64.gz"
readonly DANKINSTALL_SHA256="75f9a528c54f9048baa7994fb701d3c5799bee62cf0c7082a696ab6782df97e4"
readonly NERD_FONT_VERSION="v3.4.0"
readonly NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/JetBrainsMono.tar.xz"
readonly NERD_FONT_SHA256="ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582"
readonly FISHER_BOOTSTRAP_URL="https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish"
readonly BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

REAL_USER=""
REAL_HOME=""
FEDORA_VERSION=""
OPTIONAL_FAILURES=()
OPTIONAL_SKIPPED=()

source_required() {
    local file=$1
    [[ "$file" == /* ]] || file="$ROOT_DIR/$file"
    if [[ ! -r "$file" ]]; then
        printf 'Required installer component is missing or unreadable: %s\n' "$file" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$file"
}

source_modules() {
    local directory=${1:-"$ROOT_DIR/modules"} module
    local found=0
    for module in "$directory"/*.sh; do
        [[ -e "$module" ]] || continue
        found=1
        source_required "$module"
    done
    if ((found == 0)); then
        printf 'No installer modules found in: %s\n' "$directory" >&2
        return 1
    fi
}

source_required "$ROOT_DIR/lib/git-remote.sh"
source_required "$ROOT_DIR/lib/common.sh"
source_modules "$ROOT_DIR/modules" || exit 1

main() {
    banner "Fedora 44 → Niri + DankMaterialShell + Ghostty"

    preflight
    run_system_phase
    run_workstation_phase
    run_optional_phase
    print_summary
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
