#!/usr/bin/env bash

readonly BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

homebrew_present() { [[ -x "$BREW_BIN" ]]; }

run_homebrew_installer() {
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

brew_cmd() { "$BREW_BIN" "$@"; }
brew_bin_dir() { dirname "$BREW_BIN"; }
brew_tool_present() { [[ -x "$(brew_bin_dir)/$1" ]]; }
gh_cmd() { "$(brew_bin_dir)/gh" "$@"; }
mise_cmd() { "$(brew_bin_dir)/mise" "$@"; }
jq_cmd() { "$(brew_bin_dir)/jq" "$@"; }
make_cmd() { PATH="$(brew_bin_dir):$PATH" make "$@"; }
alacritty_cmd() { alacritty "$@"; }
system_fish_cmd() { /usr/bin/fish "$@"; }

install_homebrew() {
    local bashrc line generated
    homebrew_present || run_homebrew_installer
    homebrew_present || { err "Homebrew installation failed."; return 1; }
    # shellcheck disable=SC2016 # This must run when a future Bash shell starts.
    line='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
    bashrc="$REAL_HOME/.bashrc"
    touch "$bashrc"
    if ! grep -Fqx "$line" "$bashrc"; then
        generated="$(mktemp)"
        cat "$bashrc" >"$generated"
        printf '\n%s\n' "$line" >>"$generated"
        install_file_with_backup "$generated" "$bashrc"
        rm -f "$generated"
    fi
}

install_brew_formulae() {
    local formula missing=()
    for formula in "${BREW_FORMULAE[@]}"; do
        brew_cmd list --formula "$formula" &>/dev/null || missing+=("$formula")
    done
    if ((${#missing[@]})); then
        brew_cmd install "${missing[@]}"
    fi
}

install_mise_tools() {
    local tool
    for tool in "${MISE_TOOLS[@]}"; do
        mise_cmd current "$tool" &>/dev/null || mise_cmd use --global "${tool}@latest"
    done
}
