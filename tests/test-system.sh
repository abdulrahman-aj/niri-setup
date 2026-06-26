#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "DNF, time format, Chrome, debloat, core packages, Homebrew ownership"

test_dnf_settings_are_replaced_once() {
    local file; file="$(make_tempfile)"
    printf '[main]\nmax_parallel_downloads=3\nmax_parallel_downloads=5\ndefaultyes=False\n' >"$file"
    (
        DNF_CONF="$file"
        s() { "$@"; }
        optimize_dnf
    ) &>/dev/null || return 1
    [[ "$(grep -c '^max_parallel_downloads=10$' "$file")" -eq 1 ]]
    [[ "$(grep -c '^defaultyes=True$' "$file")" -eq 1 ]]
}

test_time_format_sets_lc_time_once() {
    local dir calls; dir="$(make_tempdir)"; calls="$(make_tempfile)"
    printf 'LANG=ar_JO.UTF-8\n' >"$dir/locale.conf"
    (
        LOCALE_CONF="$dir/locale.conf"
        s() {
            printf '%s\n' "$*" >>"$calls"
            [[ "$1 $2 $3" == 'localectl set-locale LC_TIME=en_US.UTF-8' ]] && printf 'LC_TIME=en_US.UTF-8\n' >>"$dir/locale.conf"
        }
        configure_time_format
    ) &>/dev/null || return 1
    grep -Fxq 'localectl set-locale LC_TIME=en_US.UTF-8' "$calls" || return 1
    : >"$calls"
    (
        LOCALE_CONF="$dir/locale.conf"
        configure_time_format
    ) &>/dev/null || return 1
    [[ ! -s "$calls" ]]
    printf 'LANG=en_US.UTF-8\n' >"$dir/locale.conf"
    (
        LOCALE_CONF="$dir/locale.conf"
        configure_time_format
    ) &>/dev/null || return 1
    [[ ! -s "$calls" ]]
}

test_chrome_uses_fedora_managed_repository() {
    local calls; calls="$(make_tempfile)"
    (
        rpm() { return 1; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        have_command() { [[ "$1" == xdg-settings ]]; }
        xdg-settings() {
            [[ "$1" == set ]] || printf 'google-chrome.desktop\n'
        }
        install_chrome
    ) &>/dev/null
    assert_ok grep -Fxq 'dnf install -y fedora-workstation-repositories' "$calls"
    assert_ok grep -Fxq 'dnf config-manager enable google-chrome' "$calls"
    assert_ok grep -Fxq 'dnf install -y google-chrome-stable' "$calls"
    assert_file_lacks "$calls" 'addrepo'
}

test_existing_chrome_skips_package_install() {
    local calls; calls="$(make_tempfile)"
    (
        rpm() { return 0; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        have_command() { [[ "$1" == xdg-settings ]]; }
        xdg-settings() { [[ "$1" == set ]] || printf 'google-chrome.desktop\n'; }
        install_chrome
    ) &>/dev/null
    assert_eq "$(cat "$calls")" 'dnf config-manager enable google-chrome'
}

test_debloat_allowlist_only() {
    local actual
    actual="$({
        rpm() { printf '%s\n' firefox firefox-langpacks libreoffice-core gnome-tour gnome-shell gdm nautilus kernel; }
        installed_debloat_packages
    })"
    [[ "$actual" == $'firefox\nfirefox-langpacks\nlibreoffice-core\ngnome-tour' ]]
}

test_debloat_noop_when_absent() {
    (
        rpm() { printf '%s\n' nautilus kernel; }
        s() { return 1; }
        debloat_system
    ) &>/dev/null
}

test_core_packages_include_essentials_and_exclude_bootstrap() {
    # Fear: an essential silently drops out, or a bootstrap-only/unwanted package
    # creeps into the core set. Assert those invariants, not the verbatim list.
    local pkg
    for pkg in alacritty xdg-terminal-exec xwayland-satellite wl-clipboard fish; do
        [[ " ${CORE_PACKAGES[*]} " == *" $pkg "* ]] || fail_assert "CORE_PACKAGES missing essential: $pkg"
    done
    for pkg in git pciutils unrar; do
        [[ " ${CORE_PACKAGES[*]} " != *" $pkg "* ]] || fail_assert "CORE_PACKAGES should not contain: $pkg"
    done
    [[ "$(declare -f install_kickstart)" != *'fd-find'* ]] || fail_assert "install_kickstart references fd-find"
}

test_brew_owns_portable_cli_tools() {
    local formula bin
    for formula in jq stow fd ripgrep tree-sitter-cli bat eza; do
        [[ " ${BREW_FORMULAE[*]} " == *" $formula "* ]] || return 1
    done
    [[ " ${BREW_FORMULAE[*]} " == *" steipete/tap/codexbar " ]] || return 1
    bin="$(make_tempdir)"
    printf '#!/usr/bin/env bash\nprintf jq-from-brew\n' >"$bin/jq"; chmod +x "$bin/jq"
    printf '#!/usr/bin/env bash\nprintf make-from-brew\n' >"$bin/make"; chmod +x "$bin/make"
    brew_bin_dir() { printf '%s\n' "$bin"; }
    [[ "$(jq_cmd 2>/dev/null)" == jq-from-brew ]] || return 1
    [[ "$(make_cmd 2>/dev/null)" == make-from-brew ]]
}

run_test "DNF settings are replaced without duplicates" test_dnf_settings_are_replaced_once
run_test "time format is pinned to 12-hour locale semantics" test_time_format_sets_lc_time_once
run_test "Chrome uses Fedora's managed repository" test_chrome_uses_fedora_managed_repository
run_test "existing Chrome skips package installation" test_existing_chrome_skips_package_install
run_test "debloat removes only explicitly selected packages" test_debloat_allowlist_only
run_test "debloat is a no-op when selected packages are absent" test_debloat_noop_when_absent
run_test "core packages include essentials and exclude bootstrap-only" test_core_packages_include_essentials_and_exclude_bootstrap
run_test "portable CLI tools are provided by Homebrew" test_brew_owns_portable_cli_tools

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
