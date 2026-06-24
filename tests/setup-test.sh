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
fail_assert()          { printf 'assert failed: %s\n' "$1" >&2; exit 1; }
assert_eq()            { [[ "$1" == "$2" ]] || fail_assert "expected '$2', got '$1'"; }
assert_contains()      { [[ "$1" == *"$2"* ]] || fail_assert "missing '$2' in '$1'"; }
assert_file_contains() { grep -Fq -- "$2" "$1" || fail_assert "$1 missing '$2'"; }
assert_file_lacks()    { if grep -Fq -- "$2" "$1"; then fail_assert "$1 unexpectedly has '$2'"; fi; }
assert_ok()            { "$@" || fail_assert "command failed: $*"; }
assert_fails()         { if "$@"; then fail_assert "unexpected success: $*"; fi; }

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
    local file
    file="$(make_tempfile)"
    printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=workstation\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
    local status=$?
    [[ $status -eq 0 ]]
}

test_other_fedora_rejected() {
    local file
    file="$(make_tempfile)"
    printf 'ID=fedora\nVERSION_ID=43\nVARIANT_ID=workstation\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
    local status=$?
    [[ $status -ne 0 ]]
}

test_non_workstation_rejected() {
    local file status
    file="$(make_tempfile)"
    printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=server\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
    status=$?
    [[ $status -ne 0 ]]
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

test_preflight_bootstraps_before_hardware_and_dotfiles_checks() {
    local calls
    calls="$(make_tempfile)"
    (
        step() { printf 'heading:%s\n' "$*" >>"$calls"; }
        require_bootstrap_commands() { printf '%s\n' minimal >>"$calls"; }
        require_regular_user() { printf '%s\n' sudo >>"$calls"; }
        resolve_identity() { printf '%s\n' identity >>"$calls"; }
        detect_fedora() { printf '%s\n' fedora >>"$calls"; }
        require_x86_64() { printf '%s\n' arch >>"$calls"; }
        install_bootstrap_packages() { printf '%s\n' bootstrap >>"$calls"; }
        require_commands() { printf '%s\n' commands >>"$calls"; }
        require_intel_graphics() { printf '%s\n' intel >>"$calls"; }
        validate_existing_dotfiles() { printf '%s\n' dotfiles >>"$calls"; }
        preflight
    )
    [[ "$(tr '\n' ' ' <"$calls")" == 'heading:Preflight minimal sudo identity fedora arch bootstrap commands intel dotfiles ' ]]
}

test_bootstrap_package_list_is_exact() {
    local calls
    calls="$(make_tempfile)"
    ( s() { printf '%s\n' "$*" >>"$calls"; }; install_bootstrap_packages )
    grep -Fxq 'dnf install -y git pciutils' "$calls"
}

test_bootstrap_package_install_is_rerunnable() {
    local calls
    calls="$(make_tempfile)"
    (
        s() { printf '%s\n' "$*" >>"$calls"; }
        install_bootstrap_packages
        install_bootstrap_packages
    ) &>/dev/null
    [[ "$(grep -c '^dnf install -y git pciutils$' "$calls")" -eq 2 ]]
}

test_dnf_settings_are_replaced_once() {
    local file
    file="$(make_tempfile)"
    printf '[main]\nmax_parallel_downloads=3\nmax_parallel_downloads=5\ndefaultyes=False\n' >"$file"
    (
        DNF_CONF="$file"
        s() { "$@"; }
        optimize_dnf
    ) &>/dev/null || return 1
    [[ "$(grep -c '^max_parallel_downloads=10$' "$file")" -eq 1 ]]
    [[ "$(grep -c '^defaultyes=True$' "$file")" -eq 1 ]]
}

test_core_stack_requires_every_command() {
    ( have_command() { [[ "$1" != niri ]]; }; ! core_stack_complete )
}

test_checksum_validation() {
    local file digest
    file="$(make_tempfile)"
    printf 'verified payload' >"$file"
    digest="$(sha256sum "$file" | awk '{print $1}')"
    verify_checksum "$file" "$digest"
    if verify_checksum "$file" "0000000000000000000000000000000000000000000000000000000000000000"; then
        return 1
    fi
}

test_dankinstall_selects_sudo_without_exporting_it() {
    local dir marker observed
    dir="$(make_tempdir)"
    marker="$dir/stack-complete"
    observed="$dir/privesc"
    (
        export STACK_MARKER="$marker" DMS_PRIVESC_CAPTURE="$observed"
        unset DMS_PRIVESC
        core_stack_complete() { [[ -f "$marker" ]]; }
        curl() {
            local output=""
            while (($#)); do
                if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi
            done
            : >"$output"
        }
        verify_checksum() { return 0; }
        gzip() {
            [[ "$1" == -dc ]]
            printf '%s\n' \
                '#!/usr/bin/env bash' \
                'printf "%s\n" "${DMS_PRIVESC:-unset}" >"$DMS_PRIVESC_CAPTURE"' \
                'touch "$STACK_MARKER"'
        }
        run_dankinstall
        [[ -z "${DMS_PRIVESC+x}" ]]
    ) &>/dev/null || return 1
    [[ "$(cat "$observed")" == sudo ]]
}

test_greeter_healthy_skips_repair() {
    local calls
    calls="$(make_tempfile)"
    (
        have_command() { return 0; }
        dms() { printf '%s\n' "$*" >>"$calls"; }
        s() { return 99; }
        install_dms_greeter
    ) &>/dev/null || return 1
    ! grep -q '^greeter enable$' "$calls" || return 1
    [[ "$(grep -c '^greeter sync -y$' "$calls")" -eq 1 ]]
}

test_greeter_repairs_failed_status() {
    local calls
    calls="$(make_tempfile)"
    (
        have_command() { return 0; }
        dms() {
            printf '%s\n' "$*" >>"$calls"
            if [[ "$*" == 'greeter status' ]]; then
                [[ "$(grep -c '^greeter status$' "$calls")" -gt 1 ]]
            fi
        }
        install_dms_greeter
    ) &>/dev/null || return 1
    grep -q '^greeter enable$' "$calls"
    grep -q '^greeter sync -y$' "$calls"
}

test_dms_commands_select_sudo_and_forward_status() {
    local calls
    calls="$(make_tempfile)"
    (
        unset DMS_PRIVESC
        dms() {
            printf '%s|%s\n' "${DMS_PRIVESC:-unset}" "$*" >>"$calls"
            [[ "$1" != fail ]]
        }
        dms_cmd greeter sync -y
        if dms_cmd fail; then return 1; fi
        [[ -z "${DMS_PRIVESC+x}" ]]
    ) || return 1
    [[ "$(cat "$calls")" == $'sudo|greeter sync -y\nsudo|fail' ]]
}

test_dms_settings_override_merges_and_is_idempotent() {
    local home override before
    home="$(make_tempdir)"
    override="$(make_tempfile)"
    mkdir -p "$home/.config/DankMaterialShell"
    printf '{"keep":1,"nested":{"keep":1,"change":1},"array":[1],"use24HourClock":true}\n' >"$home/.config/DankMaterialShell/settings.json"
    printf '{"nested":{"change":2},"array":[2],"use24HourClock":false}\n' >"$override"
    (
        REAL_HOME="$home"
        DMS_SETTINGS_OVERRIDE="$override"
        apply_dms_settings_override
    ) &>/dev/null || return 1
    jq -e '.keep == 1 and .nested == {"keep":1,"change":2} and .array == [2] and .use24HourClock == false' \
        "$home/.config/DankMaterialShell/settings.json" &>/dev/null || return 1
    before="$(find "$home/.config/DankMaterialShell" -name 'settings.json.backup-*' | wc -l)"
    (
        REAL_HOME="$home"
        DMS_SETTINGS_OVERRIDE="$override"
        apply_dms_settings_override
    ) &>/dev/null || return 1
    [[ "$(find "$home/.config/DankMaterialShell" -name 'settings.json.backup-*' | wc -l)" -eq "$before" ]]
}

test_dms_settings_override_freezes_dankbar_layout() {
    local override="$ROOT_DIR/assets/dms-settings-override.json"
    jq -e 'type == "object" and (.barConfigs | type == "array") and (.barConfigs | length == 1)' "$override" &>/dev/null || return 1
    jq -e '
        (.barConfigs[0]) as $b
        | ($b.rightWidgets | map(if type == "object" then .id else . end)) as $right
        | ($b.leftWidgets | index("workspaceSwitcher")) != null
          and ($right | index("dockerToggle")) != null
          and ($right | index("keyboard_layout_name")) != null
          and ($right | index("controlCenterButton")) != null
    ' "$override" &>/dev/null
}

test_invalid_dms_json_preserves_settings() {
    local home override digest missing
    home="$(make_tempdir)"
    override="$(make_tempfile)"
    mkdir -p "$home/.config/DankMaterialShell"
    printf '{"keep":true}\n' >"$home/.config/DankMaterialShell/settings.json"
    printf '[]\n' >"$override"
    digest="$(sha256sum "$home/.config/DankMaterialShell/settings.json")"
    if (REAL_HOME="$home" DMS_SETTINGS_OVERRIDE="$override" apply_dms_settings_override) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$home/.config/DankMaterialShell/settings.json")" == "$digest" ]]
    printf '{invalid\n' >"$home/.config/DankMaterialShell/settings.json"
    printf '{}\n' >"$override"
    digest="$(sha256sum "$home/.config/DankMaterialShell/settings.json")"
    if (REAL_HOME="$home" DMS_SETTINGS_OVERRIDE="$override" apply_dms_settings_override) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$home/.config/DankMaterialShell/settings.json")" == "$digest" ]] || return 1
    missing="$home/missing-override.json"
    printf '{"keep":true}\n' >"$home/.config/DankMaterialShell/settings.json"
    digest="$(sha256sum "$home/.config/DankMaterialShell/settings.json")"
    if (REAL_HOME="$home" DMS_SETTINGS_OVERRIDE="$missing" apply_dms_settings_override) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$home/.config/DankMaterialShell/settings.json")" == "$digest" ]]
}

test_unexpected_dotfiles_remote_rejected() {
    local home
    home="$(make_tempdir)"
    git init -q "$home/.dotfiles"
    git -C "$home/.dotfiles" remote add origin https://example.com/wrong.git
    ( REAL_HOME="$home"; validate_existing_dotfiles ) &>/dev/null
    local status=$?
    [[ $status -ne 0 ]]
}

test_stow_conflict_stops_dotfile_install() {
    local home
    home="$(make_tempdir)"
    mkdir -p "$home/.dotfiles"
    (
        REAL_HOME="$home"
        REAL_USER=tester
        validate_existing_dotfiles() { :; }
        validate_dotfiles_fish() { :; }
        validate_dotfiles_alacritty() { :; }
        validate_dotfiles_makefile() { :; }
        make_cmd() { return 1; }
        install_dotfiles
    ) &>/dev/null
    local status=$?
    [[ $status -ne 0 ]]
}

test_alacritty_dotfiles_are_required_and_parsed() {
    local dotdir config observed
    dotdir="$(make_tempdir)"
    config="$dotdir/alacritty/.config/alacritty/alacritty.toml"
    if validate_dotfiles_alacritty "$dotdir" &>/dev/null; then return 1; fi
    mkdir -p "$(dirname "$config")"
    printf 'not = valid = toml\n' >"$config"
    if ( alacritty_cmd() { return 1; }; validate_dotfiles_alacritty "$dotdir" ) &>/dev/null; then return 1; fi
    observed="$(make_tempfile)"
    (
        alacritty_cmd() {
            [[ "$1 $2 $3 $4" == 'migrate --dry-run --silent --config-file' ]]
            [[ "$5" == "$config" ]]
            printf parsed >"$observed"
        }
        validate_dotfiles_alacritty "$dotdir"
    ) || return 1
    [[ "$(cat "$observed")" == parsed ]]
}

test_dotfiles_makefile_targets_are_required() {
    local home dotdir
    home="$(make_tempdir)"
    dotdir="$home/.dotfiles"
    mkdir -p "$dotdir"
    if ( REAL_HOME="$home"; validate_dotfiles_makefile "$dotdir" ) &>/dev/null; then return 1; fi
    printf 'all:\n\t@:\ncheck:\n\t@:\n' >"$dotdir/Makefile"
    ( REAL_HOME="$home"; make_cmd() { make "$@"; }; validate_dotfiles_makefile "$dotdir" ) || return 1
}

test_alacritty_config_migration_is_backed_up_and_rerunnable() {
    local home dotdir destination backup
    home="$(make_tempdir)"
    dotdir="$home/.dotfiles"
    destination="$home/.config/alacritty/alacritty.toml"
    mkdir -p "$dotdir/fish" "$dotdir/zed" "$(dirname "$dotdir/alacritty/.config/alacritty/alacritty.toml")" \
        "$home/.config/alacritty"
    printf '%s\n' \
        '.PHONY: all check' \
        'PKGS := fish alacritty zed' \
        'TARGET ?= $(HOME)' \
        'all:' \
        $'\tstow -t "$(TARGET)" $(PKGS)' \
        'check:' \
        $'\tstow --simulate -t "$(TARGET)" $(PKGS)' \
        >"$dotdir/Makefile"
    printf 'font.size = 12\n' >"$dotdir/alacritty/.config/alacritty/alacritty.toml"
    printf 'font.size = 99\n' >"$destination"
    printf 'generated theme\n' >"$home/.config/alacritty/dank-theme.toml"
    (
        REAL_HOME="$home"
        REAL_USER=tester
        validate_existing_dotfiles() { :; }
        validate_dotfiles_fish() { :; }
        validate_dotfiles_alacritty() { :; }
        make_cmd() { make "$@"; }
        getent() { printf 'tester:x:1000:1000::%s:/usr/bin/fish\n' "$home"; }
        install_dotfiles
        install_dotfiles
    ) &>/dev/null || return 1
    [[ -L "$destination" ]] || return 1
    [[ "$(readlink -f "$destination")" == "$dotdir/alacritty/.config/alacritty/alacritty.toml" ]] || return 1
    backup="$(find "$home/.config/alacritty" -maxdepth 1 -name 'alacritty.toml.backup-*' -print)"
    [[ -n "$backup" && "$(wc -l <<<"$backup")" -eq 1 ]] || return 1
    grep -Fxq 'font.size = 99' "$backup" || return 1
    grep -Fxq 'generated theme' "$home/.config/alacritty/dank-theme.toml"
}

test_required_failure_is_returned() {
    ! (
        s() { return 1; }
        install_required_group "required test" package
    ) &>/dev/null
}

test_modules_are_discovered_in_lexical_order() {
    local directory
    directory="$(make_tempdir)"
    printf 'MODULE_LOAD_ORDER+=(first)\n' >"$directory/1-first.sh"
    printf 'MODULE_LOAD_ORDER+=(second)\n' >"$directory/2-second.sh"
    printf 'MODULE_LOAD_ORDER+=(third)\n' >"$directory/3-third.sh"
    assert_eq "$( MODULE_LOAD_ORDER=(); source_modules "$directory" >/dev/null; printf '%s' "${MODULE_LOAD_ORDER[*]}" )" 'first second third'
}

test_missing_module_is_fatal() {
    ! ( source_required modules/does-not-exist.sh ) &>/dev/null
}

test_empty_module_directory_is_fatal() {
    local directory status
    directory="$(make_tempdir)"
    ( source_modules "$directory" ) &>/dev/null
    status=$?
    [[ $status -ne 0 ]]
}

test_unreadable_module_is_fatal() {
    local directory file status
    directory="$(make_tempdir)"
    file="$directory/1-unreadable.sh"
    printf ':\n' >"$file"
    chmod 000 "$file"
    ( source_modules "$directory" ) &>/dev/null
    status=$?
    chmod 600 "$file"
    [[ $status -ne 0 ]]
}

test_system_phase_order() {
    local calls
    calls="$(make_tempfile)"
    (
        optimize_dnf() { printf '%s\n' optimize >>"$calls"; }
        configure_timezone() { printf '%s\n' timezone >>"$calls"; }
        configure_time_format() { printf '%s\n' timefmt >>"$calls"; }
        install_chrome() { printf '%s\n' chrome >>"$calls"; }
        debloat_system() { printf '%s\n' debloat >>"$calls"; }
        system_update() { printf '%s\n' upgrade >>"$calls"; }
        enable_danklinux_copr() { printf '%s\n' copr >>"$calls"; }
        step() { :; }
        run_system_phase
    )
    [[ "$(tr '\n' ' ' <"$calls")" == 'optimize timezone timefmt chrome debloat upgrade copr ' ]]
}

test_time_format_sets_lc_time_once() {
    local dir calls
    dir="$(make_tempdir)"
    calls="$(make_tempfile)"
    printf 'LANG=ar_JO.UTF-8\n' >"$dir/locale.conf"
    (
        LOCALE_CONF="$dir/locale.conf"
        s() {
            printf '%s\n' "$*" >>"$calls"
            [[ "$1 $2 $3" == 'localectl set-locale LC_TIME=en_US.UTF-8' ]] && printf 'LC_TIME=en_US.UTF-8\n' >>"$dir/locale.conf"
        }
        configure_time_format
    ) &>/dev/null || return 1
    grep -Fxq 'localectl set-locale LC_TIME=en_US.UTF-8' "$calls" || return 1
    : >"$calls"
    (
        LOCALE_CONF="$dir/locale.conf"
        configure_time_format
    ) &>/dev/null || return 1
    [[ ! -s "$calls" ]]
    printf 'LANG=en_US.UTF-8\n' >"$dir/locale.conf"
    (
        LOCALE_CONF="$dir/locale.conf"
        configure_time_format
    ) &>/dev/null || return 1
    [[ ! -s "$calls" ]]
}

test_chrome_uses_fedora_managed_repository() {
    local calls
    calls="$(make_tempfile)"
    (
        rpm() { return 1; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        have_command() { [[ "$1" == xdg-settings ]]; }
        xdg-settings() {
            [[ "$1" == set ]] || printf 'google-chrome.desktop\n'
        }
        install_chrome
    ) &>/dev/null
    assert_ok grep -Fxq 'dnf install -y fedora-workstation-repositories' "$calls"
    assert_ok grep -Fxq 'dnf config-manager enable google-chrome' "$calls"
    assert_ok grep -Fxq 'dnf install -y google-chrome-stable' "$calls"
    assert_file_lacks "$calls" 'addrepo'
}

test_existing_chrome_skips_package_install() {
    local calls
    calls="$(make_tempfile)"
    (
        rpm() { return 0; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        have_command() { [[ "$1" == xdg-settings ]]; }
        xdg-settings() { [[ "$1" == set ]] || printf 'google-chrome.desktop\n'; }
        install_chrome
    ) &>/dev/null
    assert_eq "$(cat "$calls")" 'dnf config-manager enable google-chrome'
}

test_core_packages_include_essentials_and_exclude_bootstrap() {
    # Fear: an essential silently drops out, or a bootstrap-only/unwanted package
    # creeps into the core set. Assert those invariants, not the verbatim list.
    local pkg
    for pkg in alacritty xdg-terminal-exec xwayland-satellite wl-clipboard fish; do
        [[ " ${CORE_PACKAGES[*]} " == *" $pkg "* ]] || fail_assert "CORE_PACKAGES missing essential: $pkg"
    done
    for pkg in git pciutils unrar; do
        [[ " ${CORE_PACKAGES[*]} " != *" $pkg "* ]] || fail_assert "CORE_PACKAGES should not contain: $pkg"
    done
    [[ "$(declare -f install_kickstart)" != *'fd-find'* ]] || fail_assert "install_kickstart references fd-find"
}

test_brew_owns_portable_cli_tools() {
    local formula
    for formula in jq stow fd ripgrep tree-sitter-cli bat eza; do
        [[ " ${BREW_FORMULAE[*]} " == *" $formula "* ]] || return 1
    done
    grep -Fq '$(brew_bin_dir)/jq' <<<"$(declare -f jq_cmd)" || return 1
    grep -Fq 'PATH="$(brew_bin_dir):$PATH" make' <<<"$(declare -f make_cmd)"
    [[ -z "$(declare -F stow_cmd)" ]]
    [[ " ${BREW_FORMULAE[*]} " == *" steipete/tap/codexbar " ]]
}

test_workstation_dependency_order() {
    local calls
    calls="$(make_tempfile)"
    (
        step() { :; }
        run_dankinstall() { printf '%s\n' dank >>"$calls"; }
        install_core_packages() { printf '%s\n' core >>"$calls"; }
        install_niri_fish_completions() { printf '%s\n' completions >>"$calls"; }
        install_homebrew() { printf '%s\n' brew >>"$calls"; }
        install_brew_formulae() { printf '%s\n' formulae >>"$calls"; }
        install_commands() { printf '%s\n' commands >>"$calls"; }
        install_webapps() { printf '%s\n' webapps >>"$calls"; }
        apply_dms_settings_override() { printf '%s\n' dms-settings >>"$calls"; }
        install_dms_greeter() { printf '%s\n' greeter >>"$calls"; }
        install_zed() { printf '%s\n' zed >>"$calls"; }
        install_nerd_font() { printf '%s\n' font >>"$calls"; }
        configure_xdg_terminal() { printf '%s\n' terminal >>"$calls"; }
        configure_niri() { printf '%s\n' niri >>"$calls"; }
        install_niri_edge_indicators() { printf '%s\n' indicators >>"$calls"; }
        configure_git() { printf '%s\n' git >>"$calls"; }
        ensure_github_auth() { printf '%s\n' github >>"$calls"; }
        install_dotfiles() { printf '%s\n' dotfiles >>"$calls"; }
        install_fish_plugins() { printf '%s\n' fish-plugins >>"$calls"; }
        install_mise_tools() { printf '%s\n' mise >>"$calls"; }
        install_docker() { printf '%s\n' docker >>"$calls"; }
        create_xdg_dirs() { printf '%s\n' dirs >>"$calls"; }
        set_graphical_target() { printf '%s\n' target >>"$calls"; }
        run_workstation_phase
    )
    [[ "$(tr '\n' ' ' <"$calls")" == 'dank core completions brew formulae commands webapps dms-settings greeter zed font terminal niri indicators git github dotfiles fish-plugins mise docker dirs target ' ]]
}

test_niri_fish_completions_are_generated_safely() {
    local home destination inode digest
    home="$(make_tempdir)"
    destination="$home/.local/share/fish/vendor_completions.d/niri.fish"
    mkdir -p "$home/.dotfiles/fish/.config/fish"
    (
        REAL_HOME="$home"
        niri() {
            [[ "$1 $2" == 'completions fish' ]] || return 1
            printf 'complete -c niri -a msg\n'
        }
        install_niri_fish_completions
    ) &>/dev/null || return 1
    [[ -f "$destination" ]] || return 1
    fish -n "$destination" || return 1
    [[ ! -e "$home/.dotfiles/fish/.config/fish/completions/niri.fish" ]] || return 1
    inode="$(stat -c '%i' "$destination")"
    (
        REAL_HOME="$home"
        niri() { printf 'complete -c niri -a msg\n'; }
        install_niri_fish_completions
    ) &>/dev/null || return 1
    [[ "$(stat -c '%i' "$destination")" == "$inode" ]] || return 1
    digest="$(sha256sum "$destination")"
    if (
        REAL_HOME="$home"
        niri() { printf 'not a completion\n'; }
        install_niri_fish_completions
    ) &>/dev/null; then
        return 1
    fi
    [[ "$(sha256sum "$destination")" == "$digest" ]] || return 1
}

test_fish_config_symlink_is_migrated_without_losing_state() {
    local home dotdir config
    home="$(make_tempdir)"
    dotdir="$home/.dotfiles"
    config="$home/.config/fish"
    mkdir -p "$dotdir/fish/.config/fish" "$home/.config"
    printf 'SETUVAR test:value\n' >"$dotdir/fish/.config/fish/fish_variables"
    ln -s ../.dotfiles/fish/.config/fish "$config"
    ( REAL_HOME="$home"; prepare_fish_config_directory "$dotdir" ) || return 1
    [[ -d "$config" && ! -L "$config" ]] || return 1
    grep -Fxq 'SETUVAR test:value' "$config/fish_variables"
}

test_fisher_updates_plugins_and_removes_legacy_install() {
    local home calls
    home="$(make_tempdir)"
    calls="$(make_tempfile)"
    mkdir -p "$home/.local/share/fish/niri-setup/fzf.fish" "$home/.local/share/fish/vendor_conf.d"
    touch "$home/.local/share/fish/vendor_conf.d/niri-setup-fzf.fish"
    (
        REAL_HOME="$home"
        curl() {
            local previous='' arg output
            for arg in "$@"; do
                [[ "$previous" == -o ]] && output=$arg
                previous=$arg
            done
            printf 'function fisher\nend\n' >"$output"
        }
        system_fish_cmd() { printf '%s\n' "$*" >>"$calls"; }
        install_fish_plugins
    ) &>/dev/null || return 1
    grep -Fq 'fisher update' "$calls" || return 1
    [[ ! -e "$home/.local/share/fish/niri-setup/fzf.fish" ]] || return 1
    [[ ! -e "$home/.local/share/fish/vendor_conf.d/niri-setup-fzf.fish" ]] || return 1
}

test_debloat_allowlist_only() {
    local actual
    actual="$({
        rpm() { printf '%s\n' firefox firefox-langpacks libreoffice-core gnome-tour gnome-shell gdm nautilus kernel; }
        installed_debloat_packages
    })"
    [[ "$actual" == $'firefox\nfirefox-langpacks\nlibreoffice-core\ngnome-tour' ]]
}

test_debloat_noop_when_absent() {
    (
        rpm() { printf '%s\n' nautilus kernel; }
        s() { return 1; }
        debloat_system
    ) &>/dev/null
}

test_brew_installs_only_missing_formulae() {
    local calls
    calls="$(make_tempfile)"
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
    local calls
    calls="$(make_tempfile)"
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
    local calls protocol=https
    calls="$(make_tempfile)"
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
    local calls
    calls="$(make_tempfile)"
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
    # shellcheck disable=SC2016 # These lines form a script evaluated later.
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

test_launch_or_focus_behaviors() {
    local dir webapp_helper tui_helper niri_mock setsid_mock windows_file focus_log launch_log marker state_dir hostile first_pid second_pid
    dir="$(make_tempdir)"
    webapp_helper="$ROOT_DIR/bin/webapp-launch-or-focus"
    tui_helper="$ROOT_DIR/bin/tui-launch-or-focus"
    niri_mock="$dir/niri"
    setsid_mock="$dir/setsid"
    windows_file="$dir/windows.json"
    focus_log="$dir/focus.log"
    launch_log="$dir/launch.log"
    marker="$dir/launched"
    hostile="$dir/should-not-exist"
    PATH="$dir:$ROOT_DIR/bin:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run"
    export WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log"
    state_dir="$XDG_RUNTIME_DIR/launch-or-focus"
    # shellcheck disable=SC2016 # These scripts are test doubles evaluated later.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$*" == "msg -j windows" ]]; then' \
        '    if [[ -n "${LAUNCH_MARKER:-}" && -e "$LAUNCH_MARKER" ]]; then' \
        '        printf "[{\"id\":88,\"app_id\":\"%s\",\"is_focused\":true}]\\n" "${LAUNCH_APP_ID:-niri-webapp-reddit}"' \
        '    else' \
        '        cat "$WINDOWS_FILE"' \
        '    fi' \
        'elif [[ "$1 $2 $3" == "msg action focus-window" ]]; then' \
        '    printf "%s\\n" "$*" >>"$FOCUS_LOG"' \
        'else' \
        '    exit 2' \
        'fi' >"$niri_mock"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        '[[ ! -e /proc/$$/fd/9 ]] || printf "<fd9-open>\\n" >>"$LAUNCH_LOG.fd"' \
        'printf "<%s>\\n" "$@" >>"$LAUNCH_LOG"' \
        '[[ -z "${LAUNCH_MARKER:-}" ]] || touch "$LAUNCH_MARKER"' \
        '[[ -z "${SETSID_DELAY:-}" ]] || sleep "$SETSID_DELAY"' \
        >"$setsid_mock"
    chmod +x "$niri_mock" "$setsid_mock"

    printf '[]\n' >"$windows_file"
    rm -f "$marker"
    : >"$launch_log"
    : >"$focus_log"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker "$tui_helper" lazydocker "\$(touch $hostile)"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker "$tui_helper" lazydocker --debug
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$launch_log")" == 1 ]] || return 1
    grep -Fxq 'msg action focus-window --id 88' "$focus_log" || return 1
    grep -Fxq "<\$(touch $hostile)>" "$launch_log" || return 1
    [[ ! -e "$hostile" ]] || return 1

    rm -f "$marker"
    : >"$launch_log"
    : >"$focus_log"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker SETSID_DELAY=0.3 "$tui_helper" lazydocker &
    first_pid=$!
    sleep 0.05
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker SETSID_DELAY=0.3 "$tui_helper" lazydocker &
    second_pid=$!
    wait "$first_pid"
    wait "$second_pid"
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$launch_log")" == 1 ]] || return 1

    rm -f "$marker"
    : >"$launch_log"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker "$tui_helper" lazydocker
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$launch_log")" == 1 ]] || return 1

    rm -f "$marker"
    : >"$launch_log"
    if "$tui_helper" lazydocker 2>/dev/null; then
        return 1
    fi
    grep -Fxq '<--app-id=local.tui.lazydocker>' "$launch_log" || return 1

    rm -f "$marker"
    : >"$launch_log"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.btop "$tui_helper" btop
    grep -Fxq '<--app-id=local.tui.btop>' "$launch_log" || return 1

    mkdir -p "$state_dir"
    printf '77\n' >"$state_dir/niri-webapp-notion.window-id"
    printf '[{"id":77,"app_id":"google-chrome","is_focused":false}]\n' >"$windows_file"
    : >"$focus_log"
    "$webapp_helper" notion https://www.notion.so
    grep -Fxq 'msg action focus-window --id 77' "$focus_log" || return 1

    printf '[]\n' >"$windows_file"
    rm -f "$marker"
    : >"$launch_log"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=niri-webapp-notion "$webapp_helper" notion https://www.notion.so
    [[ "$(cat "$state_dir/niri-webapp-notion.window-id")" == 88 ]] || return 1
    grep -Fxq '<--class=niri-webapp-notion>' "$launch_log" || return 1

    rm -f "$marker" "$state_dir/niri-webapp-reddit.window-id"
    : >"$launch_log"
    LAUNCH_MARKER="$marker" "$webapp_helper" reddit https://www.reddit.com
    [[ "$(cat "$state_dir/niri-webapp-reddit.window-id")" == 88 ]] || return 1
    grep -Fxq '<--app=https://www.reddit.com>' "$launch_log" || return 1
    grep -Fxq '<--class=niri-webapp-reddit>' "$launch_log" || return 1

    rm -f "$marker" "$state_dir/niri-webapp-chatgpt.window-id"
    : >"$launch_log"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=niri-webapp-chatgpt SETSID_DELAY=0.3 "$webapp_helper" chatgpt https://chatgpt.com &
    first_pid=$!
    sleep 0.05
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=niri-webapp-chatgpt SETSID_DELAY=0.3 "$webapp_helper" chatgpt https://chatgpt.com &
    second_pid=$!
    wait "$first_pid"
    wait "$second_pid"
    [[ "$(grep -Fxc '<--class=niri-webapp-chatgpt>' "$launch_log")" == 1 ]] || return 1

    rm -f "$marker" "$state_dir/niri-webapp-gmail.window-id"
    : >"$launch_log"
    if "$webapp_helper" gmail https://mail.google.com 2>/dev/null; then
        return 1
    fi
    grep -Fxq '<--class=niri-webapp-gmail>' "$launch_log" || return 1
    if grep -Fq '<fd9-open>' "$launch_log.fd" 2>/dev/null; then return 1; fi
    if grep -Fq eval "$webapp_helper" || grep -Fq eval "$tui_helper"; then return 1; fi
}

test_launch_or_focus_base_contract() {
    local dir base niri_mock setsid_mock windows_file focus_log launch_log marker state_dir
    dir="$(make_tempdir)"
    base="$ROOT_DIR/bin/launch-or-focus"
    niri_mock="$dir/niri"
    setsid_mock="$dir/setsid"
    windows_file="$dir/windows.json"
    focus_log="$dir/focus.log"
    launch_log="$dir/launch.log"
    marker="$dir/launched"
    PATH="$dir:$(dirname "$BREW_BIN"):$PATH"
    export XDG_RUNTIME_DIR="$dir/run"
    export WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log"
    state_dir="$XDG_RUNTIME_DIR/launch-or-focus"
    # shellcheck disable=SC2016 # These scripts are test doubles evaluated later.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$*" == "msg -j windows" ]]; then' \
        '    if [[ -n "${LAUNCH_MARKER:-}" && -e "$LAUNCH_MARKER" ]]; then' \
        '        printf "[{\"id\":99,\"app_id\":\"%s\",\"is_focused\":true}]\\n" "${LAUNCH_APP_ID:-x}"' \
        '    else' \
        '        cat "$WINDOWS_FILE"' \
        '    fi' \
        'elif [[ "$1 $2 $3" == "msg action focus-window" ]]; then' \
        '    printf "%s\\n" "$*" >>"$FOCUS_LOG"' \
        'else' \
        '    exit 2' \
        'fi' >"$niri_mock"
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'printf "<%s>\\n" "$@" >>"$LAUNCH_LOG"' \
        '[[ -z "${LAUNCH_MARKER:-}" ]] || touch "$LAUNCH_MARKER"' \
        >"$setsid_mock"
    chmod +x "$niri_mock" "$setsid_mock"

    # Focus an existing window by app_id; never launch.
    printf '[{"id":42,"app_id":"test.app","is_focused":false}]\n' >"$windows_file"
    : >"$focus_log"; : >"$launch_log"; rm -f "$marker"
    "$base" test.app placeholder
    assert_ok grep -Fxq 'msg action focus-window --id 42' "$focus_log"
    [[ ! -s "$launch_log" ]] || fail_assert "launched when focusing an existing window"
    assert_eq "$(cat "$state_dir/test.app.window-id")" 42

    # Launch and cache the new window when none matches.
    printf '[]\n' >"$windows_file"
    : >"$focus_log"; : >"$launch_log"; rm -f "$marker" "$state_dir/test.app2.window-id"
    LAUNCH_MARKER="$marker" LAUNCH_APP_ID=test.app2 "$base" test.app2 mycmd --flag
    assert_ok grep -Fxq '<mycmd>' "$launch_log"
    assert_ok grep -Fxq '<--flag>' "$launch_log"
    assert_eq "$(cat "$state_dir/test.app2.window-id")" 99

    # Reject a call without a launch command.
    assert_fails "$base" test.app3 2>/dev/null
    assert_file_lacks "$base" 'eval'
}

test_webapp_manifest_delegates_to_installer() {
    local calls
    calls="$(make_tempfile)"
    (
        webapp_install_cmd() { printf '%s\t%s\t%s\t%s\n' "$@" >>"$calls"; }
        install_webapps
    ) &>/dev/null || return 1
    [[ "$(wc -l <"$calls")" -eq 8 ]] || return 1
    grep -Fxq $'notion\tNotion\thttps://www.notion.so\tnotion.so' "$calls"
    grep -Fxq $'google-calendar\tGoogle Calendar\thttps://calendar.google.com\tcalendar.google.com' "$calls"
    grep -Fxq $'discord\tDiscord\thttps://discord.com/app\tdiscord.com' "$calls"
}

test_webapp_install_creates_idempotent_launcher() {
    local dir applications icons database_log helper desktop
    dir="$(make_tempdir)"
    applications="$dir/.local/share/applications"
    icons="$dir/.local/share/icons/hicolor/128x128/apps"
    database_log="$dir/database.log"
    helper="$ROOT_DIR/bin/webapp-install"; desktop="$applications/niri-webapp-notion.desktop"
    # shellcheck disable=SC2016 # These lines form test scripts evaluated later.
    printf '%s\n' '#!/usr/bin/env bash' 'while (($#)); do if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi; done' 'printf png >"$output"' >"$dir/curl"
    printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$*" >>"$WEBAPP_DATABASE_LOG"' >"$dir/update-desktop-database"
    chmod +x "$dir/curl" "$dir/update-desktop-database"
    export HOME="$dir" PATH="$dir:$PATH" WEBAPP_DATABASE_LOG="$database_log"
    "$helper" notion Notion https://www.notion.so notion.so || return 1
    grep -Fxq 'Name=Notion' "$desktop"
    grep -Fxq 'Exec=/usr/local/bin/webapp-launch-or-focus notion https://www.notion.so' "$desktop"
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
    dir="$(make_tempdir)"; helper="$ROOT_DIR/bin/webapp-install"
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

test_niri_edge_indicators_are_installed_idempotently() {
    local home calls
    home="$(make_tempdir)"; calls="$(make_tempfile)"
    (
        REAL_HOME="$home"
        user_systemctl_cmd() { printf '%s\n' "$*" >>"$calls"; }
        install_niri_edge_indicators
        install_niri_edge_indicators
    ) &>/dev/null || return 1
    [[ "$(readlink "$home/.config/quickshell/niri-edge-indicators")" == "$ROOT_DIR/assets/niri-edge-indicators" ]] || return 1
    [[ "$(readlink "$home/.config/systemd/user/niri-edge-indicators.service")" == "$ROOT_DIR/assets/niri-edge-indicators.service" ]] || return 1
    [[ "$(grep -c '^daemon-reload$' "$calls")" -eq 2 ]] || return 1
    [[ "$(grep -c '^enable --now niri-edge-indicators.service$' "$calls")" -eq 2 ]] || return 1
    [[ "$(find "$home" -name '*.backup-*' | wc -l)" -eq 0 ]]
}

test_entrypoints_and_update_contract() {
    [[ -x "$ROOT_DIR/setup.sh" ]] || fail_assert "setup.sh not executable"
    [[ -x "$ROOT_DIR/install.sh" ]] || fail_assert "install.sh not executable"
    [[ ! -e "$ROOT_DIR/assets/niri-setup-update" ]] || fail_assert "stale niri-setup-update present"
    [[ ! -e "$ROOT_DIR/setup-fedora-niri-dms.sh" ]] || fail_assert "stale setup-fedora-niri-dms.sh present"
    assert_file_contains "$ROOT_DIR/install.sh" 'git clone --branch main "$REPO_URL" "$INSTALL_DIR"'
    assert_file_contains "$ROOT_DIR/install.sh" 'git -C "$INSTALL_DIR" pull --ff-only origin main'
    assert_file_contains "$ROOT_DIR/install.sh" 'run_update'
}

test_commands_install_every_bin_script_and_reject_invalid_entries() {
    local calls expected invalid
    calls="$(make_tempfile)"
    (
        install_root_symlink_with_backup() { printf '%s %s\n' "$1" "$2" >>"$calls"; }
        install_commands
    ) &>/dev/null || return 1
    expected="$(find "$ROOT_DIR/bin" -maxdepth 1 -type f -executable | wc -l)"
    [[ "$(wc -l <"$calls")" -eq "$expected" ]] || return 1
    grep -Fxq "$ROOT_DIR/bin/webapp-install /usr/local/bin/webapp-install" "$calls"
    grep -Fxq "$ROOT_DIR/bin/tui-launch-or-focus /usr/local/bin/tui-launch-or-focus" "$calls"
    grep -Fxq "$ROOT_DIR/bin/workstation-update /usr/local/bin/workstation-update" "$calls"
    invalid="$(make_tempdir)"
    printf 'not executable\n' >"$invalid/broken"
    if ( COMMANDS_DIR="$invalid"; install_commands ) &>/dev/null; then return 1; fi
}

test_runtime_commands_and_workstation_modules_are_organized() {
    local command component
    for command in docker-toggle launch-or-focus tui-launch-or-focus webapp-install webapp-launch-or-focus workstation-update; do
        [[ -x "$ROOT_DIR/bin/$command" ]] || return 1
    done
    for command in docker-toggle launch-or-focus-tui launch-or-focus-webapp; do
        [[ ! -e "$ROOT_DIR/assets/$command" ]] || return 1
    done
    for component in desktop development dotfiles commands webapps docker; do
        [[ -r "$ROOT_DIR/modules/workstation/$component.sh" ]] || return 1
    done
    grep -Fq 'source_modules "$ROOT_DIR/modules/workstation"' "$ROOT_DIR/modules/2-workstation.sh" || return 1
    grep -Fq 'exec "$repo_root/install.sh" "$@"' "$ROOT_DIR/bin/workstation-update"
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
    local calls
    calls="$(make_tempfile)"
    # shellcheck disable=SC2030 # Test-only environment assignment is intentionally scoped to the subshell.
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
    dir="$(make_tempdir)"
    bin="$dir/bin"
    marker="$dir/setup-ran"
    mkdir -p "$bin"
    # shellcheck disable=SC2016 # This creates a Git test double evaluated later.
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'if [[ "$1" == clone ]]; then' \
        '    destination="${@: -1}"' \
        '    mkdir -p "$destination/.git"' \
        '    printf "%s\n" "#!/usr/bin/env bash" "printf ran >\"\$INSTALL_PIPE_MARKER\"" >"$destination/setup.sh"' \
        '    chmod +x "$destination/setup.sh"' \
        'fi' >"$bin/git"
    chmod +x "$bin/git"
    PATH="$bin:/usr/bin:/bin" NIRI_SETUP_DIR="$dir/managed" INSTALL_PIPE_MARKER="$marker" \
        bash <"$ROOT_DIR/install.sh"
    assert_eq "$(cat "$marker")" ran
}

test_install_pause_preserves_update_status() {
    local calls status
    calls="$(make_tempfile)"
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

test_niri_override_neutralizes_dangerous_defaults() {
    # Fear: a surprising/destructive default bind survives, or a window rule forces
    # fullscreen. The non-destructive nav/app shortcuts are not mirrored here.
    local override="$ROOT_DIR/assets/niri-overrides.kdl"
    assert_file_contains "$override" 'Mod+Q hotkey-overlay-title=null { spawn "true"; }'
    assert_file_contains "$override" 'Mod+D hotkey-overlay-title=null { spawn "true"; }'
    assert_file_contains "$override" 'Mod+W repeat=false hotkey-overlay-title="Close Window" { close-window; }'
    assert_file_lacks "$override" 'open-fullscreen true'
}

test_edge_indicator_wiring() {
    # Fear: the edge indicator regresses its show-when-scrollable logic or its
    # click/hover wiring (the clickability already broke once).
    local indicator="$ROOT_DIR/assets/niri-edge-indicators/shell.qml"
    assert_file_contains "$indicator" 'focusedColumn > 1'
    assert_file_contains "$indicator" 'focusedColumn < maximumColumn'
    assert_file_contains "$indicator" 'cursorShape: Qt.PointingHandCursor'
    assert_file_contains "$indicator" 'hover.containsMouse'
    assert_file_contains "$indicator" 'focus-column-left'
    assert_file_contains "$indicator" 'focus-column-right'
}

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

test_zed_installs_only_when_missing() {
    local home
    home="$(make_tempdir)"
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
    local calls
    calls="$(make_tempfile)"
    ( git() { printf '%s\n' "$*" >>"$calls"; }; configure_git )
    assert_file_contains "$calls" 'config --global init.defaultBranch main'
    assert_file_contains "$calls" 'config --global user.name '
    assert_file_contains "$calls" 'config --global user.email '
}

test_both_dotfiles_origins_are_accepted() {
    local dir
    dir="$(make_tempdir)"
    git init -q "$dir"
    git -C "$dir" remote add origin "$DOTFILES_REPO_HTTPS"
    assert_ok git_remote_matches "$dir" "$DOTFILES_REPO_HTTPS" "$DOTFILES_REPO_SSH"
    git -C "$dir" remote set-url origin "$DOTFILES_REPO_SSH"
    assert_ok git_remote_matches "$dir" "$DOTFILES_REPO_HTTPS" "$DOTFILES_REPO_SSH"
    git -C "$dir" remote set-url origin https://example.com/dotfiles.git
    assert_fails git_remote_matches "$dir" "$DOTFILES_REPO_HTTPS" "$DOTFILES_REPO_SSH"
}

test_fish_brew_initialization_must_precede_prefix() {
    local dotdir before
    dotdir="$(make_tempdir)"
    mkdir -p "$dotdir/fish/.config/fish"
    printf 'jorgebucaran/fisher\nPatrickF1/fzf.fish\n' >"$dotdir/fish/.config/fish/fish_plugins"
    printf '%s\n' \
        'eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)' \
        'mise activate fish | source' \
        'starship init fish | source' \
        'set prefix (brew --prefix)' \
        >"$dotdir/fish/.config/fish/config.fish"
    before="$(sha256sum "$dotdir/fish/.config/fish/config.fish")"
    validate_dotfiles_fish "$dotdir"
    [[ "$before" == "$(sha256sum "$dotdir/fish/.config/fish/config.fish")" ]]
    printf 'set prefix (brew --prefix)\neval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)\nmise activate fish | source\nstarship init fish | source\n' >"$dotdir/fish/.config/fish/config.fish"
    if validate_dotfiles_fish "$dotdir" &>/dev/null; then return 1; fi
}

test_dotfile_install_does_not_edit_checkout() {
    local home config before calls
    home="$(make_tempdir)"
    calls="$(make_tempfile)"
    config="$home/.dotfiles/fish/.config/fish/config.fish"
    mkdir -p "$(dirname "$config")" "$home/.dotfiles/alacritty/.config/alacritty" "$home/.dotfiles/zed"
    printf 'jorgebucaran/fisher\nPatrickF1/fzf.fish\n' >"$(dirname "$config")/fish_plugins"
    printf '%s\n' \
        'eval (/home/linuxbrew/.linuxbrew/bin/brew shellenv)' \
        'mise activate fish | source' \
        'starship init fish | source' \
        >"$config"
    before="$(sha256sum "$config")"
    (
        REAL_HOME="$home"
        REAL_USER=tester
        validate_existing_dotfiles() { :; }
        validate_dotfiles_alacritty() { :; }
        validate_dotfiles_makefile() { :; }
        make_cmd() { return 0; }
        getent() { printf 'tester:x:1000:1000::%s:/bin/bash\n' "$home"; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        install_dotfiles
    )
    assert_eq "$before" "$(sha256sum "$config")"
    assert_ok grep -Fxq 'chsh -s /usr/bin/fish tester' "$calls"
}

test_nerd_font_discovery_is_exact() {
    ( fc-match() { printf 'JetBrainsMono Nerd Font,JetBrainsMono NF\n'; }; nerd_font_present )
    if ( fc-match() { printf 'JetBrains Mono\n'; }; nerd_font_present ); then return 1; fi
    if ( fc-match() { printf 'DejaVu Sans Mono\n'; }; nerd_font_present ); then return 1; fi
}

test_installed_nerd_font_skips_download() {
    (
        REAL_HOME=/tmp
        nerd_font_present() { return 0; }
        curl() { return 1; }
        install_nerd_font
    ) &>/dev/null
}

test_niri_include_is_last_and_idempotent() {
    local home file before
    home="$(make_tempdir)"; file="$home/config.kdl"
    printf 'include "dms/a.kdl"\ninclude "niri-overrides.kdl"\nbinds {}\n' >"$file"
    ( backup_path() { :; }; ensure_niri_override_include "$file" )
    assert_eq "$(grep -c 'include "niri-overrides.kdl"' "$file")" 1
    assert_eq "$(tail -n 1 "$file")" 'include "niri-overrides.kdl"'
    before="$(sha256sum "$file")"
    ( backup_path() { return 1; }; ensure_niri_override_include "$file" )
    assert_eq "$before" "$(sha256sum "$file")"
}

test_niri_validation_failure_rolls_back() {
    local home original
    home="$(make_tempdir)"; mkdir -p "$home/.config/niri/dms"
    printf 'include "dms/layout.kdl"\n' >"$home/.config/niri/config.kdl"
    printf 'output "eDP-1" { scale 1.0 }\n' >"$home/.config/niri/dms/outputs.kdl"
    printf 'old override\n' >"$home/.config/niri/niri-overrides.kdl"
    original="$(sha256sum "$home/.config/niri/config.kdl" "$home/.config/niri/dms/outputs.kdl" "$home/.config/niri/niri-overrides.kdl")"
    if ( REAL_HOME="$home"; backup_path() { :; }; niri() { return 1; }; configure_niri ) &>/dev/null; then
        return 1
    fi
    [[ "$original" == "$(sha256sum "$home/.config/niri/config.kdl" "$home/.config/niri/dms/outputs.kdl" "$home/.config/niri/niri-overrides.kdl")" ]]
}

test_niri_success_does_not_touch_outputs() {
    local home before override
    home="$(make_tempdir)"; mkdir -p "$home/.config/niri/dms"
    printf 'include "dms/layout.kdl"\n' >"$home/.config/niri/config.kdl"
    printf 'output "eDP-1" { scale 1.25 }\n' >"$home/.config/niri/dms/outputs.kdl"
    before="$(sha256sum "$home/.config/niri/dms/outputs.kdl")"
    (
        REAL_HOME="$home"
        backup_path() { :; }
        niri() { return 0; }
        configure_niri
    )
    override="$home/.config/niri/niri-overrides.kdl"
    assert_eq "$before" "$(sha256sum "$home/.config/niri/dms/outputs.kdl")"
    [[ -L "$override" ]] || fail_assert "niri-overrides.kdl is not a symlink"
    assert_eq "$(readlink "$override")" "$ROOT_DIR/assets/niri-overrides.kdl"
    assert_file_contains "$override" 'layout "us,ara"'
    assert_file_contains "$override" 'options "grp:alt_shift_toggle"'
}

test_xdg_terminal_selects_alacritty() {
    local home
    home="$(make_tempdir)"
    (
        REAL_HOME="$home"
        xdg-terminal-exec() { [[ "$1" == --print-id ]] && printf 'Alacritty.desktop\n'; }
        configure_xdg_terminal
    )
    grep -Fxq Alacritty.desktop "$home/.config/xdg-terminals.list"
}

test_non_tty_installs_kickstart_and_skips_plugins() {
    local calls
    calls="$(make_tempfile)"
    (
        OPTIONAL_SKIPPED=()
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 1; }
        install_kickstart() { printf 'kickstart\n' >>"$calls"; }
        install_optional_dms_plugins() { return 1; }
        offer_kickstart
        offer_dms_plugins
        [[ "${OPTIONAL_SKIPPED[*]}" == 'DMS plugins' ]]
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 0 ]]
    ) &>/dev/null || return 1
    [[ "$(cat "$calls")" == kickstart ]] || return 1
}

test_kickstart_dependencies_are_split_and_exposed() {
    local home calls
    home="$(make_tempdir)"
    calls="$(make_tempfile)"
    mkdir -p "$home/.config/nvim/.git"
    (
        REAL_HOME="$home"
        install_required_group() { printf 'dnf:%s\n' "$*" >>"$calls"; }
        kickstart_is_expected() { return 0; }
        brew_tool_present() { [[ "$1" == rg || "$1" == fd || "$1" == tree-sitter ]]; }
        brew_bin_dir() { printf '/brew/bin\n'; }
        nvim() { printf 'nvim:%s:path=%s\n' "$*" "$PATH" >>"$calls"; }
        install_kickstart
    ) &>/dev/null || return 1
    grep -Fxq 'dnf:Kickstart.nvim prerequisites gcc git unzip neovim' "$calls" || return 1
    grep -Fq 'nvim:--headless +qa:path=/brew/bin:' "$calls" || return 1
    if (
        REAL_HOME="$home"
        install_required_group() { :; }
        brew_tool_present() { [[ "$1" != tree-sitter ]]; }
        install_kickstart
    ) &>/dev/null; then
        return 1
    fi
}

test_default_yes_prompt_semantics() {
    local answer
    for answer in '' y Y yes unexpected; do
        (
            prompt_default_yes 'prompt' <<<"$answer"
        ) || return 1
    done
    for answer in n N; do
        if prompt_default_yes 'prompt' <<<"$answer"; then return 1; fi
    done
}

test_kickstart_failure_is_nonfatal() {
    (
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 0; }
        prompt_default_yes() { return 0; }
        install_kickstart() { return 1; }
        offer_kickstart
        [[ "${OPTIONAL_FAILURES[*]}" == 'Kickstart.nvim' ]]
    ) &>/dev/null
}

test_plugin_failures_are_nonfatal() {
    (
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 0; }
        prompt_default_yes() { return 0; }
        dms() { [[ "$*" == 'plugins list' ]]; }
        offer_dms_plugins
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 2 ]]
    ) &>/dev/null
}

test_plugins_default_yes_installs_two() {
    local calls
    calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 0; }
        prompt_default_yes() { return 0; }
        dms() {
            [[ "$*" == 'plugins list' ]] || printf '%s\n' "$*" >>"$calls"
        }
        offer_dms_plugins
    ) &>/dev/null
    assert_eq "$(grep -c '^plugins install ' "$calls")" 2
    assert_ok grep -Fxq 'plugins install codexBar' "$calls"
    assert_ok grep -Fxq 'plugins install wallpaperDiscovery' "$calls"
    assert_file_lacks "$calls" 'dockerManager'
}

test_existing_dms_plugins_are_skipped() {
    local calls
    calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        dms() {
            if [[ "$*" == 'plugins list' ]]; then
                printf '  CodexBar\n    ID: codexBar\n  Wallpaper Discovery\n    ID: wallpaperDiscovery\n'
            else
                printf '%s\n' "$*" >>"$calls"
            fi
        }
        install_optional_dms_plugins
        [[ "${#OPTIONAL_FAILURES[@]}" -eq 0 ]]
    ) &>/dev/null || return 1
    ! grep -Fq 'plugins install' "$calls" || return 1
}

test_failed_dms_plugin_list_skips_installation() {
    local calls
    calls="$(make_tempfile)"
    (
        OPTIONAL_FAILURES=()
        dms() {
            printf '%s\n' "$*" >>"$calls"
            return 1
        }
        install_optional_dms_plugins
        [[ "${OPTIONAL_FAILURES[*]}" == 'DMS plugin discovery' ]]
    ) &>/dev/null || return 1
    [[ "$(cat "$calls")" == 'plugins list' ]]
}

run_test "root execution is rejected" test_root_rejected
run_test "regular user execution is accepted" test_regular_user_accepted
run_test "startup banner has no log prefix" test_banner_has_no_log_prefix
run_test "Fedora 44 is accepted" test_fedora_44_accepted
run_test "other Fedora releases are rejected" test_other_fedora_rejected
run_test "non-Workstation Fedora is rejected" test_non_workstation_rejected
run_test "non-Intel graphics are rejected" test_non_intel_rejected
run_test "failed home lookup is rejected" test_home_lookup_failure_is_rejected
run_test "preflight bootstraps before hardware and dotfiles checks" test_preflight_bootstraps_before_hardware_and_dotfiles_checks
run_test "bootstrap package list is exact" test_bootstrap_package_list_is_exact
run_test "bootstrap package installation is rerunnable" test_bootstrap_package_install_is_rerunnable
run_test "DNF settings are replaced without duplicates" test_dnf_settings_are_replaced_once
run_test "partial core stack is detected" test_core_stack_requires_every_command
run_test "checksums are accepted and rejected correctly" test_checksum_validation
run_test "DankInstall selects sudo without exporting it" test_dankinstall_selects_sudo_without_exporting_it
run_test "healthy greeter skips repair" test_greeter_healthy_skips_repair
run_test "unhealthy greeter is repaired" test_greeter_repairs_failed_status
run_test "DMS commands select sudo and forward status" test_dms_commands_select_sudo_and_forward_status
run_test "DMS settings override merges safely and idempotently" test_dms_settings_override_merges_and_is_idempotent
run_test "DMS settings override freezes the DankBar layout" test_dms_settings_override_freezes_dankbar_layout
run_test "invalid DMS JSON preserves existing settings" test_invalid_dms_json_preserves_settings
run_test "unexpected dotfiles remote is rejected" test_unexpected_dotfiles_remote_rejected
run_test "Stow conflicts stop dotfile installation" test_stow_conflict_stops_dotfile_install
run_test "Alacritty dotfiles are required and parsed" test_alacritty_dotfiles_are_required_and_parsed
run_test "dotfiles Makefile check and stow targets are required" test_dotfiles_makefile_targets_are_required
run_test "Alacritty config migration is backed up and rerunnable" test_alacritty_config_migration_is_backed_up_and_rerunnable
run_test "required package failures are returned" test_required_failure_is_returned
run_test "modules are discovered in lexical order" test_modules_are_discovered_in_lexical_order
run_test "missing modules are fatal" test_missing_module_is_fatal
run_test "empty module directories are fatal" test_empty_module_directory_is_fatal
run_test "unreadable modules are fatal" test_unreadable_module_is_fatal
run_test "Chrome and debloat precede the first upgrade" test_system_phase_order
run_test "time format is pinned to 12-hour locale semantics" test_time_format_sets_lc_time_once
run_test "Chrome uses Fedora's managed repository" test_chrome_uses_fedora_managed_repository
run_test "existing Chrome skips package installation" test_existing_chrome_skips_package_install
run_test "debloat removes only explicitly selected packages" test_debloat_allowlist_only
run_test "debloat is a no-op when selected packages are absent" test_debloat_noop_when_absent
run_test "core packages include essentials and exclude bootstrap-only" test_core_packages_include_essentials_and_exclude_bootstrap
run_test "portable CLI tools are provided by Homebrew" test_brew_owns_portable_cli_tools
run_test "Homebrew tools precede their workstation consumers" test_workstation_dependency_order
run_test "Niri Fish completions are generated outside dotfiles" test_niri_fish_completions_are_generated_safely
run_test "Fish config symlink migration preserves local state" test_fish_config_symlink_is_migrated_without_losing_state
run_test "Fisher updates plugins and removes the legacy install" test_fisher_updates_plugins_and_removes_legacy_install
run_test "Brew installs only missing formulae" test_brew_installs_only_missing_formulae
run_test "Mise installs only missing global tools" test_mise_installs_only_missing_tools
run_test "failed GitHub login is fatal" test_github_failed_login_is_fatal
run_test "GitHub CLI protocol is explicitly set to SSH" test_github_protocol_is_explicitly_set_to_ssh
run_test "Docker is installed for on-demand use" test_docker_configures_repo_service_and_group
run_test "Docker setup delegates to focused steps" test_docker_orchestration_uses_focused_steps
run_test "Docker toggle changes daemon state safely" test_docker_toggle_helper_transitions
run_test "Docker toggle DMS plugin has expected actions" test_docker_toggle_plugin_contract
run_test "split launch-or-focus helpers handle web apps and TUIs safely" test_launch_or_focus_behaviors
run_test "launch-or-focus base focuses, launches, caches, and validates" test_launch_or_focus_base_contract
run_test "web-app manifest delegates every entry to webapp-install" test_webapp_manifest_delegates_to_installer
run_test "webapp-install creates idempotent backed-up launchers" test_webapp_install_creates_idempotent_launcher
run_test "webapp-install validates input and falls back to Chrome" test_webapp_install_validates_and_falls_back
run_test "managed assets use backed-up idempotent symlinks" test_managed_symlink_is_idempotent_and_backed_up
run_test "Niri edge indicators install idempotently" test_niri_edge_indicators_are_installed_idempotently
run_test "setup entrypoints and updater contract are exact" test_entrypoints_and_update_contract
run_test "all bin commands are installed and invalid entries are rejected" test_commands_install_every_bin_script_and_reject_invalid_entries
run_test "runtime commands and workstation modules are domain-organized" test_runtime_commands_and_workstation_modules_are_organized
run_test "install bootstrap handles fresh, clean, and rejected checkouts" test_install_bootstrap_sync_branches
run_test "install bootstrap installs missing Git" test_install_bootstraps_missing_git
run_test "install bootstrap runs when piped to Bash" test_install_runs_when_piped_to_bash
run_test "terminal update pause preserves workflow status" test_install_pause_preserves_update_status
run_test "Niri override neutralizes dangerous default binds" test_niri_override_neutralizes_dangerous_defaults
run_test "edge indicator show-logic and click/hover wiring" test_edge_indicator_wiring
run_test "Homebrew handles missing and healthy installations" test_homebrew_missing_and_healthy_branches
run_test "Zed installs only when missing" test_zed_installs_only_when_missing
run_test "Git defaults set main branch and an identity" test_git_defaults_set_main_and_identity
run_test "both supported dotfiles origins are accepted" test_both_dotfiles_origins_are_accepted
run_test "Fish initializes absolute Homebrew before brew prefix" test_fish_brew_initialization_must_precede_prefix
run_test "dotfile installation does not edit the checkout" test_dotfile_install_does_not_edit_checkout
run_test "Nerd Font discovery checks the requested family" test_nerd_font_discovery_is_exact
run_test "installed Nerd Font skips downloading" test_installed_nerd_font_skips_download
run_test "Niri override include is last and idempotent" test_niri_include_is_last_and_idempotent
run_test "failed Niri validation restores managed files" test_niri_validation_failure_rolls_back
run_test "successful Niri configuration leaves outputs untouched" test_niri_success_does_not_touch_outputs
run_test "Alacritty is selected through xdg-terminal-exec" test_xdg_terminal_selects_alacritty
run_test "non-TTY setup installs Kickstart and skips DMS plugins" test_non_tty_installs_kickstart_and_skips_plugins
run_test "Kickstart dependencies are split between Fedora and Homebrew" test_kickstart_dependencies_are_split_and_exposed
run_test "optional prompts default to yes" test_default_yes_prompt_semantics
run_test "Kickstart failure does not fail core setup" test_kickstart_failure_is_nonfatal
run_test "DMS plugins install by default" test_plugins_default_yes_installs_two
run_test "existing DMS plugins are skipped" test_existing_dms_plugins_are_skipped
run_test "failed DMS plugin listing skips installation" test_failed_dms_plugin_list_skips_installation
run_test "DMS plugin failures do not fail core setup" test_plugin_failures_are_nonfatal

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
