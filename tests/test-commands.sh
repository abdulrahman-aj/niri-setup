#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "launch-or-focus (TUI/webapp/base), install-webapp, managed symlinks, commands install"

make_lof_fixtures() {
    local dir="$1" win_id="${2:-88}"
    # shellcheck disable=SC2016 # These lines form scripts evaluated later.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$*" == "msg -j windows" ]]; then' \
        '    if [[ -n "${LAUNCH_MARKER:-}" && -e "$LAUNCH_MARKER" ]]; then' \
        "        printf '[{\"id\":${win_id},\"app_id\":\"%s\",\"is_focused\":true}]\\n' \"\${LAUNCH_APP_ID:-niri-webapp-reddit}\"" \
        '    else' \
        '        cat "$WINDOWS_FILE"' \
        '    fi' \
        'elif [[ "$1 $2 $3" == "msg action focus-window" ]]; then' \
        '    printf "%s\\n" "$*" >>"$FOCUS_LOG"' \
        'else' \
        '    exit 2' \
        'fi' >"$dir/niri"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '[[ ! -e /proc/$$/fd/9 ]] || printf "<fd9-open>\\n" >>"$LAUNCH_LOG.fd"' \
        'printf "<%s>\\n" "$@" >>"$LAUNCH_LOG"' \
        '[[ -z "${LAUNCH_MARKER:-}" ]] || touch "$LAUNCH_MARKER"' \
        '[[ -z "${SETSID_DELAY:-}" ]] || sleep "$SETSID_DELAY"' \
        >"$dir/setsid"
    chmod +x "$dir/niri" "$dir/setsid"
}

test_tui_launches_once_then_focuses() {
    local dir marker hostile
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"; hostile="$dir/should-not-exist"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"; : >"$FOCUS_LOG"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker "$ROOT_DIR/bin/launch-or-focus-tui" lazydocker "\$(touch $hostile)"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker "$ROOT_DIR/bin/launch-or-focus-tui" lazydocker --debug
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$LAUNCH_LOG")" == 1 ]] || return 1
    grep -Fxq 'msg action focus-window --id 88' "$FOCUS_LOG" || return 1
    grep -Fxq "<\$(touch $hostile)>" "$LAUNCH_LOG" || return 1
    [[ ! -e "$hostile" ]] || return 1
}

test_tui_concurrent_launch_deduplicates() {
    local dir marker first_pid second_pid
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker SETSID_DELAY=0.3 "$ROOT_DIR/bin/launch-or-focus-tui" lazydocker &
    first_pid=$!
    sleep 0.05
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker SETSID_DELAY=0.3 "$ROOT_DIR/bin/launch-or-focus-tui" lazydocker &
    second_pid=$!
    wait "$first_pid"; wait "$second_pid"
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$LAUNCH_LOG")" == 1 ]] || return 1
}

test_tui_failure_when_app_never_appears() {
    local dir
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    if "$ROOT_DIR/bin/launch-or-focus-tui" lazydocker 2>/dev/null; then return 1; fi
    grep -Fxq '<--app-id=local.tui.lazydocker>' "$LAUNCH_LOG" || return 1
}

test_tui_different_app_gets_own_id() {
    local dir marker
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.btop "$ROOT_DIR/bin/launch-or-focus-tui" btop
    grep -Fxq '<--app-id=local.tui.btop>' "$LAUNCH_LOG" || return 1
}

test_webapp_focuses_by_cached_window_id() {
    local dir
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"

    mkdir -p "$XDG_RUNTIME_DIR/launch-or-focus"
    printf '77\n' >"$XDG_RUNTIME_DIR/launch-or-focus/niri-webapp-notion.window-id"
    printf '[{"id":77,"app_id":"google-chrome","is_focused":false}]\n' >"$WINDOWS_FILE"
    : >"$FOCUS_LOG"
    "$ROOT_DIR/bin/launch-or-focus-webapp" notion https://www.notion.so
    grep -Fxq 'msg action focus-window --id 77' "$FOCUS_LOG" || return 1
}

test_webapp_launches_and_caches_window_id() {
    local dir marker
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=niri-webapp-notion "$ROOT_DIR/bin/launch-or-focus-webapp" notion https://www.notion.so
    [[ "$(cat "$XDG_RUNTIME_DIR/launch-or-focus/niri-webapp-notion.window-id")" == 88 ]] || return 1
    grep -Fxq '<--class=niri-webapp-notion>' "$LAUNCH_LOG" || return 1
}

test_webapp_launch_by_name_only() {
    local dir marker
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    LAUNCH_MARKER="$marker" "$ROOT_DIR/bin/launch-or-focus-webapp" reddit https://www.reddit.com
    [[ "$(cat "$XDG_RUNTIME_DIR/launch-or-focus/niri-webapp-reddit.window-id")" == 88 ]] || return 1
    grep -Fxq '<--app=https://www.reddit.com>' "$LAUNCH_LOG" || return 1
    grep -Fxq '<--class=niri-webapp-reddit>' "$LAUNCH_LOG" || return 1
}

test_webapp_concurrent_launch_deduplicates() {
    local dir marker first_pid second_pid
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=niri-webapp-chatgpt SETSID_DELAY=0.3 "$ROOT_DIR/bin/launch-or-focus-webapp" chatgpt https://chatgpt.com &
    first_pid=$!
    sleep 0.05
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=niri-webapp-chatgpt SETSID_DELAY=0.3 "$ROOT_DIR/bin/launch-or-focus-webapp" chatgpt https://chatgpt.com &
    second_pid=$!
    wait "$first_pid"; wait "$second_pid"
    [[ "$(grep -Fxc '<--class=niri-webapp-chatgpt>' "$LAUNCH_LOG")" == 1 ]] || return 1
}

test_webapp_failure_when_app_never_appears() {
    local dir
    dir="$(make_tempdir)"; make_lof_fixtures "$dir"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"

    printf '[]\n' >"$WINDOWS_FILE"; : >"$LAUNCH_LOG"
    if "$ROOT_DIR/bin/launch-or-focus-webapp" gmail https://mail.google.com 2>/dev/null; then return 1; fi
    grep -Fxq '<--class=niri-webapp-gmail>' "$LAUNCH_LOG" || return 1
    if grep -Fq '<fd9-open>' "$LAUNCH_LOG.fd" 2>/dev/null; then return 1; fi
}

test_launch_or_focus_has_no_eval() {
    if grep -Fq eval "$ROOT_DIR/bin/launch-or-focus-webapp" || \
       grep -Fq eval "$ROOT_DIR/bin/launch-or-focus-tui"; then return 1; fi
}

test_launch_or_focus_base_contract() {
    local dir marker
    dir="$(make_tempdir)"; make_lof_fixtures "$dir" 99
    PATH="$dir:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run" WINDOWS_FILE="$dir/windows.json" FOCUS_LOG="$dir/focus.log" LAUNCH_LOG="$dir/launch.log"
    marker="$dir/launched"

    # Focus an existing window by app_id; never launch.
    printf '[{"id":42,"app_id":"test.app","is_focused":false}]\n' >"$WINDOWS_FILE"
    : >"$FOCUS_LOG"; : >"$LAUNCH_LOG"; rm -f "$marker"
    "$ROOT_DIR/bin/launch-or-focus" test.app placeholder
    assert_ok grep -Fxq 'msg action focus-window --id 42' "$FOCUS_LOG"
    [[ ! -s "$LAUNCH_LOG" ]] || fail_assert "launched when focusing an existing window"
    assert_eq "$(cat "$XDG_RUNTIME_DIR/launch-or-focus/test.app.window-id")" 42

    # Launch and cache the new window when none matches.
    printf '[]\n' >"$WINDOWS_FILE"
    : >"$FOCUS_LOG"; : >"$LAUNCH_LOG"; rm -f "$marker" "$XDG_RUNTIME_DIR/launch-or-focus/test.app2.window-id"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=test.app2 "$ROOT_DIR/bin/launch-or-focus" test.app2 mycmd --flag
    assert_ok grep -Fxq '<mycmd>' "$LAUNCH_LOG"
    assert_ok grep -Fxq '<--flag>' "$LAUNCH_LOG"
    assert_eq "$(cat "$XDG_RUNTIME_DIR/launch-or-focus/test.app2.window-id")" 99

    # Reject a call without a launch command.
    assert_fails "$ROOT_DIR/bin/launch-or-focus" test.app3 2>/dev/null
    assert_file_lacks "$ROOT_DIR/bin/launch-or-focus" 'eval'
}

test_webapp_manifest_delegates_to_installer() {
    local calls; calls="$(make_tempfile)"
    (
        webapp_install_cmd() { printf '%s\t%s\t%s\t%s\n' "$@" >>"$calls"; }
        install_webapps
    ) &>/dev/null || return 1
    grep -Fxq $'notion\tNotion\thttps://www.notion.so\tnotion.so' "$calls"
    grep -Fxq $'google-calendar\tGoogle Calendar\thttps://calendar.google.com\tcalendar.google.com' "$calls"
    grep -Fxq $'discord\tDiscord\thttps://discord.com/app\tdiscord.com' "$calls"
}

test_webapp_install_creates_idempotent_launcher() {
    local dir applications icons database_log helper desktop; dir="$(make_tempdir)"
    applications="$dir/.local/share/applications"
    icons="$dir/.local/share/icons/hicolor/128x128/apps"
    database_log="$dir/database.log"
    helper="$ROOT_DIR/bin/install-webapp"; desktop="$applications/niri-webapp-notion.desktop"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' 'while (($#)); do if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi; done' 'printf png >"$output"' >"$dir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$WEBAPP_DATABASE_LOG"' >"$dir/update-desktop-database"
    chmod +x "$dir/curl" "$dir/update-desktop-database"
    export HOME="$dir" PATH="$dir:$PATH" WEBAPP_DATABASE_LOG="$database_log"
    "$helper" notion Notion https://www.notion.so notion.so || return 1
    grep -Fxq 'Name=Notion' "$desktop"
    grep -Fxq 'Exec=/usr/local/bin/launch-or-focus-webapp notion https://www.notion.so' "$desktop"
    grep -Fxq 'Icon=niri-webapp-notion' "$desktop"
    [[ -s "$icons/niri-webapp-notion.png" ]]
    "$helper" notion Notion https://www.notion.so notion.so || return 1
    [[ "$(find "$applications" "$icons" -name '*.backup-*' | wc -l)" -eq 0 ]] || return 1
    "$helper" notion 'Notion App' https://www.notion.so notion.so || return 1
    grep -Fxq 'Name=Notion App' "$desktop"
    [[ "$(find "$applications" -name 'niri-webapp-notion.desktop.backup-*' | wc -l)" -eq 1 ]]
    [[ "$(wc -l <"$database_log")" -eq 3 ]]
}

test_webapp_install_validates_and_falls_back() {
    local dir helper desktop
    dir="$(make_tempdir)"; helper="$ROOT_DIR/bin/install-webapp"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 1' >"$dir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$dir/update-desktop-database"
    chmod +x "$dir/curl" "$dir/update-desktop-database"
    export HOME="$dir" PATH="$dir:$PATH"
    "$helper" chatgpt ChatGPT https://chatgpt.com chatgpt.com 2>/dev/null || return 1
    desktop="$dir/.local/share/applications/niri-webapp-chatgpt.desktop"
    grep -Fxq 'Icon=google-chrome' "$desktop" || return 1
    if "$helper" 'bad id' Bad https://example.com example.com 2>/dev/null; then return 1; fi
    if "$helper" valid Bad http://example.com example.com 2>/dev/null; then return 1; fi
}

test_managed_symlink_is_idempotent_and_backed_up() {
    local dir target destination backup_count
    dir="$(make_tempdir)"; target="$dir/target"; destination="$dir/link"
    printf 'managed\n' >"$target"
    printf 'user content\n' >"$destination"
    install_symlink_with_backup "$target" "$destination"
    [[ -L "$destination" && "$(readlink "$destination")" == "$target" ]] || return 1
    backup_count="$(find "$dir" -maxdepth 1 -name 'link.backup-*' | wc -l)"
    [[ "$backup_count" -eq 1 ]] || return 1
    install_symlink_with_backup "$target" "$destination"
    [[ "$(find "$dir" -maxdepth 1 -name 'link.backup-*' | wc -l)" -eq 1 ]]
}

test_commands_install_every_bin_script_and_reject_invalid_entries() {
    local calls expected invalid; calls="$(make_tempfile)"
    (
        install_root_symlink_with_backup() { printf '%s %s\n' "$1" "$2" >>"$calls"; }
        install_commands
    ) &>/dev/null || return 1
    expected="$(find "$ROOT_DIR/bin" -maxdepth 1 -type f -executable | wc -l)"
    [[ "$(wc -l <"$calls")" -eq "$expected" ]] || return 1
    grep -Fxq "$ROOT_DIR/bin/install-webapp /usr/local/bin/install-webapp" "$calls"
    grep -Fxq "$ROOT_DIR/bin/launch-or-focus-tui /usr/local/bin/launch-or-focus-tui" "$calls"
    grep -Fxq "$ROOT_DIR/bin/update-workstation /usr/local/bin/update-workstation" "$calls"
    invalid="$(make_tempdir)"
    printf 'not executable\n' >"$invalid/broken"
    if ( COMMANDS_DIR="$invalid"; install_commands ) &>/dev/null; then return 1; fi
}

run_test "TUI launches once then focuses on second call" test_tui_launches_once_then_focuses
run_test "TUI concurrent launches deduplicate" test_tui_concurrent_launch_deduplicates
run_test "TUI exits non-zero when app never appears" test_tui_failure_when_app_never_appears
run_test "TUI derives app-id from command name" test_tui_different_app_gets_own_id
run_test "webapp focuses by cached window-id" test_webapp_focuses_by_cached_window_id
run_test "webapp launches and caches window-id" test_webapp_launches_and_caches_window_id
run_test "webapp launches by name when no app-id is given" test_webapp_launch_by_name_only
run_test "webapp concurrent launches deduplicate" test_webapp_concurrent_launch_deduplicates
run_test "webapp exits non-zero when app never appears" test_webapp_failure_when_app_never_appears
run_test "launch-or-focus scripts contain no eval" test_launch_or_focus_has_no_eval
run_test "launch-or-focus base focuses, launches, caches, and validates" test_launch_or_focus_base_contract
run_test "web-app manifest delegates every entry to install-webapp" test_webapp_manifest_delegates_to_installer
run_test "install-webapp creates idempotent backed-up launchers" test_webapp_install_creates_idempotent_launcher
run_test "install-webapp validates input and falls back to Chrome" test_webapp_install_validates_and_falls_back
run_test "managed assets use backed-up idempotent symlinks" test_managed_symlink_is_idempotent_and_backed_up
run_test "all bin commands are installed and invalid entries are rejected" test_commands_install_every_bin_script_and_reject_invalid_entries

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
