#!/usr/bin/env bash

stdin_is_tty() { [[ -t 0 ]]; }

prompt_default_yes() {
    local prompt=$1 answer
    read -r -p "$prompt" answer || answer=""
    [[ "$answer" != n && "$answer" != N ]]
}

kickstart_is_expected() {
    local dir=$1 remote
    [[ -d "$dir/.git" ]] || return 1
    remote="$(git -C "$dir" config --get remote.origin.url || true)"
    [[ "$remote" == https://github.com/nvim-lua/kickstart.nvim.git || "$remote" == git@github.com:nvim-lua/kickstart.nvim.git ]]
}

install_kickstart() {
    local config="$REAL_HOME/.config/nvim" stamp path backup_root
    install_required_group "Kickstart.nvim prerequisites" gcc make git ripgrep tree-sitter-cli unzip neovim
    if ! kickstart_is_expected "$config"; then
        stamp="$(timestamp)"
        backup_root="$REAL_HOME/.nvim-backup-$stamp"
        for path in "$config" "$REAL_HOME/.local/share/nvim" "$REAL_HOME/.local/state/nvim" "$REAL_HOME/.cache/nvim"; do
            if [[ -e "$path" ]]; then
                mkdir -p "$backup_root"
                mv "$path" "$backup_root/$(basename "$(dirname "$path")")-$(basename "$path")"
            fi
        done
        git clone https://github.com/nvim-lua/kickstart.nvim.git "$config"
    fi
    nvim --headless '+qa'
}

offer_kickstart() {
    if ! stdin_is_tty; then
        info "Non-interactive input: skipping Kickstart.nvim"
        OPTIONAL_SKIPPED+=("Kickstart.nvim")
        return 0
    fi
    if ! prompt_default_yes 'Install Kickstart.nvim? [Y/n]'; then
        OPTIONAL_SKIPPED+=("Kickstart.nvim")
        return 0
    fi
    if ! install_kickstart; then
        warn "Optional Kickstart.nvim installation failed"
        OPTIONAL_FAILURES+=("Kickstart.nvim")
    fi
}

install_optional_dms_plugins() {
    local plugin output
    for plugin in codexBar wallpaperDiscovery; do
        info "Third-party DMS registry plugin: ${plugin} (review the source and dependencies shown by DMS)."
        if ! dms plugins install "$plugin"; then
            warn "Optional DMS plugin failed: ${plugin}"
            OPTIONAL_FAILURES+=("DMS plugin ${plugin}")
        fi
    done
    output="$(dms plugins list || true)"
    printf '%s\n' "$output"
    for plugin in codexBar wallpaperDiscovery; do
        grep -Fqi "$plugin" <<<"$output" || warn "DMS plugin is not listed as installed: ${plugin}"
    done
}

offer_dms_plugins() {
    if ! stdin_is_tty; then
        info "Non-interactive input: skipping optional DMS plugins"
        OPTIONAL_SKIPPED+=("DMS plugins")
        return 0
    fi
    if ! prompt_default_yes 'Install optional DMS plugins? [Y/n]'; then
        OPTIONAL_SKIPPED+=("DMS plugins")
        return 0
    fi
    install_optional_dms_plugins
}

run_optional_phase() {
    step "Optional personalization"
    offer_kickstart
    offer_dms_plugins
}

print_summary() {
    printf '\n%b\n' "${GREEN}${BOLD}Core setup complete.${NC}"
    printf '%s\n' "Verified Fedora ${FEDORA_VERSION} Workstation, desktop stack, developer tools, Docker, and configuration."
    ((${#OPTIONAL_SKIPPED[@]})) && info "Optional items skipped: ${OPTIONAL_SKIPPED[*]}"
    ((${#OPTIONAL_FAILURES[@]})) && warn "Optional items that failed: ${OPTIONAL_FAILURES[*]}"
    warn "Set the eDP-1 display scale to 1.67 through DMS after login."
    printf '%b\n' "${YELLOW}Reboot to activate the graphical session and new Docker group membership.${NC}"
}
