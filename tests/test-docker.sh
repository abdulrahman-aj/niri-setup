#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Docker installation, toggle, and DMS plugin"

test_docker_configures_repo_service_and_group() {
    local calls home
    calls="$(make_tempfile)"; home="$(make_tempdir)"
    (
        REAL_USER=tester
        REAL_HOME="$home"
        rpm() { return 1; }
        dnf() { return 0; }
        id() { [[ "$1" == -nG ]] && printf 'tester wheel\n'; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        visudo() { return 0; }
        install_root_file_with_backup() {
            if [[ "$2" == /etc/sudoers.d/docker-toggle ]]; then
                grep -Fxq 'tester ALL=(root) NOPASSWD: /usr/bin/systemctl start docker.service docker.socket, /usr/bin/systemctl stop docker.service docker.socket' "$1"
            fi
            printf 'root-file %s %s\n' "$2" "$3" >>"$calls"
        }
        install_symlink_with_backup() { printf 'user-link %s %s\n' "$1" "$2" >>"$calls"; }
        systemctl() {
            case "$1" in
                is-enabled) printf 'disabled\n'; return 1 ;;
                is-active) return 3 ;;
            esac
        }
        install_docker
    ) &>/dev/null
    grep -Fq 'dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo' "$calls" || return 1
    grep -Fxq 'systemctl disable --now docker.service docker.socket' "$calls" || return 1
    grep -Fxq 'usermod -aG docker tester' "$calls" || return 1
    grep -Fxq 'root-file /etc/sudoers.d/docker-toggle 0440' "$calls" || return 1
    grep -Fxq "user-link $ROOT_DIR/assets/dms-plugins/docker-toggle $home/.config/DankMaterialShell/plugins/dockerToggle" "$calls" || return 1
}

test_docker_orchestration_uses_focused_steps() {
    local calls; calls="$(make_tempfile)"
    (
        warn() { :; }
        enable_docker_repository() { printf '%s\n' repository >>"$calls"; }
        install_docker_packages() { printf '%s\n' packages >>"$calls"; }
        install_docker_toggle() { printf '%s\n' toggle >>"$calls"; }
        configure_docker_access() { printf '%s\n' access >>"$calls"; }
        verify_docker_disabled() { printf '%s\n' verify >>"$calls"; }
        install_docker
    )
    [[ "$(tr '\n' ' ' <"$calls")" == 'repository packages toggle access verify ' ]]
}

test_docker_toggle_helper_transitions() {
    local dir state helper
    dir="$(make_tempdir)"; state="$dir/state"; helper="$ROOT_DIR/bin/docker-toggle"
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
    local manifest="$ROOT_DIR/assets/dms-plugins/docker-toggle/plugin.json"
    local component="$ROOT_DIR/assets/dms-plugins/docker-toggle/DockerToggle.qml"
    assert_file_contains "$manifest" '"id": "dockerToggle"'
    assert_file_contains "$component" 'pillClickAction: () => toggleDocker()'
    assert_file_contains "$component" 'pillRightClickAction: () => openLazydocker()'
    assert_file_contains "$component" '["/usr/local/bin/docker-toggle", "toggle"]'
    assert_file_contains "$component" '["/usr/local/bin/tui-launch-or-focus", "lazydocker"]'
    assert_file_lacks "$component" '["/usr/local/bin/docker-toggle", "start"]'
}

run_test "Docker is installed for on-demand use" test_docker_configures_repo_service_and_group
run_test "Docker setup delegates to focused steps" test_docker_orchestration_uses_focused_steps
run_test "Docker toggle changes daemon state safely" test_docker_toggle_helper_transitions
run_test "Docker toggle DMS plugin has expected actions" test_docker_toggle_plugin_contract

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
