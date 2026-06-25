#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Kickstart.nvim, DMS plugins"

test_non_tty_installs_kickstart_and_skips_plugins() {
    local calls; calls="$(make_tempfile)"
    (
        OPTIONAL_SKIPPED=()
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 1; }
        install_kickstart() { printf 'kickstart\n' >>"$calls"; }
        install_optional_dms_plugins() { return 1; }
        offer_kickstart
        offer_dms_plugins
        [[ "${OPTIONAL_SKIPPED[*]}" == 'DMS plugins' ]]
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 0 ]]
    ) &>/dev/null || return 1
    [[ "$(cat "$calls")" == kickstart ]] || return 1
}

test_kickstart_dependencies_are_split_and_exposed() {
    local home calls; home="$(make_tempdir)"; calls="$(make_tempfile)"
    mkdir -p "$home/.config/nvim/.git"
    (
        REAL_HOME="$home"
        install_required_group() { printf 'dnf:%s\n' "$*" >>"$calls"; }
        kickstart_is_expected() { return 0; }
        brew_tool_present() { [[ "$1" == rg || "$1" == fd || "$1" == tree-sitter ]]; }
        brew_bin_dir() { printf '/brew/bin\n'; }
        nvim() { printf 'nvim:%s:path=%s\n' "$*" "$PATH" >>"$calls"; }
        install_kickstart
    ) &>/dev/null || return 1
    grep -Fxq 'dnf:Kickstart.nvim prerequisites gcc git unzip neovim' "$calls" || return 1
    grep -Fq 'nvim:--headless +qa:path=/brew/bin:' "$calls" || return 1
    if (
        REAL_HOME="$home"
        install_required_group() { :; }
        brew_tool_present() { [[ "$1" != tree-sitter ]]; }
        install_kickstart
    ) &>/dev/null; then
        return 1
    fi
}

test_kickstart_failure_is_nonfatal() {
    (
        OPTIONAL_FAILURES=()
        install_kickstart() { return 1; }
        offer_kickstart
        [[ "${OPTIONAL_FAILURES[*]}" == 'Kickstart.nvim' ]]
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
    assert_eq "$(grep -c '^plugins install ' "$calls")" 2
    assert_ok grep -Fxq 'plugins install codexBar' "$calls"
    assert_ok grep -Fxq 'plugins install wallpaperDiscovery' "$calls"
    assert_file_lacks "$calls" 'dockerManager'
}

test_existing_dms_plugins_are_skipped() {
    local calls; calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        dms() {
            if [[ "$*" == 'plugins list' ]]; then
                printf '  CodexBar\n    ID: codexBar\n  Wallpaper Discovery\n    ID: wallpaperDiscovery\n'
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
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 2 ]]
    ) &>/dev/null
}

run_test "non-TTY setup installs Kickstart and skips DMS plugins" test_non_tty_installs_kickstart_and_skips_plugins
run_test "Kickstart dependencies are split between Fedora and Homebrew" test_kickstart_dependencies_are_split_and_exposed
run_test "Kickstart failure does not fail core setup" test_kickstart_failure_is_nonfatal
run_test "DMS plugins install in TTY mode" test_dms_plugins_install_in_tty
run_test "existing DMS plugins are skipped" test_existing_dms_plugins_are_skipped
run_test "failed DMS plugin listing skips installation" test_failed_dms_plugin_list_skips_installation
run_test "DMS plugin failures do not fail core setup" test_plugin_failures_are_nonfatal

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
