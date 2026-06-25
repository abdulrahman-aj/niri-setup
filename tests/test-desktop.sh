#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "DankInstall, DMS greeter/commands/settings, Niri config, edge indicators, xdg-terminal"

test_dankinstall_selects_sudo_without_exporting_it() {
    local dir marker observed
    dir="$(make_tempdir)"; marker="$dir/stack-complete"; observed="$dir/privesc"
    (
        export STACK_MARKER="$marker" DMS_PRIVESC_CAPTURE="$observed"
        unset DMS_PRIVESC
        core_stack_complete() { [[ -f "$marker" ]]; }
        curl() {
            local output=""
            while (($#)); do
                if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi
            done
            : >"$output"
        }
        verify_checksum() { return 0; }
        gzip() {
            [[ "$1" == -dc ]]
            printf '%s\n' \
                '#!/usr/bin/env bash' \
                'printf "%s\n" "${DMS_PRIVESC:-unset}" >"$DMS_PRIVESC_CAPTURE"' \
                'touch "$STACK_MARKER"'
        }
        run_dankinstall
        [[ -z "${DMS_PRIVESC+x}" ]]
    ) &>/dev/null || return 1
    [[ "$(cat "$observed")" == sudo ]]
}

test_greeter_healthy_skips_repair() {
    local calls; calls="$(make_tempfile)"
    (
        have_command() { return 0; }
        dms() { printf '%s\n' "$*" >>"$calls"; }
        s() { return 99; }
        install_dms_greeter
    ) &>/dev/null || return 1
    ! grep -q '^greeter enable$' "$calls" || return 1
    [[ "$(grep -c '^greeter sync -y$' "$calls")" -eq 1 ]]
}

test_greeter_repairs_failed_status() {
    local calls; calls="$(make_tempfile)"
    (
        have_command() { return 0; }
        dms() {
            printf '%s\n' "$*" >>"$calls"
            if [[ "$*" == 'greeter status' ]]; then
                [[ "$(grep -c '^greeter status$' "$calls")" -gt 1 ]]
            fi
        }
        install_dms_greeter
    ) &>/dev/null || return 1
    grep -q '^greeter enable$' "$calls"
    grep -q '^greeter sync -y$' "$calls"
}

test_dms_commands_select_sudo_and_forward_status() {
    local calls; calls="$(make_tempfile)"
    (
        unset DMS_PRIVESC
        dms() {
            printf '%s|%s\n' "${DMS_PRIVESC:-unset}" "$*" >>"$calls"
            [[ "$1" != fail ]]
        }
        dms_cmd greeter sync -y
        if dms_cmd fail; then return 1; fi
        [[ -z "${DMS_PRIVESC+x}" ]]
    ) || return 1
    [[ "$(cat "$calls")" == $'sudo|greeter sync -y\nsudo|fail' ]]
}

test_dms_settings_override_merges_and_is_idempotent() {
    local home override before
    home="$(make_tempdir)"; override="$(make_tempfile)"
    mkdir -p "$home/.config/DankMaterialShell"
    printf '{"keep":1,"nested":{"keep":1,"change":1},"array":[1],"use24HourClock":true}\n' >"$home/.config/DankMaterialShell/settings.json"
    printf '{"nested":{"change":2},"array":[2],"use24HourClock":false}\n' >"$override"
    (
        REAL_HOME="$home"
        DMS_SETTINGS_OVERRIDE="$override"
        apply_dms_settings_override
    ) &>/dev/null || return 1
    jq -e '.keep == 1 and .nested == {"keep":1,"change":2} and .array == [2] and .use24HourClock == false' \
        "$home/.config/DankMaterialShell/settings.json" &>/dev/null || return 1
    before="$(find "$home/.config/DankMaterialShell" -name 'settings.json.backup-*' | wc -l)"
    (
        REAL_HOME="$home"
        DMS_SETTINGS_OVERRIDE="$override"
        apply_dms_settings_override
    ) &>/dev/null || return 1
    [[ "$(find "$home/.config/DankMaterialShell" -name 'settings.json.backup-*' | wc -l)" -eq "$before" ]]
}

test_dms_settings_override_hides_lock_screen_media_player() {
    local override="$ROOT_DIR/assets/dms-settings-override.json"
    jq -e '.lockScreenShowMediaPlayer == false' "$override" &>/dev/null
}

test_dms_settings_override_freezes_dankbar_layout() {
    local override="$ROOT_DIR/assets/dms-settings-override.json"
    jq -e 'type == "object" and (.barConfigs | type == "array") and (.barConfigs | length == 1)' "$override" &>/dev/null || return 1
    jq -e '
        (.barConfigs[0]) as $b
        | ($b.rightWidgets | map(if type == "object" then .id else . end)) as $right
        | ($b.leftWidgets | index("workspaceSwitcher")) != null
          and ($right | index("dockerToggle")) != null
          and ($right | index("keyboard_layout_name")) != null
          and ($right | index("controlCenterButton")) != null
    ' "$override" &>/dev/null
}

test_invalid_dms_json_preserves_settings() {
    local home override digest missing
    home="$(make_tempdir)"; override="$(make_tempfile)"
    mkdir -p "$home/.config/DankMaterialShell"
    printf '{"keep":true}\n' >"$home/.config/DankMaterialShell/settings.json"
    printf '[]\n' >"$override"
    digest="$(sha256sum "$home/.config/DankMaterialShell/settings.json")"
    if (REAL_HOME="$home" DMS_SETTINGS_OVERRIDE="$override" apply_dms_settings_override) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$home/.config/DankMaterialShell/settings.json")" == "$digest" ]]
    printf '{invalid\n' >"$home/.config/DankMaterialShell/settings.json"
    printf '{}\n' >"$override"
    digest="$(sha256sum "$home/.config/DankMaterialShell/settings.json")"
    if (REAL_HOME="$home" DMS_SETTINGS_OVERRIDE="$override" apply_dms_settings_override) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$home/.config/DankMaterialShell/settings.json")" == "$digest" ]] || return 1
    missing="$home/missing-override.json"
    printf '{"keep":true}\n' >"$home/.config/DankMaterialShell/settings.json"
    digest="$(sha256sum "$home/.config/DankMaterialShell/settings.json")"
    if (REAL_HOME="$home" DMS_SETTINGS_OVERRIDE="$missing" apply_dms_settings_override) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$home/.config/DankMaterialShell/settings.json")" == "$digest" ]]
}

test_niri_override_neutralizes_dangerous_defaults() {
    # Fear: a surprising/destructive default bind survives, or a window rule forces
    # fullscreen. The non-destructive nav/app shortcuts are not mirrored here.
    local override="$ROOT_DIR/assets/niri-overrides.kdl"
    assert_file_contains "$override" 'Mod+Q hotkey-overlay-title=null { spawn "true"; }'
    assert_file_contains "$override" 'Mod+D hotkey-overlay-title=null { spawn "true"; }'
    assert_file_contains "$override" 'Mod+W repeat=false hotkey-overlay-title="Close Window" { close-window; }'
    assert_file_lacks "$override" 'open-fullscreen true'
}

test_edge_indicator_wiring() {
    # Fear: the edge indicator regresses its show-when-scrollable logic or its
    # click/hover wiring (the clickability already broke once).
    local indicator="$ROOT_DIR/assets/niri-edge-indicators/shell.qml"
    assert_file_contains "$indicator" 'focusedColumn > 1'
    assert_file_contains "$indicator" 'focusedColumn < maximumColumn'
    assert_file_contains "$indicator" 'cursorShape: Qt.PointingHandCursor'
    assert_file_contains "$indicator" 'hover.containsMouse'
    assert_file_contains "$indicator" 'focus-column-left'
    assert_file_contains "$indicator" 'focus-column-right'
}

test_niri_edge_indicators_are_installed_idempotently() {
    local home calls
    home="$(make_tempdir)"; calls="$(make_tempfile)"
    (
        REAL_HOME="$home"
        user_systemctl_cmd() { printf '%s\n' "$*" >>"$calls"; }
        install_niri_edge_indicators
        install_niri_edge_indicators
    ) &>/dev/null || return 1
    [[ "$(readlink "$home/.config/quickshell/niri-edge-indicators")" == "$ROOT_DIR/assets/niri-edge-indicators" ]] || return 1
    [[ "$(readlink "$home/.config/systemd/user/niri-edge-indicators.service")" == "$ROOT_DIR/assets/niri-edge-indicators.service" ]] || return 1
    [[ "$(grep -c '^daemon-reload$' "$calls")" -eq 2 ]] || return 1
    [[ "$(grep -c '^enable --now niri-edge-indicators.service$' "$calls")" -eq 2 ]] || return 1
    [[ "$(find "$home" -name '*.backup-*' | wc -l)" -eq 0 ]]
}

test_niri_include_is_last_and_idempotent() {
    local home file before
    home="$(make_tempdir)"; file="$home/config.kdl"
    printf 'include "dms/a.kdl"\ninclude "niri-overrides.kdl"\nbinds {}\n' >"$file"
    ( backup_path() { :; }; ensure_niri_override_include "$file" )
    assert_eq "$(grep -c 'include "niri-overrides.kdl"' "$file")" 1
    assert_eq "$(tail -n 1 "$file")" 'include "niri-overrides.kdl"'
    before="$(sha256sum "$file")"
    ( backup_path() { return 1; }; ensure_niri_override_include "$file" )
    assert_eq "$before" "$(sha256sum "$file")"
}

test_niri_validation_failure_rolls_back() {
    local home original
    home="$(make_tempdir)"; mkdir -p "$home/.config/niri/dms"
    printf 'include "dms/layout.kdl"\n' >"$home/.config/niri/config.kdl"
    printf 'output "eDP-1" { scale 1.0 }\n' >"$home/.config/niri/dms/outputs.kdl"
    printf 'old override\n' >"$home/.config/niri/niri-overrides.kdl"
    original="$(sha256sum "$home/.config/niri/config.kdl" "$home/.config/niri/dms/outputs.kdl" "$home/.config/niri/niri-overrides.kdl")"
    if ( REAL_HOME="$home"; backup_path() { :; }; niri() { return 1; }; configure_niri ) &>/dev/null; then
        return 1
    fi
    [[ "$original" == "$(sha256sum "$home/.config/niri/config.kdl" "$home/.config/niri/dms/outputs.kdl" "$home/.config/niri/niri-overrides.kdl")" ]]
}

test_niri_success_does_not_touch_outputs() {
    local home before override
    home="$(make_tempdir)"; mkdir -p "$home/.config/niri/dms"
    printf 'include "dms/layout.kdl"\n' >"$home/.config/niri/config.kdl"
    printf 'output "eDP-1" { scale 1.25 }\n' >"$home/.config/niri/dms/outputs.kdl"
    before="$(sha256sum "$home/.config/niri/dms/outputs.kdl")"
    (
        REAL_HOME="$home"
        backup_path() { :; }
        niri() { return 0; }
        configure_niri
    )
    override="$home/.config/niri/niri-overrides.kdl"
    assert_eq "$before" "$(sha256sum "$home/.config/niri/dms/outputs.kdl")"
    [[ -L "$override" ]] || fail_assert "niri-overrides.kdl is not a symlink"
    assert_eq "$(readlink "$override")" "$ROOT_DIR/assets/niri-overrides.kdl"
    assert_file_contains "$override" 'layout "us,ara"'
    assert_file_contains "$override" 'options "grp:alt_shift_toggle"'
}

test_xdg_terminal_selects_alacritty() {
    local home; home="$(make_tempdir)"
    (
        REAL_HOME="$home"
        xdg-terminal-exec() { [[ "$1" == --print-id ]] && printf 'Alacritty.desktop\n'; }
        configure_xdg_terminal
    )
    grep -Fxq Alacritty.desktop "$home/.config/xdg-terminals.list"
}

run_test "DankInstall selects sudo without exporting it" test_dankinstall_selects_sudo_without_exporting_it
run_test "healthy greeter skips repair" test_greeter_healthy_skips_repair
run_test "unhealthy greeter is repaired" test_greeter_repairs_failed_status
run_test "DMS commands select sudo and forward status" test_dms_commands_select_sudo_and_forward_status
run_test "DMS settings override merges safely and idempotently" test_dms_settings_override_merges_and_is_idempotent
run_test "DMS settings override hides lock screen media player" test_dms_settings_override_hides_lock_screen_media_player
run_test "DMS settings override freezes the DankBar layout" test_dms_settings_override_freezes_dankbar_layout
run_test "invalid DMS JSON preserves existing settings" test_invalid_dms_json_preserves_settings
run_test "Niri override neutralizes dangerous default binds" test_niri_override_neutralizes_dangerous_defaults
run_test "edge indicator show-logic and click/hover wiring" test_edge_indicator_wiring
run_test "Niri edge indicators install idempotently" test_niri_edge_indicators_are_installed_idempotently
run_test "Niri override include is last and idempotent" test_niri_include_is_last_and_idempotent
run_test "failed Niri validation restores managed files" test_niri_validation_failure_rolls_back
run_test "successful Niri configuration leaves outputs untouched" test_niri_success_does_not_touch_outputs
run_test "Alacritty is selected through xdg-terminal-exec" test_xdg_terminal_selects_alacritty

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
