#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Homebrew, brew formulae, mise"

test_homebrew_missing_and_healthy_branches() {
    local home calls
    home="$(make_tempdir)"; calls="$(make_tempfile)"; : >"$home/.bashrc"
    (
        REAL_HOME="$home"
        state=missing
        homebrew_present() { [[ "$state" == healthy ]]; }
        run_homebrew_installer() { printf 'installer\n' >>"$calls"; state=healthy; }
        backup_path() { :; }
        install_homebrew
    )
    assert_ok grep -Fxq installer "$calls"
    assert_file_contains "$home/.bashrc" '/home/linuxbrew/.linuxbrew/bin/brew shellenv'
    : >"$calls"
    (
        REAL_HOME="$home"
        homebrew_present() { return 0; }
        run_homebrew_installer() { return 1; }
        install_homebrew
    )
    [[ ! -s "$calls" ]] || fail_assert "installer ran when Homebrew already healthy"
}

test_brew_installs_only_missing_formulae() {
    local calls; calls="$(make_tempfile)"
    (
        brew_cmd() {
            if [[ "$1" == list ]]; then [[ "$3" != fzf && "$3" != bat && "$3" != eza && "$3" != gh && "$3" != tlrc && "$3" != zoxide && "$3" != jq && "$3" != stow && "$3" != fd && "$3" != tree-sitter-cli ]]; else printf '%s\n' "$*" >>"$calls"; fi
        }
        install_brew_formulae
    )
    grep -Fxq 'install fzf bat eza gh tlrc zoxide jq stow fd tree-sitter-cli' "$calls"
    : >"$calls"
    (
        brew_cmd() {
            [[ "$1" == list ]] || { printf '%s\n' "$*" >>"$calls"; return 1; }
        }
        install_brew_formulae
    ) || return 1
    [[ ! -s "$calls" ]] || return 1
}

test_mise_installs_only_missing_tools() {
    local calls; calls="$(make_tempfile)"
    (
        mise_cmd() {
            if [[ "$1" == current ]]; then [[ "$2" != codex ]]; else printf '%s\n' "$*" >>"$calls"; fi
        }
        install_mise_tools
    )
    assert_ok grep -Fxq 'use --global codex@latest' "$calls"
    assert_eq "$(wc -l <"$calls")" 1
}

run_test "Homebrew handles missing and healthy installations" test_homebrew_missing_and_healthy_branches
run_test "Brew installs only missing formulae" test_brew_installs_only_missing_formulae
run_test "Mise installs only missing global tools" test_mise_installs_only_missing_tools

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
