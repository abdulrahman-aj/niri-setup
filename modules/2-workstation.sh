#!/usr/bin/env bash

# -- Constants ----------------------------------------------------------------

readonly BREW_BIN="/home/linuxbrew/.linuxbrew/bin/brew"

readonly CORE_PACKAGES=(
    xwayland-satellite libva-intel-driver intel-media-driver alacritty
    xdg-terminal-exec wl-clipboard fontconfig xdg-user-dirs which fish make neovim
)
readonly BREW_FORMULAE=(starship lazygit lazydocker fzf bat eza ripgrep gh mise tlrc zoxide jq stow fd tree-sitter-cli git-delta steipete/tap/codexbar)
readonly MISE_TOOLS=(opencode codex claude-code)
readonly WALLPAPER_URLS=(
    "https://raw.githubusercontent.com/dharmx/walls/main/nord/a_mountain_range_with_snow_on_top.jpg"
    "https://raw.githubusercontent.com/dharmx/walls/main/nord/a_video_game_graphics_of_a_forest_and_a_lake.png"
    "https://raw.githubusercontent.com/dharmx/walls/main/digital/a_road_with_trees_and_a_mountain_in_the_background.png"
    "https://raw.githubusercontent.com/dharmx/walls/main/nord/a_waterfall_with_trees_and_leaves.jpg"
)

# -- Brew command wrappers ----------------------------------------------------

brew_cmd()      { "$BREW_BIN" "$@"; }
brew_bin_dir()  { dirname "$BREW_BIN"; }
brew_tool_present() { [[ -x "$(brew_bin_dir)/$1" ]]; }
gh_cmd()        { "$(brew_bin_dir)/gh" "$@"; }
mise_cmd()      { "$(brew_bin_dir)/mise" "$@"; }
jq_cmd()        { "$(brew_bin_dir)/jq" "$@"; }
make_cmd()      { PATH="$(brew_bin_dir):$PATH" make "$@"; }
alacritty_cmd() { alacritty "$@"; }
system_fish_cmd() { /usr/bin/fish "$@"; }

webapp_install_cmd() { /usr/local/bin/install-webapp "$@"; }
user_systemctl_cmd() { systemctl --user "$@"; }

# -- Bin-script delegates -----------------------------------------------------

install_homebrew()    { "$ROOT_DIR/bin/install-homebrew"; }
install_docker()      { "$ROOT_DIR/bin/install-docker"; }
install_zed()         { "$ROOT_DIR/bin/install-zed"; }
install_nerd_font()   { "$ROOT_DIR/bin/install-fonts-jetbrains"; }

# -- Install functions --------------------------------------------------------

install_core_packages() {
    install_required_group "workstation essentials" "${CORE_PACKAGES[@]}"
}

install_brew_formulae() {
    local formula missing=()
    for formula in "${BREW_FORMULAE[@]}"; do
        brew_cmd list --formula "$formula" &>/dev/null || missing+=("$formula")
    done
    if ((${#missing[@]})); then
        brew_cmd install "${missing[@]}"
    fi
}

install_mise_tools() {
    local tool
    for tool in "${MISE_TOOLS[@]}"; do
        mise_cmd current "$tool" &>/dev/null || mise_cmd use --global "${tool}@latest"
    done
}

install_commands() {
    local directory="${COMMANDS_DIR:-$ROOT_DIR/bin}" command name first_line found=0
    for command in "$directory"/*; do
        [[ -e "$command" ]] || continue
        found=1
        if [[ ! -f "$command" || ! -x "$command" ]]; then
            err "Invalid command in bin/: ${command}"
            return 1
        fi
        IFS= read -r first_line <"$command" || true
        if [[ "$first_line" != '#!'* ]]; then
            err "Invalid command in bin/: ${command}"
            return 1
        fi
        name="$(basename "$command")"
        install_root_symlink_with_backup "$command" "/usr/local/bin/$name"
    done
    ((found)) || { err "No commands found in: $directory"; return 1; }
    log "Repository commands installed"
}

install_webapps() {
    local manifest="$ROOT_DIR/assets/webapps.json"
    local id name url domain
    jq_cmd -e 'type == "array" and all(.[]; (.id | type == "string") and (.name | type == "string") and (.url | type == "string") and (.domain | type == "string"))' \
        "$manifest" &>/dev/null || { err "Invalid web-app manifest: ${manifest}"; return 1; }
    while IFS=$'\t' read -r id name url domain; do
        webapp_install_cmd "$id" "$name" "$url" "$domain"
    done < <(jq_cmd -r '.[] | [.id, .name, .url, .domain] | @tsv' "$manifest")
    log "Web apps installed"
}

install_wallpapers() {
    local url
    for url in "${WALLPAPER_URLS[@]}"; do
        PATH="$(brew_bin_dir):$PATH" "$ROOT_DIR/bin/install-wallpaper" "$url"
    done
}

# -- System configuration -----------------------------------------------------

ensure_github_auth() {
    local protocol
    gh_cmd auth status &>/dev/null || BROWSER=google-chrome gh_cmd auth login --web --git-protocol ssh
    gh_cmd auth status &>/dev/null || { err "GitHub authentication is not healthy."; return 1; }
    gh_cmd config set git_protocol ssh --host github.com || {
        err "Failed to configure GitHub CLI to use SSH."
        return 1
    }
    protocol="$(gh_cmd config get git_protocol --host github.com)"
    [[ "$protocol" == ssh ]] || { err "GitHub CLI git protocol is not SSH."; return 1; }
}

set_fish_shell() {
    [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" == /usr/bin/fish ]] || s chsh -s /usr/bin/fish "$REAL_USER"
}

create_xdg_dirs() { have_command xdg-user-dirs-update && xdg-user-dirs-update; }

set_graphical_target() {
    [[ "$(systemctl get-default)" == graphical.target ]] || s systemctl set-default graphical.target
}

# -- Orchestration ------------------------------------------------------------

run_workstation_phase() {
    step "Setting up your workstation"

    install_core_packages
    install_docker
    install_homebrew
    install_brew_formulae
    install_mise_tools
    install_commands
    install_webapps
    install_zed
    install_nerd_font
    ensure_github_auth
    set_fish_shell
    create_xdg_dirs
    set_graphical_target
}
