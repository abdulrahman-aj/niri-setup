#!/usr/bin/env bash
# shellcheck disable=SC2034 # Constants are consumed by sourced workstation components.

readonly CORE_PACKAGES=(
    xwayland-satellite libva-intel-driver intel-media-driver alacritty
    xdg-terminal-exec wl-clipboard fontconfig xdg-user-dirs which fish make
)
readonly BREW_FORMULAE=(starship lazygit lazydocker fzf bat eza ripgrep gh mise tlrc zoxide jq stow fd tree-sitter-cli git-delta steipete/tap/codexbar)
readonly MISE_TOOLS=(opencode codex claude-code)
readonly WALLPAPER_URLS=(
    "https://raw.githubusercontent.com/dharmx/walls/main/nord/a_mountain_range_with_snow_on_top.jpg"
    "https://raw.githubusercontent.com/dharmx/walls/main/nord/a_video_game_graphics_of_a_forest_and_a_lake.png"
    "https://raw.githubusercontent.com/dharmx/walls/main/digital/a_road_with_trees_and_a_mountain_in_the_background.png"
    "https://raw.githubusercontent.com/dharmx/walls/main/nord/a_waterfall_with_trees_and_leaves.jpg"
)

source_modules "$ROOT_DIR/modules/workstation"

run_workstation_phase() {
    step "Setting up your desktop"

    # DNF
    run_dankinstall
    install_core_packages
    install_dms_greeter
    install_docker

    # Homebrew
    install_homebrew
    install_brew_formulae

    # Mise
    install_mise_tools

    install_commands
    install_webapps
    apply_dms_settings_override
    apply_dms_session_override
    install_wallpapers
    install_niri_fish_completions
    install_zed
    install_nerd_font
    configure_xdg_terminal
    configure_niri
    install_niri_edge_indicators
    ensure_github_auth
    set_fish_shell
    create_xdg_dirs
    set_graphical_target
}
