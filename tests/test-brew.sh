#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Homebrew, brew formulae, mise"

test_install_homebrew_script() {
    local dir fake_brew
    dir="$(make_tempdir)"; fake_brew="$dir/brew"
    printf '%s\n' '#!/usr/bin/env bash' \
        "printf '#!/usr/bin/env bash\n' >'$fake_brew'" \
        "chmod +x '$fake_brew'" >"$dir/curl"
    chmod +x "$dir/curl"

    env HOME="$dir" BREW_BIN="$fake_brew" PATH="$dir:$PATH" \
        bash "$ROOT_DIR/bin/install-homebrew" &>/dev/null || return 1
    [[ -x "$fake_brew" ]] || return 1
    assert_file_contains "$dir/.bashrc" '/home/linuxbrew/.linuxbrew/bin/brew shellenv'

    local before; before="$(wc -l <"$dir/.bashrc")"
    env HOME="$dir" BREW_BIN="$fake_brew" PATH="/usr/bin:/bin" \
        bash "$ROOT_DIR/bin/install-homebrew" &>/dev/null || return 1
    assert_eq "$(wc -l <"$dir/.bashrc")" "$before"
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

run_test "install-homebrew installs binary and sets up .bashrc idempotently" test_install_homebrew_script
run_test "Brew installs only missing formulae" test_brew_installs_only_missing_formulae
run_test "Mise installs only missing global tools" test_mise_installs_only_missing_tools

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
