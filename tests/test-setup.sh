#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "setup entrypoints, OS detection, bootstrap, module system, install.sh"

test_root_rejected() {
    ! ( current_euid() { printf '0\n'; }; sudo() { return 0; }; require_regular_user ) &>/dev/null
}

test_regular_user_accepted() {
    ( current_euid() { printf '1000\n'; }; sudo() { return 0; }; require_regular_user )
}

test_banner_has_no_log_prefix() {
    local actual expected
    actual="$(banner 'Test title')"
    expected="$(printf '%b' "${CYAN}${BOLD}Test title${NC}")"
    assert_eq "$actual" "$expected"
    [[ "$actual" != *'[i]'* ]] || fail_assert "banner has log prefix [i]"
}

test_fedora_44_accepted() {
    local file; file="$(make_tempfile)"
    printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=workstation\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
}

test_other_fedora_rejected() {
    local file; file="$(make_tempfile)"
    printf 'ID=fedora\nVERSION_ID=43\nVARIANT_ID=workstation\n' >"$file"
    ! ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
}

test_non_workstation_rejected() {
    local file; file="$(make_tempfile)"
    printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=server\n' >"$file"
    ! ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
}

test_non_intel_rejected() {
    ! ( uname() { printf 'x86_64\n'; }; lspci() { printf 'VGA compatible controller: AMD Radeon\n'; }; require_intel_graphics ) &>/dev/null
}

test_home_lookup_failure_is_rejected() {
    ! (
        id() { [[ "$1" == '-un' ]] && printf 'missing-user\n'; }
        getent() { return 2; }
        resolve_identity
    ) &>/dev/null
}

test_bootstrap_requires_git_and_pciutils() {
    local calls
    calls="$(make_tempfile)"
    ( s() { printf '%s\n' "$*" >>"$calls"; }; install_bootstrap_packages )
    assert_file_contains "$calls" 'git'
    assert_file_contains "$calls" 'pciutils'
}

test_bootstrap_package_install_is_rerunnable() {
    local calls; calls="$(make_tempfile)"
    (
        s() { printf '%s\n' "$*" >>"$calls"; }
        install_bootstrap_packages
        install_bootstrap_packages
    ) &>/dev/null
    [[ "$(grep -c 'dnf install' "$calls")" -eq 2 ]]
}

test_core_stack_requires_every_command() {
    ( have_command() { [[ "$1" != niri ]]; }; ! core_stack_complete )
}

test_checksum_validation() {
    local file digest; file="$(make_tempfile)"
    printf 'verified payload' >"$file"
    digest="$(sha256sum "$file" | awk '{print $1}')"
    verify_checksum "$file" "$digest"
    if verify_checksum "$file" "0000000000000000000000000000000000000000000000000000000000000000"; then
        return 1
    fi
}

test_required_failure_is_returned() {
    ! (
        s() { return 1; }
        install_required_group "required test" package
    ) &>/dev/null
}

test_modules_are_discovered_in_lexical_order() {
    local directory; directory="$(make_tempdir)"
    printf 'MODULE_LOAD_ORDER+=(first)\n' >"$directory/1-first.sh"
    printf 'MODULE_LOAD_ORDER+=(second)\n' >"$directory/2-second.sh"
    printf 'MODULE_LOAD_ORDER+=(third)\n' >"$directory/3-third.sh"
    assert_eq "$( MODULE_LOAD_ORDER=(); source_modules "$directory" >/dev/null; printf '%s' "${MODULE_LOAD_ORDER[*]}" )" 'first second third'
}

test_missing_module_is_fatal() {
    ! ( source_required modules/does-not-exist.sh ) &>/dev/null
}

test_empty_module_directory_is_fatal() {
    local directory; directory="$(make_tempdir)"
    ! ( source_modules "$directory" ) &>/dev/null
}

test_unreadable_module_is_fatal() {
    local directory file status
    directory="$(make_tempdir)"; file="$directory/1-unreadable.sh"
    printf ':\n' >"$file"
    chmod 000 "$file"
    ( source_modules "$directory" ) &>/dev/null; status=$?
    chmod 600 "$file"
    [[ $status -ne 0 ]]
}

test_entrypoints_and_update_contract() {
    [[ -x "$ROOT_DIR/setup.sh" ]] || fail_assert "setup.sh not executable"
    [[ -x "$ROOT_DIR/install.sh" ]] || fail_assert "install.sh not executable"
    [[ ! -e "$ROOT_DIR/assets/niri-setup-update" ]] || fail_assert "stale niri-setup-update present"
    [[ ! -e "$ROOT_DIR/setup-fedora-niri-dms.sh" ]] || fail_assert "stale setup-fedora-niri-dms.sh present"
}

test_runtime_commands_and_workstation_modules_are_organized() {
    local command component
    for command in toggle-docker launch-or-focus launch-or-focus-tui install-webapp launch-or-focus-webapp update-workstation install-docker install-homebrew install-wallpaper; do
        [[ -x "$ROOT_DIR/bin/$command" ]] || return 1
    done
    for command in toggle-docker launch-or-focus-tui launch-or-focus-webapp; do
        [[ ! -e "$ROOT_DIR/assets/$command" ]] || return 1
    done
    for component in desktop development webapps; do
        [[ -r "$ROOT_DIR/modules/workstation/$component.sh" ]] || return 1
    done
}

test_install_bootstrap_sync_branches() {
    local dir calls
    dir="$(make_tempdir)"; calls="$(make_tempfile)"
    (
        NIRI_SETUP_DIR="$dir/managed"
        source "$ROOT_DIR/install.sh"
        git() {
            printf '%s\n' "$*" >>"$calls"
            [[ "$1" == clone ]] && mkdir -p "$INSTALL_DIR/.git"
        }
        sync_managed_checkout
    )
    grep -Fxq "clone --branch main https://github.com/abdulrahman-aj/niri-setup.git $dir/managed" "$calls" || return 1
    : >"$calls"; mkdir -p "$dir/existing/.git"
    (
        NIRI_SETUP_DIR="$dir/existing"
        source "$ROOT_DIR/install.sh"
        git() {
            case "$*" in
                *'remote get-url origin') printf '%s\n' "$REPO_URL" ;;
                *'status --porcelain') : ;;
                *'pull --ff-only origin main') printf '%s\n' pull >>"$calls" ;;
            esac
        }
        sync_managed_checkout
    )
    grep -Fxq pull "$calls" || return 1
    if (
        NIRI_SETUP_DIR="$dir/existing"
        source "$ROOT_DIR/install.sh"
        git() {
            case "$*" in
                *'remote get-url origin') printf '%s\n' "$REPO_URL" ;;
                *'status --porcelain') printf 'dirty\n' ;;
            esac
        }
        sync_managed_checkout
    ) &>/dev/null; then
        return 1
    fi
    if (
        NIRI_SETUP_DIR="$dir/existing"
        source "$ROOT_DIR/install.sh"
        git() {
            case "$*" in
                *'remote get-url origin') printf 'https://example.com/wrong.git\n' ;;
            esac
        }
        sync_managed_checkout
    ) &>/dev/null; then
        return 1
    fi
}

test_install_bootstraps_missing_git() {
    local calls; calls="$(make_tempfile)"
    # shellcheck disable=SC2030
    (
        NIRI_SETUP_DIR=/tmp/not-used
        source "$ROOT_DIR/install.sh"
        command() { return 1; }
        sudo() { printf '%s\n' "$*" >>"$calls"; }
        ensure_git
    )
    grep -Fxq 'dnf install -y git' "$calls"
}

test_install_runs_when_piped_to_bash() {
    local dir bin marker
    dir="$(make_tempdir)"; bin="$dir/bin"; marker="$dir/setup-ran"
    mkdir -p "$bin"
    # shellcheck disable=SC2016
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$1" == clone ]]; then' \
        '    destination="${@: -1}"' \
        '    mkdir -p "$destination/.git"' \
        '    printf "%s\n" "#!/usr/bin/env bash" "printf ran >\"$INSTALL_PIPE_MARKER\"" >"$destination/setup.sh"' \
        '    chmod +x "$destination/setup.sh"' \
        'fi' >"$bin/git"
    chmod +x "$bin/git"
    PATH="$bin:/usr/bin:/bin" NIRI_SETUP_DIR="$dir/managed" INSTALL_PIPE_MARKER="$marker" \
        bash <"$ROOT_DIR/install.sh"
    assert_eq "$(cat "$marker")" ran
}

test_install_pause_preserves_update_status() {
    local calls status; calls="$(make_tempfile)"
    (
        source "$ROOT_DIR/install.sh"
        stdin_is_tty() { return 0; }
        read() { printf '%s\n' "$*" >>"$calls"; }
        pause_for_completion 0
    ) &>/dev/null || return 1
    grep -Fq 'Workstation update complete. Press any key to close...' "$calls" || return 1
    status=0
    (
        source "$ROOT_DIR/install.sh"
        stdin_is_tty() { return 0; }
        read() { printf '%s\n' "$*" >>"$calls"; }
        pause_for_completion 7
    ) &>/dev/null || status=$?
    [[ "$status" -eq 7 ]] || return 1
    grep -Fq 'Workstation update failed with status 7. Press any key to close...' "$calls" || return 1
    : >"$calls"
    (
        source "$ROOT_DIR/install.sh"
        stdin_is_tty() { return 1; }
        read() { printf called >>"$calls"; }
        pause_for_completion 0
    ) &>/dev/null || status=$?
    [[ ! -s "$calls" ]]
    status=0
    (
        source "$ROOT_DIR/install.sh"
        stdin_is_tty() { return 0; }
        ensure_git() { :; }
        sync_managed_checkout() { return 9; }
        read() { printf '%s\n' "$*" >>"$calls"; }
        run_update
    ) &>/dev/null || status=$?
    [[ "$status" -eq 9 ]] || return 1
    grep -Fq 'Workstation update failed with status 9. Press any key to close...' "$calls" || return 1
}

run_test "root execution is rejected" test_root_rejected
run_test "regular user execution is accepted" test_regular_user_accepted
run_test "startup banner has no log prefix" test_banner_has_no_log_prefix
run_test "Fedora 44 is accepted" test_fedora_44_accepted
run_test "other Fedora releases are rejected" test_other_fedora_rejected
run_test "non-Workstation Fedora is rejected" test_non_workstation_rejected
run_test "non-Intel graphics are rejected" test_non_intel_rejected
run_test "failed home lookup is rejected" test_home_lookup_failure_is_rejected
run_test "bootstrap requires git and pciutils for preflight" test_bootstrap_requires_git_and_pciutils
run_test "bootstrap package installation is rerunnable" test_bootstrap_package_install_is_rerunnable
run_test "partial core stack is detected" test_core_stack_requires_every_command
run_test "checksums are accepted and rejected correctly" test_checksum_validation
run_test "required package failures are returned" test_required_failure_is_returned
run_test "modules are discovered in lexical order" test_modules_are_discovered_in_lexical_order
run_test "missing modules are fatal" test_missing_module_is_fatal
run_test "empty module directories are fatal" test_empty_module_directory_is_fatal
run_test "unreadable modules are fatal" test_unreadable_module_is_fatal
run_test "setup entrypoints and updater contract are exact" test_entrypoints_and_update_contract
run_test "runtime commands and workstation modules are domain-organized" test_runtime_commands_and_workstation_modules_are_organized
run_test "install bootstrap handles fresh, clean, and rejected checkouts" test_install_bootstrap_sync_branches
run_test "install bootstrap installs missing Git" test_install_bootstraps_missing_git
run_test "install bootstrap runs when piped to Bash" test_install_runs_when_piped_to_bash
run_test "terminal update pause preserves workflow status" test_install_pause_preserves_update_status

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
