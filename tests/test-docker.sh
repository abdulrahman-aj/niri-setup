#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Docker install script, toggle, and DMS plugin"

test_install_docker_script() {
    local dir home sudoers plugin_dir
    dir="$(make_tempdir)"; home="$(make_tempdir)"
    sudoers="$dir/sudoers"; plugin_dir="$home/plugins/dockerToggle"

    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$dir/dnf"
    printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$dir/visudo"
    printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' >"$dir/sudo"
    printf '%s\n' '#!/usr/bin/env bash' \
        'case "$*" in' \
        '  is-enabled*) printf "disabled\n"; exit 1 ;;' \
        '  is-active*) exit 3 ;;' \
        'esac' >"$dir/systemctl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "tester wheel\n"' >"$dir/id"
    printf '%s\n' '#!/usr/bin/env bash' >"$dir/usermod"
    chmod +x "$dir/dnf" "$dir/visudo" "$dir/sudo" "$dir/systemctl" "$dir/id" "$dir/usermod"

    env HOME="$home" USER=tester ROOT_DIR="$ROOT_DIR" \
        SUDOERS="$sudoers" PLUGIN_DIR="$plugin_dir" \
        PATH="$dir:/usr/bin:/bin" \
        bash "$ROOT_DIR/bin/install-docker" &>/dev/null || return 1

    assert_file_contains "$sudoers" 'tester ALL=(root) NOPASSWD: /usr/bin/systemctl start docker.service docker.socket'
    [[ -L "$plugin_dir" && "$(readlink "$plugin_dir")" == "$ROOT_DIR/assets/dms-plugins/toggle-docker" ]]
}

test_docker_toggle_helper_transitions() {
    local dir state helper
    dir="$(make_tempdir)"; state="$dir/state"; helper="$ROOT_DIR/bin/toggle-docker"
    # shellcheck disable=SC2016
    printf '%s\n' '#!/usr/bin/env bash' \
        'state=$DOCKER_TEST_STATE' \
        'case "$1" in' \
        '  is-active) [[ "$(cat "$state")" == active ]] ;;' \
        '  start) printf "active\n" >"$state" ;;' \
        '  stop) printf "inactive\n" >"$state" ;;' \
        'esac' >"$dir/systemctl"
    printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' >"$dir/sudo"
    chmod +x "$dir/systemctl" "$dir/sudo"
    export PATH="$dir:$PATH" DOCKER_TEST_STATE="$state"
    printf 'inactive\n' >"$state"
    [[ -x "$helper" ]] || return 1
    [[ "$("$helper" status)" == inactive ]] || return 1
    "$helper" start &>/dev/null || return 1
    [[ "$(cat "$state")" == active ]] || return 1
    "$helper" toggle &>/dev/null || return 1
    [[ "$(cat "$state")" == inactive ]] || return 1
    "$helper" stop &>/dev/null || return 1
    [[ "$(cat "$state")" == inactive ]] || return 1
    if "$helper" invalid &>/dev/null; then
        return 1
    fi
}

test_docker_toggle_plugin_contract() {
    local manifest="$ROOT_DIR/assets/dms-plugins/toggle-docker/plugin.json"
    local component="$ROOT_DIR/assets/dms-plugins/toggle-docker/DockerToggle.qml"
    assert_file_contains "$manifest" '"id": "dockerToggle"'
    assert_file_contains "$component" 'pillClickAction: () => toggleDocker()'
    assert_file_contains "$component" 'pillRightClickAction: () => openLazydocker()'
    assert_file_contains "$component" '["/usr/local/bin/toggle-docker", "toggle"]'
    assert_file_contains "$component" '["/usr/local/bin/launch-or-focus-tui", "lazydocker"]'
    assert_file_lacks "$component" '["/usr/local/bin/toggle-docker", "start"]'
}

run_test "install-docker configures repo, packages, sudoers, plugin, and access" test_install_docker_script
run_test "Docker toggle changes daemon state safely" test_docker_toggle_helper_transitions
run_test "Docker toggle DMS plugin has expected actions" test_docker_toggle_plugin_contract

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
