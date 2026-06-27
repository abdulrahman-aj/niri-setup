#!/usr/bin/env bash

stdin_is_tty() { [[ -t 0 ]]; }

install_optional_dms_plugins() {
    local plugin output
    if ! output="$(dms_cmd plugins list)"; then
        warn "Could not list installed DMS plugins; skipping optional plugin installation"
        OPTIONAL_FAILURES+=("DMS plugin discovery")
        return 0
    fi
    printf '%s\n' "$output"
    # shellcheck disable=SC2043
    for plugin in codexBar; do
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
    offer_dms_plugins
}

print_summary() {
    printf '\n%b\n' "${GREEN}${BOLD}All done!${NC}"
    printf '%s\n' "Your Niri desktop is ready. Reboot to start your graphical session and activate Docker group membership."
    ((${#OPTIONAL_SKIPPED[@]})) && info "Skipped: ${OPTIONAL_SKIPPED[*]}"
    ((${#OPTIONAL_FAILURES[@]})) && warn "Failed (non-fatal): ${OPTIONAL_FAILURES[*]}"
    printf '\n%b\n' "${BOLD}After your first login:${NC}"
    printf '%s\n' "  • Set up your dotfiles"
    printf '%s\n' "  • Set eDP-1 scale to 1.67 in DMS Display settings, then reboot"
    printf '%s\n' "  • Verify: Chrome opens desktop links; Alacritty is the default terminal"
    printf '%s\n' "  • Verify: GitHub auth, SSH fetch, and push work"
    printf '%s\n' "  • Verify: Docker inactive after reboot; DMS widget toggles it; hello-world works without sudo"
    printf '%s\n' "  • Verify: Niri loads clean; scaling, keybindings, Arabic switch, Nerd Font all work"
    printf '%s\n' "  • Verify: CLI tools available in a fresh Fish shell (zoxide cd, starship prompt)"
    printf '\n'
}
