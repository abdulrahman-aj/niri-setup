#!/usr/bin/env bash

core_stack_complete() { have_command dms && have_command niri; }
dms_cmd() { DMS_PRIVESC=sudo dms "$@"; }

run_dankinstall() {
    local tempdir archive installer
    core_stack_complete && { log "DMS and Niri are already installed"; return 0; }
    tempdir="$(mktemp -d)"
    archive="$tempdir/dankinstall.gz"
    installer="$tempdir/dankinstall"
    trap 'rm -rf "${tempdir:-}"; trap - RETURN' RETURN
    download_and_verify "$DANKINSTALL_URL" "$DANKINSTALL_SHA256" "$archive" || return 1
    gzip -dc "$archive" >"$installer"
    chmod +x "$installer"
    info "DankInstall is interactive; select Niri in the TUI."
    DMS_PRIVESC=sudo "$installer"
    core_stack_complete || {
        err "DankInstall finished without the complete desktop stack."
        return 1
    }
}

install_dms_greeter() {
    have_command dms-greeter || s dnf install -y dms-greeter
    if ! dms_cmd greeter status &>/dev/null; then
        dms_cmd greeter enable
    fi
    dms_cmd greeter sync -y
    dms_cmd greeter status
    log "dms-greeter is configured and synced"
}

apply_dms_settings_override() {
    local settings="$REAL_HOME/.config/DankMaterialShell/settings.json"
    local override="${DMS_SETTINGS_OVERRIDE:-$ROOT_DIR/assets/dms-settings-override.json}" generated
    [[ -f "$settings" ]] || { err "DMS settings do not exist: ${settings}"; return 1; }
    [[ -f "$override" ]] || { err "DMS settings override does not exist: ${override}"; return 1; }
    jq_cmd -e 'type == "object"' "$settings" &>/dev/null || {
        err "DMS settings must contain a valid JSON object: ${settings}"
        return 1
    }
    jq_cmd -e 'type == "object"' "$override" &>/dev/null || {
        err "DMS settings override must contain a valid JSON object: ${override}"
        return 1
    }
    generated="$(mktemp)"
    trap 'rm -f "${generated:-}"; trap - RETURN' RETURN
    jq_cmd -s '.[0] * .[1]' "$settings" "$override" >"$generated" || {
        err "Failed to merge DMS settings."
        return 1
    }
    install_file_atomically_with_backup "$generated" "$settings"
    log "Repository-managed DMS settings applied"
}

install_core_packages() {
    install_required_group "workstation essentials" "${CORE_PACKAGES[@]}"
}

install_niri_fish_completions() {
    local destination="${NIRI_FISH_COMPLETION_FILE:-$REAL_HOME/.local/share/fish/vendor_completions.d/niri.fish}"
    local generated
    generated="$(mktemp)"
    trap 'rm -f "${generated:-}"; trap - RETURN' RETURN
    niri completions fish >"$generated" || {
        err "Failed to generate Niri Fish completions."
        return 1
    }
    if [[ ! -s "$generated" ]] || ! grep -Fq 'complete -c niri' "$generated" || ! fish -n "$generated"; then
        err "Generated Niri Fish completions are invalid."
        return 1
    fi
    install_generated_file_atomically "$generated" "$destination"
    log "Niri Fish completions installed"
}

configure_xdg_terminal() {
    local file="$REAL_HOME/.config/xdg-terminals.list" temp
    temp="$(mktemp)"
    printf '%s\n' Alacritty.desktop >"$temp"
    install_file_with_backup "$temp" "$file"
    rm -f "$temp"
    [[ "$(xdg-terminal-exec --print-id)" == Alacritty.desktop ]] || {
        err "Alacritty is not selected by xdg-terminal-exec."
        return 1
    }
}

user_systemctl_cmd() { systemctl --user "$@"; }

install_niri_edge_indicators() {
    local config="$REAL_HOME/.config/quickshell/niri-edge-indicators"
    local service="$REAL_HOME/.config/systemd/user/niri-edge-indicators.service"
    install_symlink_with_backup "$ROOT_DIR/assets/niri-edge-indicators" "$config"
    install_symlink_with_backup "$ROOT_DIR/assets/niri-edge-indicators.service" "$service"
    user_systemctl_cmd daemon-reload
    user_systemctl_cmd enable --now niri-edge-indicators.service
    log "Niri edge indicators installed"
}

ensure_niri_override_include() {
    local file=$1 generated body
    generated="$(mktemp)"
    # Drop any existing override include, then re-append it last. Command
    # substitution trims trailing newlines so repeated runs stay idempotent
    # (otherwise the leading "\n" accumulates a blank line on every run).
    body="$(sed '/^[[:space:]]*include[[:space:]]*"niri-overrides.kdl"[[:space:]]*$/d' "$file")"
    printf '%s\n\ninclude "niri-overrides.kdl"\n' "$body" >"$generated"
    if ! cmp -s "$generated" "$file"; then
        backup_path "$file"
        install -m 0644 "$generated" "$file"
    fi
    rm -f "$generated"
}

configure_niri() {
    local dir="$REAL_HOME/.config/niri" config override snapshot
    local existed_override=0
    config="$dir/config.kdl"
    override="$dir/niri-overrides.kdl"
    [[ -f "$config" ]] || { err "Niri config does not exist: ${config}"; return 1; }
    snapshot="$(mktemp -d)"
    trap 'rm -rf "${snapshot:-}"; trap - RETURN' RETURN
    cp -a "$config" "$snapshot/config.kdl"
    if [[ -f "$override" ]]; then
        cp -a "$override" "$snapshot/override.kdl"
        existed_override=1
    fi
    install_symlink_with_backup "$ROOT_DIR/assets/niri-overrides.kdl" "$override"
    ensure_niri_override_include "$config"
    if ! niri validate -c "$config"; then
        cp -a "$snapshot/config.kdl" "$config"
        if ((existed_override)); then
            rm -rf -- "$override"
            cp -a "$snapshot/override.kdl" "$override"
        else
            rm -f "$override"
        fi
        err "Niri validation failed; changed Niri files were restored."
        return 1
    fi
}

create_xdg_dirs() { have_command xdg-user-dirs-update && xdg-user-dirs-update; }

set_graphical_target() {
    [[ "$(systemctl get-default)" == graphical.target ]] || s systemctl set-default graphical.target
}
