#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "Homebrew, brew formulae, mise, GitHub, Zed, Git, Docker"

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

run_test "Homebrew handles missing and healthy installations" test_homebrew_missing_and_healthy_branches
run_test "Brew installs only missing formulae" test_brew_installs_only_missing_formulae
run_test "Mise installs only missing global tools" test_mise_installs_only_missing_tools
run_test "failed GitHub login is fatal" test_github_failed_login_is_fatal
run_test "GitHub CLI protocol is explicitly set to SSH" test_github_protocol_is_explicitly_set_to_ssh
run_test "Zed installs only when missing" test_zed_installs_only_when_missing
run_test "Git defaults set main branch and an identity" test_git_defaults_set_main_and_identity
run_test "Docker is installed for on-demand use" test_docker_configures_repo_service_and_group
run_test "Docker setup delegates to focused steps" test_docker_orchestration_uses_focused_steps
run_test "Docker toggle changes daemon state safely" test_docker_toggle_helper_transitions
run_test "Docker toggle DMS plugin has expected actions" test_docker_toggle_plugin_contract

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
