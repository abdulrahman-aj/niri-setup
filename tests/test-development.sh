#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Git, GitHub auth, Zed"

test_github_failed_login_is_fatal() {
    ! (
        gh_cmd() { return 1; }
        ensure_github_auth
    ) &>/dev/null
}

test_github_protocol_is_explicitly_set_to_ssh() {
    local calls protocol=https; calls="$(make_tempfile)"
    (
        gh_cmd() {
            printf '%s\n' "$*" >>"$calls"
            case "$*" in
                'auth status') return 0 ;;
                'config set git_protocol ssh --host github.com') protocol=ssh ;;
                'config get git_protocol --host github.com') printf '%s\n' "$protocol" ;;
            esac
        }
        ensure_github_auth
    ) &>/dev/null || return 1
    grep -Fxq 'config set git_protocol ssh --host github.com' "$calls"
    grep -Fxq 'config get git_protocol --host github.com' "$calls"
}

test_zed_installs_only_when_missing() {
    local home; home="$(make_tempdir)"
    (
        REAL_HOME="$home"
        zed_present() { [[ -x "$REAL_HOME/.local/bin/zed" ]]; }
        curl() { printf 'mkdir -p %q/.local/bin; touch %q/.local/bin/zed; chmod +x %q/.local/bin/zed\n' "$REAL_HOME" "$REAL_HOME" "$REAL_HOME"; }
        install_zed
    )
    [[ -x "$home/.local/bin/zed" ]] || fail_assert "zed not installed when missing"
}

test_git_defaults_set_main_and_identity() {
    # Fear: configure_git fails to set the default branch or an identity. The exact
    # name/email are personal data, not a behavior worth pinning verbatim.
    local calls; calls="$(make_tempfile)"
    ( git() { printf '%s\n' "$*" >>"$calls"; }; configure_git )
    assert_file_contains "$calls" 'config --global init.defaultBranch main'
    assert_file_contains "$calls" 'config --global user.name '
    assert_file_contains "$calls" 'config --global user.email '
}

run_test "failed GitHub login is fatal" test_github_failed_login_is_fatal
run_test "GitHub CLI protocol is explicitly set to SSH" test_github_protocol_is_explicitly_set_to_ssh
run_test "Zed installs only when missing" test_zed_installs_only_when_missing
run_test "Git defaults set main branch and an identity" test_git_defaults_set_main_and_identity

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
