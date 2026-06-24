#!/usr/bin/env bash
# shellcheck disable=SC1090,SC2016,SC2032,SC2034,SC2329

set -u
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/tests/lib.sh"

section "dotfiles remote/stow/Alacritty/Makefile, Fish, Fisher, Nerd Font, Niri completions"

test_unexpected_dotfiles_remote_rejected() {
    local home; home="$(make_tempdir)"
    git init -q "$home/.dotfiles"
    git -C "$home/.dotfiles" remote add origin https://example.com/wrong.git
    ! ( REAL_HOME="$home"; validate_existing_dotfiles ) &>/dev/null
}

test_stow_conflict_stops_dotfile_install() {
    local home; home="$(make_tempdir)"
    mkdir -p "$home/.dotfiles"
    ! (
        REAL_HOME="$home"
        REAL_USER=tester
        validate_existing_dotfiles() { :; }
        validate_dotfiles_fish() { :; }
        validate_dotfiles_alacritty() { :; }
        validate_dotfiles_makefile() { :; }
        make_cmd() { return 1; }
        install_dotfiles
    ) &>/dev/null
}

test_alacritty_dotfiles_are_required_and_parsed() {
    local dotdir config observed; dotdir="$(make_tempdir)"
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
    local home dotdir; home="$(make_tempdir)"; dotdir="$home/.dotfiles"
    mkdir -p "$dotdir"
    if ( REAL_HOME="$home"; validate_dotfiles_makefile "$dotdir" ) &>/dev/null; then return 1; fi
    printf 'all:\n\t@:\ncheck:\n\t@:\n' >"$dotdir/Makefile"
    ( REAL_HOME="$home"; make_cmd() { make "$@"; }; validate_dotfiles_makefile "$dotdir" ) || return 1
}

test_alacritty_config_migration_is_backed_up_and_rerunnable() {
    local home dotdir destination backup
    home="$(make_tempdir)"; dotdir="$home/.dotfiles"; destination="$home/.config/alacritty/alacritty.toml"
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

test_both_dotfiles_origins_are_accepted() {
    local dir; dir="$(make_tempdir)"
    git init -q "$dir"
    git -C "$dir" remote add origin "$DOTFILES_REPO_HTTPS"
    assert_ok git_remote_matches "$dir" "$DOTFILES_REPO_HTTPS" "$DOTFILES_REPO_SSH"
    git -C "$dir" remote set-url origin "$DOTFILES_REPO_SSH"
    assert_ok git_remote_matches "$dir" "$DOTFILES_REPO_HTTPS" "$DOTFILES_REPO_SSH"
    git -C "$dir" remote set-url origin https://example.com/dotfiles.git
    assert_fails git_remote_matches "$dir" "$DOTFILES_REPO_HTTPS" "$DOTFILES_REPO_SSH"
}

test_fish_brew_initialization_must_precede_prefix() {
    local dotdir before; dotdir="$(make_tempdir)"
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

test_fish_config_symlink_is_migrated_without_losing_state() {
    local home dotdir config; home="$(make_tempdir)"; dotdir="$home/.dotfiles"; config="$home/.config/fish"
    mkdir -p "$dotdir/fish/.config/fish" "$home/.config"
    printf 'SETUVAR test:value\n' >"$dotdir/fish/.config/fish/fish_variables"
    ln -s ../.dotfiles/fish/.config/fish "$config"
    ( REAL_HOME="$home"; prepare_fish_config_directory "$dotdir" ) || return 1
    [[ -d "$config" && ! -L "$config" ]] || return 1
    grep -Fxq 'SETUVAR test:value' "$config/fish_variables"
}

test_fisher_updates_plugins_and_removes_legacy_install() {
    local home calls; home="$(make_tempdir)"; calls="$(make_tempfile)"
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

test_dotfile_install_does_not_edit_checkout() {
    local home config before calls; home="$(make_tempdir)"; calls="$(make_tempfile)"
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

test_niri_fish_completions_are_generated_safely() {
    local home destination inode digest; home="$(make_tempdir)"
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

run_test "unexpected dotfiles remote is rejected" test_unexpected_dotfiles_remote_rejected
run_test "Stow conflicts stop dotfile installation" test_stow_conflict_stops_dotfile_install
run_test "Alacritty dotfiles are required and parsed" test_alacritty_dotfiles_are_required_and_parsed
run_test "dotfiles Makefile check and stow targets are required" test_dotfiles_makefile_targets_are_required
run_test "Alacritty config migration is backed up and rerunnable" test_alacritty_config_migration_is_backed_up_and_rerunnable
run_test "both supported dotfiles origins are accepted" test_both_dotfiles_origins_are_accepted
run_test "Fish initializes absolute Homebrew before brew prefix" test_fish_brew_initialization_must_precede_prefix
run_test "Fish config symlink migration preserves local state" test_fish_config_symlink_is_migrated_without_losing_state
run_test "Fisher updates plugins and removes the legacy install" test_fisher_updates_plugins_and_removes_legacy_install
run_test "dotfile installation does not edit the checkout" test_dotfile_install_does_not_edit_checkout
run_test "Nerd Font discovery checks the requested family" test_nerd_font_discovery_is_exact
run_test "installed Nerd Font skips downloading" test_installed_nerd_font_skips_download
run_test "Niri Fish completions are generated outside dotfiles" test_niri_fish_completions_are_generated_safely

printf '\n%d tests, %d failures\n' "$TESTS_RUN" "$TESTS_FAILED"
[[ $TESTS_FAILED -eq 0 ]]
