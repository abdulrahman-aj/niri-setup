#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "DMS plugins"

test_non_tty_skips_dms_plugins() {
    (
        OPTIONAL_SKIPPED=()
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 1; }
        install_optional_dms_plugins() { return 1; }
        offer_dms_plugins
        [[ "${OPTIONAL_SKIPPED[*]}" == 'DMS plugins' ]]
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 0 ]]
    ) &>/dev/null
}

test_dms_plugins_install_in_tty() {
    local calls; calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 0; }
        dms() {
            [[ "$*" == 'plugins list' ]] || printf '%s\n' "$*" >>"$calls"
        }
        offer_dms_plugins
    ) &>/dev/null
    assert_eq "$(grep -c '^plugins install ' "$calls")" 1
    assert_ok grep -Fxq 'plugins install codexBar' "$calls"
    assert_file_lacks "$calls" 'wallpaperDiscovery'
    assert_file_lacks "$calls" 'dockerManager'
}

test_existing_dms_plugins_are_skipped() {
    local calls; calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        dms() {
            if [[ "$*" == 'plugins list' ]]; then
                printf '  CodexBar\n    ID: codexBar\n'
            else
                printf '%s\n' "$*" >>"$calls"
            fi
        }
        install_optional_dms_plugins
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 0 ]]
    ) &>/dev/null || return 1
    ! grep -Fq 'plugins install' "$calls" || return 1
}

test_failed_dms_plugin_list_skips_installation() {
    local calls; calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        dms() {
            printf '%s\n' "$*" >>"$calls"
            return 1
        }
        install_optional_dms_plugins
        [[ "${OPTIONAL_FAILURES[*]}" == 'DMS plugin discovery' ]]
    ) &>/dev/null || return 1
    [[ "$(cat "$calls")" == 'plugins list' ]]
}

test_plugin_failures_are_nonfatal() {
    (
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 0; }
        dms() { [[ "$*" == 'plugins list' ]]; }
        offer_dms_plugins
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 1 ]]
    ) &>/dev/null
}

run_test "non-TTY setup skips DMS plugins" test_non_tty_skips_dms_plugins
run_test "DMS plugins install in TTY mode" test_dms_plugins_install_in_tty
run_test "existing DMS plugins are skipped" test_existing_dms_plugins_are_skipped
run_test "failed DMS plugin listing skips installation" test_failed_dms_plugin_list_skips_installation
run_test "DMS plugin failures do not fail core setup" test_plugin_failures_are_nonfatal

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
