#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "GitHub auth, Zed, JetBrains fonts"

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

test_install_zed_script() {
    local dir home; dir="$(make_tempdir)"; home="$(make_tempdir)"
    printf '%s\n' '#!/usr/bin/env bash' \
        'printf "mkdir -p \"$HOME/.local/bin\"; touch \"$HOME/.local/bin/zed\"; chmod +x \"$HOME/.local/bin/zed\"\n"' \
        >"$dir/curl"
    chmod +x "$dir/curl"

    env HOME="$home" PATH="$dir:/usr/bin:/bin" \
        bash "$ROOT_DIR/bin/install-zed" &>/dev/null || return 1
    [[ -x "$home/.local/bin/zed" ]] || return 1

    local calls; calls="$(make_tempfile)"
    printf '%s\n' '#!/usr/bin/env bash' "printf 'called\n' >>\"$calls\"" >"$dir/curl"
    env HOME="$home" PATH="$dir:/usr/bin:/bin" \
        bash "$ROOT_DIR/bin/install-zed" &>/dev/null || return 1
    [[ ! -s "$calls" ]]
}

test_install_jetbrains_fonts_script() {
    local dir home fake_archive sha
    dir="$(make_tempdir)"; home="$(make_tempdir)"

    printf 'fake\n' >"$dir/FakeFont.ttf"
    fake_archive="$dir/JetBrainsMono.tar.xz"
    tar -cJf "$fake_archive" -C "$dir" "FakeFont.ttf"
    sha="$(sha256sum "$fake_archive" | cut -d' ' -f1)"

    printf '%s\n' '#!/usr/bin/env bash' \
        'while (($#)); do if [[ "$1" == -o ]]; then dest=$2; shift 2; else shift; fi; done' \
        "cp '$fake_archive' \"\$dest\"" >"$dir/curl"
    printf '%s\n' '#!/usr/bin/env bash' \
        'find "${FONT_DIR:-/nonexistent}" -name "*.ttf" 2>/dev/null | grep -q . && printf "JetBrainsMono Nerd Font\n" || printf "DejaVu Sans\n"' \
        >"$dir/fc-match"
    printf '%s\n' '#!/usr/bin/env bash' >"$dir/fc-cache"
    chmod +x "$dir/curl" "$dir/fc-match" "$dir/fc-cache"

    env HOME="$home" FONT_DIR="$home/.fonts" \
        FONT_URL="https://example.com/ignored" FONT_SHA256="$sha" \
        PATH="$dir:/usr/bin:/bin" \
        bash "$ROOT_DIR/bin/install-fonts-jetbrains" &>/dev/null || return 1
    [[ -f "$home/.fonts/FakeFont.ttf" ]] || return 1

    local calls; calls="$(make_tempfile)"
    printf '%s\n' '#!/usr/bin/env bash' "printf 'called\n' >>\"$calls\"" >"$dir/curl"
    env HOME="$home" FONT_DIR="$home/.fonts" \
        FONT_URL="https://example.com/ignored" FONT_SHA256="$sha" \
        PATH="$dir:/usr/bin:/bin" \
        bash "$ROOT_DIR/bin/install-fonts-jetbrains" &>/dev/null || return 1
    [[ ! -s "$calls" ]]
}

run_test "failed GitHub login is fatal" test_github_failed_login_is_fatal
run_test "GitHub CLI protocol is explicitly set to SSH" test_github_protocol_is_explicitly_set_to_ssh
run_test "install-zed installs and skips when already present" test_install_zed_script
run_test "install-fonts-jetbrains installs fonts and skips when already present" test_install_jetbrains_fonts_script

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
