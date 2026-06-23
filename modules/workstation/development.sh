#!/usr/bin/env bash

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
ghostty_cmd() { ghostty "$@"; }
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

configure_git() {
    git config --global init.defaultBranch main
    git config --global user.name 'Abdulrahman Ajlouni'
    git config --global user.email ajlouni2000@gmail.com
}

ensure_github_auth() {
    local protocol
    gh_cmd auth status &>/dev/null || BROWSER=google-chrome gh_cmd auth login --web --git-protocol ssh
    gh_cmd auth status &>/dev/null || { err "GitHub authentication is not healthy."; return 1; }
    gh_cmd config set git_protocol ssh --host github.com || {
        err "Failed to configure GitHub CLI to use SSH."
        return 1
    }
    protocol="$(gh_cmd config get git_protocol --host github.com)"
    [[ "$protocol" == ssh ]] || { err "GitHub CLI git protocol is not SSH."; return 1; }
}

install_mise_tools() {
    local tool
    for tool in "${MISE_TOOLS[@]}"; do
        mise_cmd current "$tool" &>/dev/null || mise_cmd use --global "${tool}@latest"
    done
}

