#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/setup.sh"

TESTS_RUN=0
TESTS_FAILED=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s: %s\n' "$1" "$2"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

run_test() {
    local name=$1
    shift
    TESTS_RUN=$((TESTS_RUN + 1))
    if ( TMP_PATHS=(); trap '(( ${#TMP_PATHS[@]} )) && rm -rf "${TMP_PATHS[@]}"' EXIT; "$@" ); then
        pass "$name"
    else
        fail "$name" "assertion failed"
    fi
}

# Temp fixtures: register every path so run_test's trap removes it (even on early
# assert exit), so tests never need their own cleanup.
make_tempdir()  { local d; d="$(mktemp -d)"; TMP_PATHS+=("$d"); printf '%s' "$d"; }
make_tempfile() { local f; f="$(mktemp)";    TMP_PATHS+=("$f"); printf '%s' "$f"; }
with_dms_home() {
    local home; home="$(make_tempdir)"
    mkdir -p "$home/.config/DankMaterialShell"
    printf '%s\n' "${1:-{}}" >"$home/.config/DankMaterialShell/settings.json"
    printf '%s' "$home"
}

# Assertions: print context and exit the test subshell on failure, so every assertion
# binds without needing `set -e` or `|| return 1`.
section() { printf '\n%b[%s]%b %s\n\n' "$BOLD" "$(basename "$0")" "$NC" "$1"; }

fail_assert()          { printf 'assert failed: %s\n' "$1" >&2; exit 1; }
assert_eq()            { [[ "$1" == "$2" ]] || fail_assert "expected '$2', got '$1'"; }
assert_contains()      { [[ "$1" == *"$2"* ]] || fail_assert "missing '$2' in '$1'"; }
assert_file_contains() { grep -Fq -- "$2" "$1" || fail_assert "$1 missing '$2'"; }
assert_file_lacks()    { if grep -Fq -- "$2" "$1"; then fail_assert "$1 unexpectedly has '$2'"; fi; }
assert_ok()            { "$@" || fail_assert "command failed: $*"; }
assert_fails()         { if "$@"; then fail_assert "unexpected success: $*"; fi; }
