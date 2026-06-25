#!/usr/bin/env bash

stdin_is_tty() { [[ -t 0 ]]; }

kickstart_is_expected() {
    local dir=$1 remote
    [[ -d "$dir/.git" ]] || return 1
    remote="$(git -C "$dir" config --get remote.origin.url || true)"
    [[ "$remote" == https://github.com/nvim-lua/kickstart.nvim.git || "$remote" == git@github.com:nvim-lua/kickstart.nvim.git ]]
}

install_kickstart() {
    local config="$REAL_HOME/.config/nvim" stamp path backup_root tool
    install_required_group "Kickstart.nvim prerequisites" gcc git unzip neovim
    for tool in rg fd tree-sitter; do
        brew_tool_present "$tool" || {
            err "Kickstart.nvim requires the Homebrew tool: ${tool}"
            return 1
        }
    done
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
    PATH="$(brew_bin_dir):$PATH" nvim --headless '+qa'
}

offer_kickstart() {
    if ! install_kickstart; then
        warn "Optional Kickstart.nvim installation failed"
        OPTIONAL_FAILURES+=("Kickstart.nvim")
    fi
}

install_optional_dms_plugins() {
    local plugin output
    if ! output="$(dms_cmd plugins list)"; then
        warn "Could not list installed DMS plugins; skipping optional plugin installation"
        OPTIONAL_FAILURES+=("DMS plugin discovery")
        return 0
    fi
    printf '%s\n' "$output"
    for plugin in codexBar wallpaperDiscovery; do
        info "Third-party DMS registry plugin: ${plugin} (review the source and dependencies shown by DMS)."
        if grep -Eq "^[[:space:]]*ID:[[:space:]]+${plugin}[[:space:]]*$" <<<"$output"; then
            log "DMS plugin already installed: ${plugin}"
        elif ! dms_cmd plugins install "$plugin"; then
            warn "Optional DMS plugin failed: ${plugin}"
            OPTIONAL_FAILURES+=("DMS plugin ${plugin}")
        fi
    done
}

offer_dms_plugins() {
    if ! stdin_is_tty; then
        info "Non-interactive setup: skipping optional DMS plugins"
        OPTIONAL_SKIPPED+=("DMS plugins")
        return 0
    fi
    install_optional_dms_plugins
}

run_optional_phase() {
    step "Finishing touches"
    offer_kickstart
    offer_dms_plugins
}

print_summary() {
    printf '\n%b\n' "${GREEN}${BOLD}All done!${NC}"
    printf '%s\n' "Your Niri desktop is ready. Reboot to start your graphical session and activate Docker group membership."
    ((${#OPTIONAL_SKIPPED[@]})) && info "Skipped: ${OPTIONAL_SKIPPED[*]}"
    ((${#OPTIONAL_FAILURES[@]})) && warn "Failed (non-fatal): ${OPTIONAL_FAILURES[*]}"
    printf '\n%b\n' "${BOLD}After your first login:${NC}"
    printf '%s\n' "  • Set the eDP-1 display scale to 1.67 in DMS settings"
    printf '%s\n' "  • Enable dockerToggle in DMS Plugins and add it to the right side of DankBar"
    printf '%s\n' "  • Docker group is root-equivalent — don't add untrusted users"
    printf '\n'
}
