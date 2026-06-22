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
    if ("$@"); then pass "$name"; else fail "$name" "assertion failed"; fi
}

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
    [[ "$actual" == "$expected" ]]
    [[ "$actual" != *'[i]'* ]]
}

test_main_uses_banner_helper() {
    local definition
    definition="$(declare -f main)"
    grep -Fq 'banner "Fedora 44 → Niri + DankMaterialShell + Ghostty"' <<<"$definition"
    ! grep -Fq "printf '%b" <<<"$definition"
}

test_fedora_44_accepted() {
    local file
    file="$(mktemp)"
    printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=workstation\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
    local status=$?
    rm -f "$file"
    [[ $status -eq 0 ]]
}

test_other_fedora_rejected() {
    local file
    file="$(mktemp)"
    printf 'ID=fedora\nVERSION_ID=43\nVARIANT_ID=workstation\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
    local status=$?
    rm -f "$file"
    [[ $status -ne 0 ]]
}

test_non_workstation_rejected() {
    local file status
    file="$(mktemp)"
    printf 'ID=fedora\nVERSION_ID=44\nVARIANT_ID=server\n' >"$file"
    ( OS_RELEASE_FILE="$file"; detect_fedora ) &>/dev/null
    status=$?
    rm -f "$file"
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
    calls="$(mktemp)"
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
    rm -f "$calls"
}

test_bootstrap_package_list_is_exact() {
    local calls
    calls="$(mktemp)"
    ( s() { printf '%s\n' "$*" >>"$calls"; }; install_bootstrap_packages )
    grep -Fxq 'dnf install -y git pciutils' "$calls"
    rm -f "$calls"
}

test_bootstrap_package_install_is_rerunnable() {
    local calls
    calls="$(mktemp)"
    (
        s() { printf '%s\n' "$*" >>"$calls"; }
        install_bootstrap_packages
        install_bootstrap_packages
    ) &>/dev/null
    [[ "$(grep -c '^dnf install -y git pciutils$' "$calls")" -eq 2 ]]
    rm -f "$calls"
}

test_dnf_settings_are_replaced_once() {
    local file
    file="$(mktemp)"
    printf '[main]\nmax_parallel_downloads=3\nmax_parallel_downloads=5\ndefaultyes=False\n' >"$file"
    (
        DNF_CONF="$file"
        s() { "$@"; }
        optimize_dnf
    ) &>/dev/null || return 1
    [[ "$(grep -c '^max_parallel_downloads=10$' "$file")" -eq 1 ]]
    [[ "$(grep -c '^defaultyes=True$' "$file")" -eq 1 ]]
    rm -f "$file"
}

test_core_stack_requires_every_command() {
    ( have_command() { [[ "$1" != ghostty ]]; }; ! core_stack_complete )
}

test_checksum_validation() {
    local file digest
    file="$(mktemp)"
    printf 'verified payload' >"$file"
    digest="$(sha256sum "$file" | awk '{print $1}')"
    verify_checksum "$file" "$digest"
    if verify_checksum "$file" "0000000000000000000000000000000000000000000000000000000000000000"; then
        return 1
    fi
    rm -f "$file"
}

test_greeter_healthy_skips_repair() {
    local calls
    calls="$(mktemp)"
    (
        have_command() { return 0; }
        dms() { printf '%s\n' "$*" >>"$calls"; }
        s() { return 99; }
        install_dms_greeter
    ) &>/dev/null || return 1
    ! grep -q '^greeter enable$' "$calls" || return 1
    [[ "$(grep -c '^greeter sync -y$' "$calls")" -eq 1 ]]
    rm -f "$calls"
}

test_greeter_repairs_failed_status() {
    local calls
    calls="$(mktemp)"
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
    rm -f "$calls"
}

test_dms_settings_override_merges_and_is_idempotent() {
    local home override before
    home="$(mktemp -d)"
    override="$(mktemp)"
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
    rm -rf "$home" "$override"
}

test_invalid_dms_json_preserves_settings() {
    local home override digest missing
    home="$(mktemp -d)"
    override="$(mktemp)"
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
    rm -rf "$home" "$override"
}

test_unexpected_dotfiles_remote_rejected() {
    local home
    home="$(mktemp -d)"
    git init -q "$home/.dotfiles"
    git -C "$home/.dotfiles" remote add origin https://example.com/wrong.git
    ( REAL_HOME="$home"; validate_existing_dotfiles ) &>/dev/null
    local status=$?
    rm -rf "$home"
    [[ $status -ne 0 ]]
}

test_stow_conflict_stops_dotfile_install() {
    local home
    home="$(mktemp -d)"
    mkdir -p "$home/.dotfiles"
    (
        REAL_HOME="$home"
        REAL_USER=tester
        validate_existing_dotfiles() { :; }
        validate_dotfiles_fish() { :; }
        stow_cmd() { [[ "$1" != '--simulate' ]]; }
        install_dotfiles
    ) &>/dev/null
    local status=$?
    rm -rf "$home"
    [[ $status -ne 0 ]]
}

test_required_failure_is_returned() {
    ! (
        s() { return 1; }
        install_required_group "required test" package
    ) &>/dev/null
}

test_modules_are_discovered_in_lexical_order() {
    local directory
    directory="$(mktemp -d)"
    printf 'MODULE_LOAD_ORDER+=(first)\n' >"$directory/1-first.sh"
    printf 'MODULE_LOAD_ORDER+=(second)\n' >"$directory/2-second.sh"
    printf 'MODULE_LOAD_ORDER+=(third)\n' >"$directory/3-third.sh"
    (
        MODULE_LOAD_ORDER=()
        source_modules "$directory"
        [[ "${MODULE_LOAD_ORDER[*]}" == 'first second third' ]]
    )
    local status=$?
    rm -rf "$directory"
    [[ $status -eq 0 ]]
}

test_missing_module_is_fatal() {
    ! ( source_required modules/does-not-exist.sh ) &>/dev/null
}

test_empty_module_directory_is_fatal() {
    local directory status
    directory="$(mktemp -d)"
    ( source_modules "$directory" ) &>/dev/null
    status=$?
    rm -rf "$directory"
    [[ $status -ne 0 ]]
}

test_unreadable_module_is_fatal() {
    local directory file status
    directory="$(mktemp -d)"
    file="$directory/1-unreadable.sh"
    printf ':\n' >"$file"
    chmod 000 "$file"
    ( source_modules "$directory" ) &>/dev/null
    status=$?
    chmod 600 "$file"
    rm -rf "$directory"
    [[ $status -ne 0 ]]
}

test_system_phase_order() {
    local calls
    calls="$(mktemp)"
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
    rm -f "$calls"
}

test_time_format_sets_lc_time_once() {
    local dir calls
    dir="$(mktemp -d)"
    calls="$(mktemp)"
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
    rm -rf "$dir" "$calls"
}

test_chrome_uses_fedora_managed_repository() {
    local calls
    calls="$(mktemp)"
    (
        rpm() { return 1; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        have_command() { [[ "$1" == xdg-settings ]]; }
        xdg-settings() {
            [[ "$1" == set ]] || printf 'google-chrome.desktop\n'
        }
        install_chrome
    ) &>/dev/null
    grep -Fxq 'dnf install -y fedora-workstation-repositories' "$calls"
    grep -Fxq 'dnf config-manager enable google-chrome' "$calls"
    grep -Fxq 'dnf install -y google-chrome-stable' "$calls"
    if grep -Fq 'addrepo' "$calls"; then return 1; fi
    rm -f "$calls"
}

test_existing_chrome_skips_package_install() {
    local calls
    calls="$(mktemp)"
    (
        rpm() { return 0; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        have_command() { [[ "$1" == xdg-settings ]]; }
        xdg-settings() { [[ "$1" == set ]] || printf 'google-chrome.desktop\n'; }
        install_chrome
    ) &>/dev/null
    [[ "$(cat "$calls")" == 'dnf config-manager enable google-chrome' ]]
    rm -f "$calls"
}

test_core_package_list_is_exact() {
    [[ "${CORE_PACKAGES[*]}" == 'xwayland-satellite libva-intel-driver intel-media-driver xdg-terminal-exec wl-clipboard fontconfig xdg-user-dirs which fish' ]]
    [[ " ${CORE_PACKAGES[*]} " != *' git '* ]]
    [[ " ${CORE_PACKAGES[*]} " != *' pciutils '* ]]
    [[ " ${CORE_PACKAGES[*]} " != *' unrar '* ]]
    [[ "$(declare -f install_kickstart)" != *'fd-find'* ]]
}

test_brew_owns_portable_cli_tools() {
    local formula
    for formula in jq stow fd ripgrep tree-sitter-cli bat eza; do
        [[ " ${BREW_FORMULAE[*]} " == *" $formula "* ]] || return 1
    done
    grep -Fq '$(brew_bin_dir)/jq' <<<"$(declare -f jq_cmd)" || return 1
    grep -Fq '$(brew_bin_dir)/stow' <<<"$(declare -f stow_cmd)"
}

test_workstation_dependency_order() {
    local calls
    calls="$(mktemp)"
    (
        step() { :; }
        run_dankinstall() { printf '%s\n' dank >>"$calls"; }
        install_core_packages() { printf '%s\n' core >>"$calls"; }
        install_niri_fish_completions() { printf '%s\n' completions >>"$calls"; }
        install_homebrew() { printf '%s\n' brew >>"$calls"; }
        install_brew_formulae() { printf '%s\n' formulae >>"$calls"; }
        configure_launch_or_focus() { printf '%s\n' launchers >>"$calls"; }
        apply_dms_settings_override() { printf '%s\n' dms-settings >>"$calls"; }
        install_dms_greeter() { printf '%s\n' greeter >>"$calls"; }
        install_zed() { printf '%s\n' zed >>"$calls"; }
        install_nerd_font() { printf '%s\n' font >>"$calls"; }
        configure_xdg_terminal() { printf '%s\n' terminal >>"$calls"; }
        configure_niri() { printf '%s\n' niri >>"$calls"; }
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
    [[ "$(tr '\n' ' ' <"$calls")" == 'dank core completions brew formulae launchers dms-settings greeter zed font terminal niri git github dotfiles fish-plugins mise docker dirs target ' ]]
    rm -f "$calls"
}

test_niri_fish_completions_are_generated_safely() {
    local home destination inode digest
    home="$(mktemp -d)"
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
    rm -rf "$home"
}

test_fish_config_symlink_is_migrated_without_losing_state() {
    local home dotdir config
    home="$(mktemp -d)"
    dotdir="$home/.dotfiles"
    config="$home/.config/fish"
    mkdir -p "$dotdir/fish/.config/fish" "$home/.config"
    printf 'SETUVAR test:value\n' >"$dotdir/fish/.config/fish/fish_variables"
    ln -s ../.dotfiles/fish/.config/fish "$config"
    ( REAL_HOME="$home"; prepare_fish_config_directory "$dotdir" ) || return 1
    [[ -d "$config" && ! -L "$config" ]] || return 1
    grep -Fxq 'SETUVAR test:value' "$config/fish_variables"
    rm -rf "$home"
}

test_fisher_updates_plugins_and_removes_legacy_install() {
    local home calls
    home="$(mktemp -d)"
    calls="$(mktemp)"
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
    rm -rf "$home" "$calls"
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
        rpm() { printf '%s\n' gnome-shell gdm nautilus; }
        s() { return 1; }
        debloat_system
    ) &>/dev/null
}

test_brew_installs_only_missing_formulae() {
    local calls
    calls="$(mktemp)"
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
    rm -f "$calls"
}

test_mise_installs_only_missing_tools() {
    local calls
    calls="$(mktemp)"
    (
        mise_cmd() {
            if [[ "$1" == current ]]; then [[ "$2" != codex ]]; else printf '%s\n' "$*" >>"$calls"; fi
        }
        install_mise_tools
    )
    grep -Fxq 'use --global codex@latest' "$calls"
    [[ "$(wc -l <"$calls")" -eq 1 ]]
    rm -f "$calls"
}

test_github_failed_login_is_fatal() {
    ! (
        gh_cmd() { return 1; }
        ensure_github_auth
    ) &>/dev/null
}

test_github_protocol_is_explicitly_set_to_ssh() {
    local calls protocol=https
    calls="$(mktemp)"
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
    rm -f "$calls"
}

test_docker_configures_repo_service_and_group() {
    local calls home
    calls="$(mktemp)"; home="$(mktemp -d)"
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
        install_root_symlink_with_backup() { printf 'root-link %s %s\n' "$1" "$2" >>"$calls"; }
        remove_root_path_with_backup() { printf 'root-remove %s\n' "$1" >>"$calls"; }
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
    grep -Fxq "root-link $ROOT_DIR/assets/docker-toggle /usr/local/bin/docker-toggle" "$calls" || return 1
    grep -Fxq "root-link $ROOT_DIR/install.sh /usr/local/bin/update-workstation" "$calls" || return 1
    grep -Fxq 'root-remove /usr/local/bin/niri-setup-update' "$calls" || return 1
    grep -Fxq 'root-file /etc/sudoers.d/docker-toggle 0440' "$calls" || return 1
    grep -Fxq 'root-remove /etc/sudoers.d/niri-setup-docker-toggle' "$calls" || return 1
    grep -Fxq "user-link $ROOT_DIR/assets/dms-docker-toggle $home/.config/DankMaterialShell/plugins/dockerToggle" "$calls" || return 1
    rm -rf "$calls" "$home"
}

test_docker_toggle_helper_transitions() {
    local dir state systemctl_mock sudo_mock helper
    dir="$(mktemp -d)"; state="$dir/state"; helper="$ROOT_DIR/assets/docker-toggle"
    systemctl_mock="$dir/systemctl"; sudo_mock="$dir/sudo"
    printf 'inactive\n' >"$state"
    # shellcheck disable=SC2016 # These lines form a script evaluated later.
    printf '%s\n' '#!/usr/bin/env bash' \
        'state=$DOCKER_TEST_STATE' \
        'case "$1" in' \
        '  is-active) [[ "$(cat "$state")" == active ]] ;;' \
        '  start) printf "active\n" >"$state" ;;' \
        '  stop) printf "inactive\n" >"$state" ;;' \
        'esac' >"$systemctl_mock"
    printf '%s\n' '#!/usr/bin/env bash' 'exec "$@"' >"$sudo_mock"
    chmod +x "$systemctl_mock" "$sudo_mock"
    [[ -x "$helper" ]] || return 1
    [[ "$(DOCKER_TEST_STATE="$state" SYSTEMCTL="$systemctl_mock" SUDO="$sudo_mock" "$helper" status)" == inactive ]] || return 1
    DOCKER_TEST_STATE="$state" SYSTEMCTL="$systemctl_mock" SUDO="$sudo_mock" "$helper" start &>/dev/null || return 1
    [[ "$(cat "$state")" == active ]] || return 1
    DOCKER_TEST_STATE="$state" SYSTEMCTL="$systemctl_mock" SUDO="$sudo_mock" "$helper" toggle &>/dev/null || return 1
    [[ "$(cat "$state")" == inactive ]] || return 1
    DOCKER_TEST_STATE="$state" SYSTEMCTL="$systemctl_mock" SUDO="$sudo_mock" "$helper" stop &>/dev/null || return 1
    [[ "$(cat "$state")" == inactive ]] || return 1
    if DOCKER_TEST_STATE="$state" SYSTEMCTL="$systemctl_mock" SUDO="$sudo_mock" "$helper" invalid &>/dev/null; then
        return 1
    fi
    rm -rf "$dir"
}

test_docker_toggle_plugin_contract() {
    local manifest="$ROOT_DIR/assets/dms-docker-toggle/plugin.json"
    local component="$ROOT_DIR/assets/dms-docker-toggle/DockerToggle.qml"
    grep -Fq '"id": "dockerToggle"' "$manifest"
    grep -Fq 'pillClickAction: () => toggleDocker()' "$component"
    grep -Fq 'pillRightClickAction: () => openLazydocker()' "$component"
    grep -Fq '["/usr/local/bin/docker-toggle", "toggle"]' "$component"
    grep -Fq '["/usr/local/bin/launch-or-focus", "tui", "--", "lazydocker"]' "$component"
    grep -Fq 'text: "\uf308"' "$component"
    grep -Fq 'font.family: "JetBrainsMono Nerd Font"' "$component"
    if grep -Fq '["/usr/local/bin/docker-toggle", "start"]' "$component"; then
        return 1
    fi
}

test_launch_or_focus_behaviors() {
    local dir helper niri_mock setsid_mock windows_file focus_log launch_log marker state_dir hostile first_pid second_pid
    dir="$(mktemp -d)"
    helper="$ROOT_DIR/assets/launch-or-focus"
    niri_mock="$dir/niri"
    setsid_mock="$dir/setsid"
    windows_file="$dir/windows.json"
    focus_log="$dir/focus.log"
    launch_log="$dir/launch.log"
    marker="$dir/launched"
    state_dir="$dir/state"
    hostile="$dir/should-not-exist"
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

    printf '[{"id":42,"app_id":"dev.zed.Zed","is_focused":false}]\n' >"$windows_file"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" app dev.zed.Zed -- zed
    grep -Fxq 'msg action focus-window --id 42' "$focus_log" || return 1
    [[ ! -e "$launch_log" ]] || return 1

    printf '[]\n' >"$windows_file"
    : >"$focus_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" app missing.App -- printf 'hello world' "\$(touch $hostile)"
    grep -Fxq '<hello world>' "$launch_log" || return 1
    grep -Fxq "<\$(touch $hostile)>" "$launch_log" || return 1
    [[ ! -e "$hostile" ]] || return 1

    rm -f "$marker"
    : >"$launch_log"
    : >"$focus_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" tui -- lazydocker
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" tui -- lazydocker --debug
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$launch_log")" == 1 ]] || return 1
    grep -Fxq 'msg action focus-window --id 88' "$focus_log" || return 1

    rm -f "$marker"
    : >"$launch_log"
    : >"$focus_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker SETSID_DELAY=0.3 \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" tui -- lazydocker &
    first_pid=$!
    sleep 0.05
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker SETSID_DELAY=0.3 \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" tui -- lazydocker &
    second_pid=$!
    wait "$first_pid"
    wait "$second_pid"
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$launch_log")" == 1 ]] || return 1

    rm -f "$marker"
    : >"$launch_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.lazydocker \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" tui -- lazydocker
    [[ "$(grep -Fxc '<--app-id=local.tui.lazydocker>' "$launch_log")" == 1 ]] || return 1

    rm -f "$marker"
    : >"$launch_log"
    if WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        WINDOW_WAIT_ATTEMPTS=1 LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" \
        "$helper" tui -- lazydocker 2>/dev/null; then
        return 1
    fi
    grep -Fxq '<--app-id=local.tui.lazydocker>' "$launch_log" || return 1

    rm -f "$marker"
    : >"$launch_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        LAUNCH_MARKER="$marker" LAUNCH_APP_ID=local.tui.btop \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" tui -- btop
    grep -Fxq '<--app-id=local.tui.btop>' "$launch_log" || return 1

    mkdir -p "$state_dir"
    printf '77\n' >"$state_dir/webapp-notion.window-id"
    printf '[{"id":77,"app_id":"google-chrome","is_focused":false}]\n' >"$windows_file"
    : >"$focus_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" webapp notion https://www.notion.so
    grep -Fxq 'msg action focus-window --id 77' "$focus_log" || return 1

    printf '[]\n' >"$windows_file"
    rm -f "$marker" "$state_dir/webapp-reddit.window-id"
    : >"$launch_log"
    WINDOWS_FILE="$windows_file" FOCUS_LOG="$focus_log" LAUNCH_LOG="$launch_log" LAUNCH_MARKER="$marker" \
        NIRI="$niri_mock" SETSID="$setsid_mock" JQ="$(dirname "$BREW_BIN")/jq" \
        LAUNCH_OR_FOCUS_STATE_DIR="$state_dir" "$helper" webapp reddit https://www.reddit.com
    [[ "$(cat "$state_dir/webapp-reddit.window-id")" == 88 ]] || return 1
    grep -Fxq '<--app=https://www.reddit.com>' "$launch_log" || return 1
    grep -Fxq '<--class=niri-webapp-reddit>' "$launch_log" || return 1
    if grep -Fq '<fd9-open>' "$launch_log.fd" 2>/dev/null; then return 1; fi
    if grep -Fq eval "$helper"; then return 1; fi
    rm -rf "$dir"
}

test_webapp_launchers_are_generated_with_icons() {
    local home calls
    home="$(mktemp -d)"
    calls="$(mktemp)"
    (
        REAL_HOME="$home"
        install_root_symlink_with_backup() { printf '%s %s\n' "$1" "$2" >>"$calls"; }
        have_command() { return 1; }
        curl() {
            local output=""
            while (($#)); do
                if [[ "$1" == -o ]]; then output=$2; shift 2; else shift; fi
            done
            printf 'png' >"$output"
        }
        configure_launch_or_focus
    ) &>/dev/null || return 1
    [[ "$(find "$home/.local/share/applications" -name 'niri-webapp-*.desktop' | wc -l)" -eq 8 ]] || return 1
    [[ "$(find "$home/.local/share/icons" -name 'niri-webapp-*.png' | wc -l)" -eq 8 ]] || return 1
    grep -Fxq 'Name=Notion' "$home/.local/share/applications/niri-webapp-notion.desktop"
    grep -Fxq 'Exec=/usr/local/bin/launch-or-focus webapp notion https://www.notion.so' "$home/.local/share/applications/niri-webapp-notion.desktop"
    grep -Fxq 'Icon=niri-webapp-notion' "$home/.local/share/applications/niri-webapp-notion.desktop"
    grep -Fxq "$ROOT_DIR/assets/launch-or-focus /usr/local/bin/launch-or-focus" "$calls"
    rm -rf "$home" "$calls"
}

test_webapp_icon_failure_uses_chrome_icon() {
    local home
    home="$(mktemp -d)"
    (
        REAL_HOME="$home"
        install_root_symlink_with_backup() { :; }
        have_command() { return 1; }
        curl() { return 1; }
        configure_launch_or_focus
    ) &>/dev/null || return 1
    grep -Fxq 'Icon=google-chrome' "$home/.local/share/applications/niri-webapp-notion.desktop"
    rm -rf "$home"
}

test_launch_or_focus_bindings_are_complete() {
    local config="$ROOT_DIR/assets/niri-overrides.kdl" binding
    for binding in \
        'Mod\+Shift\+N.*notion.*https://www.notion.so' \
        'Mod\+Shift\+R.*reddit.*https://www.reddit.com' \
        'Mod\+Shift\+C.*google-calendar.*https://calendar.google.com' \
        'Mod\+Shift\+A.*chatgpt.*https://chatgpt.com' \
        'Mod\+Shift\+Y.*youtube.*https://www.youtube.com' \
        'Mod\+Shift\+M.*youtube-music.*https://music.youtube.com' \
        'Mod\+Shift\+G.*gmail.*https://mail.google.com' \
        'Mod\+Shift\+D.*discord.*https://discord.com/app' \
        'Mod\+Shift\+Z.*dev.zed.Zed.*zed' \
        'Mod\+Shift\+E.*org.gnome.Nautilus.*nautilus'; do
        grep -Eq "$binding" "$config" || return 1
    done
}

test_managed_symlink_is_idempotent_and_backed_up() {
    local dir target destination backup_count
    dir="$(mktemp -d)"; target="$dir/target"; destination="$dir/link"
    printf 'managed\n' >"$target"
    printf 'user content\n' >"$destination"
    install_symlink_with_backup "$target" "$destination"
    [[ -L "$destination" && "$(readlink "$destination")" == "$target" ]] || return 1
    backup_count="$(find "$dir" -maxdepth 1 -name 'link.backup-*' | wc -l)"
    [[ "$backup_count" -eq 1 ]] || return 1
    install_symlink_with_backup "$target" "$destination"
    [[ "$(find "$dir" -maxdepth 1 -name 'link.backup-*' | wc -l)" -eq 1 ]]
    rm -rf "$dir"
}

test_root_path_removal_is_backed_up_and_rerunnable() {
    local dir path backup
    dir="$(mktemp -d)"
    path="$dir/legacy-command"
    backup="$path.backup-20260621-000000"
    printf 'legacy content\n' >"$path"
    (
        sudo() { "$@"; }
        s() { "$@"; }
        timestamp() { printf '20260621-000000\n'; }
        remove_root_path_with_backup "$path"
        remove_root_path_with_backup "$path"
    ) &>/dev/null || return 1
    [[ ! -e "$path" ]]
    [[ "$(cat "$backup")" == 'legacy content' ]]
    [[ "$(find "$dir" -name 'legacy-command.backup-*' | wc -l)" -eq 1 ]]
    rm -rf "$dir"
}

test_entrypoints_and_update_contract() {
    [[ -x "$ROOT_DIR/setup.sh" ]]
    [[ -x "$ROOT_DIR/install.sh" ]]
    [[ ! -e "$ROOT_DIR/assets/niri-setup-update" ]]
    [[ ! -e "$ROOT_DIR/setup-fedora-niri-dms.sh" ]]
    grep -Fq 'git clone --branch main "$REPO_URL" "$INSTALL_DIR"' "$ROOT_DIR/install.sh"
    grep -Fq 'git -C "$INSTALL_DIR" pull --ff-only origin main' "$ROOT_DIR/install.sh"
    grep -Fq 'exec "$INSTALL_DIR/setup.sh"' "$ROOT_DIR/install.sh"
    grep -Fq 'install_root_symlink_with_backup "$ROOT_DIR/install.sh" /usr/local/bin/update-workstation' \
        "$ROOT_DIR/modules/2-workstation.sh"
}

test_install_bootstrap_sync_branches() {
    local dir calls
    dir="$(mktemp -d)"; calls="$(mktemp)"
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
    rm -rf "$dir" "$calls"
}

test_install_bootstraps_missing_git() {
    local calls
    calls="$(mktemp)"
    (
        NIRI_SETUP_DIR=/tmp/not-used
        source "$ROOT_DIR/install.sh"
        command() { return 1; }
        sudo() { printf '%s\n' "$*" >>"$calls"; }
        ensure_git
    )
    grep -Fxq 'dnf install -y git' "$calls"
    rm -f "$calls"
}

test_install_runs_when_piped_to_bash() {
    local dir bin marker
    dir="$(mktemp -d)"
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
    [[ "$(cat "$marker")" == ran ]]
    rm -rf "$dir"
}

test_close_window_binding_is_mod_w() {
    local override="$ROOT_DIR/assets/niri-overrides.kdl"
    grep -Fq 'Mod+W repeat=false hotkey-overlay-title="Close Window" { close-window; }' "$override"
    grep -Fq 'Mod+Q hotkey-overlay-title=null { spawn "true"; }' "$override"
    grep -Fq 'Mod+D hotkey-overlay-title=null { spawn "true"; }' "$override"
    grep -Fq 'Mod+Tab repeat=false hotkey-overlay-title="Next Workspace" { focus-workspace-down; }' "$override"
    grep -Fq 'Mod+Shift+Tab repeat=false hotkey-overlay-title="Previous Workspace" { focus-workspace-up; }' "$override"
    grep -Fq 'Mod+O repeat=false hotkey-overlay-title="Overview" { toggle-overview; }' "$override"
    ! grep -Fq 'toggle-column-tabbed-display' "$override"
}

test_homebrew_missing_and_healthy_branches() {
    local home calls
    home="$(mktemp -d)"; calls="$(mktemp)"; : >"$home/.bashrc"
    (
        REAL_HOME="$home"
        state=missing
        homebrew_present() { [[ "$state" == healthy ]]; }
        run_homebrew_installer() { printf 'installer\n' >>"$calls"; state=healthy; }
        backup_path() { :; }
        install_homebrew
    )
    grep -Fxq installer "$calls"
    grep -Fq '/home/linuxbrew/.linuxbrew/bin/brew shellenv' "$home/.bashrc"
    : >"$calls"
    (
        REAL_HOME="$home"
        homebrew_present() { return 0; }
        run_homebrew_installer() { return 1; }
        install_homebrew
    )
    [[ ! -s "$calls" ]]
    rm -rf "$home" "$calls"
}

test_zed_installs_only_when_missing() {
    local home
    home="$(mktemp -d)"
    (
        REAL_HOME="$home"
        zed_present() { [[ -x "$REAL_HOME/.local/bin/zed" ]]; }
        curl() { printf 'mkdir -p %q/.local/bin; touch %q/.local/bin/zed; chmod +x %q/.local/bin/zed\n' "$REAL_HOME" "$REAL_HOME" "$REAL_HOME"; }
        install_zed
    )
    [[ -x "$home/.local/bin/zed" ]]
    rm -rf "$home"
}

test_git_defaults_are_exact() {
    local calls
    calls="$(mktemp)"
    ( git() { printf '%s\n' "$*" >>"$calls"; }; configure_git )
    [[ "$(cat "$calls")" == $'config --global init.defaultBranch main\nconfig --global user.name Abdulrahman Ajlouni\nconfig --global user.email ajlouni2000@gmail.com' ]]
    rm -f "$calls"
}

test_both_dotfiles_origins_are_accepted() {
    valid_dotfiles_remote "$DOTFILES_REPO_HTTPS"
    valid_dotfiles_remote "$DOTFILES_REPO_SSH"
    ! valid_dotfiles_remote https://example.com/dotfiles.git
}

test_fish_brew_initialization_must_precede_prefix() {
    local dotdir before
    dotdir="$(mktemp -d)"
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
    rm -rf "$dotdir"
}

test_dotfile_install_does_not_edit_checkout() {
    local home config before calls
    home="$(mktemp -d)"
    calls="$(mktemp)"
    config="$home/.dotfiles/fish/.config/fish/config.fish"
    mkdir -p "$(dirname "$config")" "$home/.dotfiles/zed"
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
        stow_cmd() { return 0; }
        getent() { printf 'tester:x:1000:1000::%s:/bin/bash\n' "$home"; }
        s() { printf '%s\n' "$*" >>"$calls"; }
        install_dotfiles
    )
    [[ "$before" == "$(sha256sum "$config")" ]]
    grep -Fxq 'chsh -s /usr/bin/fish tester' "$calls"
    rm -rf "$home" "$calls"
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
    home="$(mktemp -d)"; file="$home/config.kdl"
    printf 'include "dms/a.kdl"\ninclude "niri-overrides.kdl"\nbinds {}\n' >"$file"
    ( backup_path() { :; }; ensure_niri_override_include "$file" )
    [[ "$(grep -c 'include "niri-overrides.kdl"' "$file")" -eq 1 ]]
    [[ "$(tail -n 1 "$file")" == 'include "niri-overrides.kdl"' ]]
    before="$(sha256sum "$file")"
    ( backup_path() { return 1; }; ensure_niri_override_include "$file" )
    [[ "$before" == "$(sha256sum "$file")" ]]
    rm -rf "$home"
}

test_niri_validation_failure_rolls_back() {
    local home original
    home="$(mktemp -d)"; mkdir -p "$home/.config/niri/dms"
    printf 'include "dms/layout.kdl"\n' >"$home/.config/niri/config.kdl"
    printf 'output "eDP-1" { scale 1.0 }\n' >"$home/.config/niri/dms/outputs.kdl"
    printf 'old override\n' >"$home/.config/niri/niri-overrides.kdl"
    original="$(sha256sum "$home/.config/niri/config.kdl" "$home/.config/niri/dms/outputs.kdl" "$home/.config/niri/niri-overrides.kdl")"
    if ( REAL_HOME="$home"; backup_path() { :; }; niri() { return 1; }; configure_niri ) &>/dev/null; then
        return 1
    fi
    [[ "$original" == "$(sha256sum "$home/.config/niri/config.kdl" "$home/.config/niri/dms/outputs.kdl" "$home/.config/niri/niri-overrides.kdl")" ]]
    rm -rf "$home"
}

test_niri_success_does_not_touch_outputs() {
    local home before
    home="$(mktemp -d)"; mkdir -p "$home/.config/niri/dms"
    printf 'include "dms/layout.kdl"\n' >"$home/.config/niri/config.kdl"
    printf 'output "eDP-1" { scale 1.25 }\n' >"$home/.config/niri/dms/outputs.kdl"
    before="$(sha256sum "$home/.config/niri/dms/outputs.kdl")"
    (
        REAL_HOME="$home"
        backup_path() { :; }
        niri() { return 0; }
        configure_niri
    )
    [[ "$before" == "$(sha256sum "$home/.config/niri/dms/outputs.kdl")" ]]
    [[ -L "$home/.config/niri/niri-overrides.kdl" ]]
    [[ "$(readlink "$home/.config/niri/niri-overrides.kdl")" == "$ROOT_DIR/assets/niri-overrides.kdl" ]]
    grep -Fq 'layout "us,ara"' "$home/.config/niri/niri-overrides.kdl"
    grep -Fq 'options "grp:alt_shift_toggle"' "$home/.config/niri/niri-overrides.kdl"
    rm -rf "$home"
}

test_xdg_terminal_selects_ghostty() {
    local home
    home="$(mktemp -d)"
    (
        REAL_HOME="$home"
        xdg-terminal-exec() { [[ "$1" == --print-id ]] && printf 'com.mitchellh.ghostty.desktop\n'; }
        configure_xdg_terminal
    )
    grep -Fxq com.mitchellh.ghostty.desktop "$home/.config/xdg-terminals.list"
    rm -rf "$home"
}

test_non_tty_installs_kickstart_and_skips_plugins() {
    local calls
    calls="$(mktemp)"
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
    rm -f "$calls"
}

test_kickstart_dependencies_are_split_and_exposed() {
    local home calls
    home="$(mktemp -d)"
    calls="$(mktemp)"
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
    grep -Fxq 'dnf:Kickstart.nvim prerequisites gcc make git unzip neovim' "$calls" || return 1
    grep -Fq 'nvim:--headless +qa:path=/brew/bin:' "$calls" || return 1
    if (
        REAL_HOME="$home"
        install_required_group() { :; }
        brew_tool_present() { [[ "$1" != tree-sitter ]]; }
        install_kickstart
    ) &>/dev/null; then
        return 1
    fi
    rm -rf "$home" "$calls"
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

test_optional_prompt_text_is_exact() {
    local calls
    calls="$(mktemp)"
    (
        OPTIONAL_SKIPPED=()
        stdin_is_tty() { return 0; }
        prompt_default_yes() { printf '%s\n' "$1" >>"$calls"; return 1; }
        offer_kickstart
        offer_dms_plugins
    )
    [[ "$(cat "$calls")" == $'Install Kickstart.nvim? [Y/n]\nInstall optional DMS plugins? [Y/n]' ]]
    rm -f "$calls"
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
    calls="$(mktemp)"
    (
        OPTIONAL_FAILURES=()
        stdin_is_tty() { return 0; }
        prompt_default_yes() { return 0; }
        dms() { printf '%s\n' "$*" >>"$calls"; }
        offer_dms_plugins
    ) &>/dev/null
    [[ "$(grep -c '^plugins install ' "$calls")" -eq 2 ]]
    grep -Fxq 'plugins install codexBar' "$calls"
    grep -Fxq 'plugins install wallpaperDiscovery' "$calls"
    if grep -Fq dockerManager "$calls"; then
        return 1
    fi
    rm -f "$calls"
}

run_test "root execution is rejected" test_root_rejected
run_test "regular user execution is accepted" test_regular_user_accepted
run_test "startup banner has no log prefix" test_banner_has_no_log_prefix
run_test "main uses the shared banner helper" test_main_uses_banner_helper
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
run_test "healthy greeter skips repair" test_greeter_healthy_skips_repair
run_test "unhealthy greeter is repaired" test_greeter_repairs_failed_status
run_test "DMS settings override merges safely and idempotently" test_dms_settings_override_merges_and_is_idempotent
run_test "invalid DMS JSON preserves existing settings" test_invalid_dms_json_preserves_settings
run_test "unexpected dotfiles remote is rejected" test_unexpected_dotfiles_remote_rejected
run_test "Stow conflicts stop dotfile installation" test_stow_conflict_stops_dotfile_install
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
run_test "core package list contains only agreed essentials" test_core_package_list_is_exact
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
run_test "Docker toggle changes daemon state safely" test_docker_toggle_helper_transitions
run_test "Docker toggle DMS plugin has expected actions" test_docker_toggle_plugin_contract
run_test "launch-or-focus handles apps, web apps, and TUIs safely" test_launch_or_focus_behaviors
run_test "web-app desktop launchers include downloaded icons" test_webapp_launchers_are_generated_with_icons
run_test "web-app icon failures use the Chrome icon" test_webapp_icon_failure_uses_chrome_icon
run_test "launch-or-focus Niri bindings are complete" test_launch_or_focus_bindings_are_complete
run_test "managed assets use backed-up idempotent symlinks" test_managed_symlink_is_idempotent_and_backed_up
run_test "legacy root paths are backed up and removed once" test_root_path_removal_is_backed_up_and_rerunnable
run_test "setup entrypoints and updater contract are exact" test_entrypoints_and_update_contract
run_test "install bootstrap handles fresh, clean, and rejected checkouts" test_install_bootstrap_sync_branches
run_test "install bootstrap installs missing Git" test_install_bootstraps_missing_git
run_test "install bootstrap runs when piped to Bash" test_install_runs_when_piped_to_bash
run_test "close-window is bound to Mod+W" test_close_window_binding_is_mod_w
run_test "Homebrew handles missing and healthy installations" test_homebrew_missing_and_healthy_branches
run_test "Zed installs only when missing" test_zed_installs_only_when_missing
run_test "Git global defaults are exact" test_git_defaults_are_exact
run_test "both supported dotfiles origins are accepted" test_both_dotfiles_origins_are_accepted
run_test "Fish initializes absolute Homebrew before brew prefix" test_fish_brew_initialization_must_precede_prefix
run_test "dotfile installation does not edit the checkout" test_dotfile_install_does_not_edit_checkout
run_test "Nerd Font discovery checks the requested family" test_nerd_font_discovery_is_exact
run_test "installed Nerd Font skips downloading" test_installed_nerd_font_skips_download
run_test "Niri override include is last and idempotent" test_niri_include_is_last_and_idempotent
run_test "failed Niri validation restores managed files" test_niri_validation_failure_rolls_back
run_test "successful Niri configuration leaves outputs untouched" test_niri_success_does_not_touch_outputs
run_test "Ghostty is selected through xdg-terminal-exec" test_xdg_terminal_selects_ghostty
run_test "non-TTY setup installs Kickstart and skips DMS plugins" test_non_tty_installs_kickstart_and_skips_plugins
run_test "Kickstart dependencies are split between Fedora and Homebrew" test_kickstart_dependencies_are_split_and_exposed
run_test "optional prompts default to yes" test_default_yes_prompt_semantics
run_test "optional prompt text is exact" test_optional_prompt_text_is_exact
run_test "Kickstart failure does not fail core setup" test_kickstart_failure_is_nonfatal
run_test "DMS plugins install by default" test_plugins_default_yes_installs_two
run_test "DMS plugin failures do not fail core setup" test_plugin_failures_are_nonfatal

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
