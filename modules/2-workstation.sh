#!/usr/bin/env bash
# shellcheck disable=SC2034 # Constants are consumed by sourced workstation components.

readonly CORE_PACKAGES=(
    xwayland-satellite libva-intel-driver intel-media-driver alacritty
    xdg-terminal-exec wl-clipboard fontconfig xdg-user-dirs which fish make
)
readonly BREW_FORMULAE=(starship lazygit lazydocker fzf bat eza ripgrep gh mise tlrc zoxide jq stow fd tree-sitter-cli steipete/tap/codexbar)
readonly MISE_TOOLS=(opencode codex claude-code)

source_modules "$ROOT_DIR/modules/workstation"

run_workstation_phase() {
    step "Core workstation"
    run_dankinstall
    install_core_packages
    install_niri_fish_completions
    install_homebrew
    install_brew_formulae
    install_commands
    install_webapps
    apply_dms_settings_override
    install_dms_greeter
    install_zed
    install_nerd_font
    configure_xdg_terminal
    configure_niri
    install_niri_edge_indicators
    configure_git
    ensure_github_auth
    install_dotfiles
    install_fish_plugins
    install_mise_tools
    install_workstation_update_plugin
    install_docker
    create_xdg_dirs
    set_graphical_target
}
