#!/usr/bin/env bash

readonly NERD_FONT_VERSION="v3.4.0"
readonly NERD_FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/JetBrainsMono.tar.xz"
readonly NERD_FONT_SHA256="ef552a3e638f25125c6ad4c51176a6adcdce295ab1d2ffacf0db060caf8c1582"

zed_present() { have_command zed || [[ -x "$REAL_HOME/.local/bin/zed" ]]; }

install_zed() {
    if ! zed_present; then
        curl -f https://zed.dev/install.sh | sh
    fi
    zed_present || { err "Zed installation failed."; return 1; }
}

nerd_font_present() {
    [[ "$(fc-match -f '%{family}\n' 'JetBrainsMono Nerd Font')" == *'JetBrainsMono Nerd Font'* ]]
}

install_nerd_font() {
    local font_dir="$REAL_HOME/.local/share/fonts/JetBrainsMonoNerdFont" tempdir archive
    if nerd_font_present; then
        log "JetBrainsMono Nerd Font is installed"
        return 0
    fi
    tempdir="$(mktemp -d)"
    archive="$tempdir/JetBrainsMono.tar.xz"
    trap 'rm -rf "${tempdir:-}"; trap - RETURN' RETURN
    download_and_verify "$NERD_FONT_URL" "$NERD_FONT_SHA256" "$archive" || return 1
    mkdir -p "$font_dir"
    tar -xJf "$archive" -C "$font_dir" --wildcards '*.ttf'
    fc-cache -f "$font_dir"
    nerd_font_present || { err "JetBrainsMono Nerd Font was not discovered."; return 1; }
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
