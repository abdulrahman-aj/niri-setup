#!/usr/bin/env bash

readonly CORE_PACKAGES=(
    xwayland-satellite libva-intel-driver intel-media-driver
    xdg-terminal-exec wl-clipboard fontconfig xdg-user-dirs which fish make
)
readonly BREW_FORMULAE=(starship lazygit lazydocker fzf bat eza ripgrep gh mise tlrc zoxide jq stow fd tree-sitter-cli steipete/tap/codexbar)
readonly MISE_TOOLS=(opencode codex claude-code)

core_stack_complete() { have_command dms && have_command niri && have_command ghostty; }
dms_cmd() { DMS_PRIVESC=sudo dms "$@"; }

run_dankinstall() {
    local tempdir archive installer
    core_stack_complete && { log "DMS, Niri, and Ghostty are already installed"; return 0; }
    tempdir="$(mktemp -d)"
    archive="$tempdir/dankinstall.gz"
    installer="$tempdir/dankinstall"
    trap 'rm -rf "${tempdir:-}"; trap - RETURN' RETURN
    curl -fsSL "$DANKINSTALL_URL" -o "$archive"
    verify_checksum "$archive" "$DANKINSTALL_SHA256" || {
        err "DankInstall checksum verification failed."
        return 1
    }
    gzip -dc "$archive" >"$installer"
    chmod +x "$installer"
    info "DankInstall is interactive; select Niri and Ghostty in the TUI."
    DMS_PRIVESC=sudo "$installer"
    core_stack_complete || {
        err "DankInstall finished without the complete desktop stack."
        return 1
    }
}

install_dms_greeter() {
    have_command dms-greeter || s dnf install -y dms-greeter
    if ! dms_cmd greeter status &>/dev/null; then
        dms_cmd greeter enable
    fi
    dms_cmd greeter sync -y
    dms_cmd greeter status
    log "dms-greeter is configured and synced"
}

apply_dms_settings_override() {
    local settings="$REAL_HOME/.config/DankMaterialShell/settings.json"
    local override="${DMS_SETTINGS_OVERRIDE:-$ROOT_DIR/assets/dms-settings-override.json}" generated
    [[ -f "$settings" ]] || { err "DMS settings do not exist: ${settings}"; return 1; }
    [[ -f "$override" ]] || { err "DMS settings override does not exist: ${override}"; return 1; }
    jq_cmd -e 'type == "object"' "$settings" &>/dev/null || {
        err "DMS settings must contain a valid JSON object: ${settings}"
        return 1
    }
    jq_cmd -e 'type == "object"' "$override" &>/dev/null || {
        err "DMS settings override must contain a valid JSON object: ${override}"
        return 1
    }
    generated="$(mktemp)"
    trap 'rm -f "${generated:-}"; trap - RETURN' RETURN
    jq_cmd -s '.[0] * .[1]' "$settings" "$override" >"$generated" || {
        err "Failed to merge DMS settings."
        return 1
    }
    install_file_atomically_with_backup "$generated" "$settings"
    log "Repository-managed DMS settings applied"
}

install_core_packages() {
    install_required_group "workstation essentials" "${CORE_PACKAGES[@]}"
}

install_niri_fish_completions() {
    local destination="${NIRI_FISH_COMPLETION_FILE:-$REAL_HOME/.local/share/fish/vendor_completions.d/niri.fish}"
    local generated
    generated="$(mktemp)"
    trap 'rm -f "${generated:-}"; trap - RETURN' RETURN
    niri completions fish >"$generated" || {
        err "Failed to generate Niri Fish completions."
        return 1
    }
    if [[ ! -s "$generated" ]] || ! grep -Fq 'complete -c niri' "$generated" || ! fish -n "$generated"; then
        err "Generated Niri Fish completions are invalid."
        return 1
    fi
    install_generated_file_atomically "$generated" "$destination"
    log "Niri Fish completions installed"
}

zed_present() { have_command zed || [[ -x "$REAL_HOME/.local/bin/zed" ]]; }

install_zed() {
    if ! zed_present; then
        curl -f https://zed.dev/install.sh | sh
    fi
    zed_present || { err "Zed installation failed."; return 1; }
}

nerd_font_present() {
    [[ "$(fc-match -f '%{family}\n' 'JetBrainsMono Nerd Font')" == *'JetBrainsMono Nerd Font'* ]]
}

install_nerd_font() {
    local font_dir="$REAL_HOME/.local/share/fonts/JetBrainsMonoNerdFont" tempdir archive
    if nerd_font_present; then
        log "JetBrainsMono Nerd Font is installed"
        return 0
    fi
    tempdir="$(mktemp -d)"
    archive="$tempdir/JetBrainsMono.tar.xz"
    trap 'rm -rf "${tempdir:-}"; trap - RETURN' RETURN
    curl -fsSL "$NERD_FONT_URL" -o "$archive"
    verify_checksum "$archive" "$NERD_FONT_SHA256" || {
        err "Nerd Font checksum verification failed."
        return 1
    }
    mkdir -p "$font_dir"
    tar -xJf "$archive" -C "$font_dir" --wildcards '*.ttf'
    fc-cache -f "$font_dir"
    nerd_font_present || { err "JetBrainsMono Nerd Font was not discovered."; return 1; }
}

configure_xdg_terminal() {
    local file="$REAL_HOME/.config/xdg-terminals.list" temp
    temp="$(mktemp)"
    printf '%s\n' com.mitchellh.ghostty.desktop >"$temp"
    install_file_with_backup "$temp" "$file"
    rm -f "$temp"
    [[ "$(xdg-terminal-exec --print-id)" == com.mitchellh.ghostty.desktop ]] || {
        err "Ghostty is not selected by xdg-terminal-exec."
        return 1
    }
}

user_systemctl_cmd() { systemctl --user "$@"; }

install_niri_edge_indicators() {
    local config="$REAL_HOME/.config/quickshell/niri-edge-indicators"
    local service="$REAL_HOME/.config/systemd/user/niri-edge-indicators.service"
    install_symlink_with_backup "$ROOT_DIR/assets/niri-edge-indicators" "$config"
    install_symlink_with_backup "$ROOT_DIR/assets/niri-edge-indicators.service" "$service"
    user_systemctl_cmd daemon-reload
    user_systemctl_cmd enable --now niri-edge-indicators.service
    log "Niri edge indicators installed"
}

ensure_niri_override_include() {
    local file=$1 generated
    generated="$(mktemp)"
    sed '/^[[:space:]]*include[[:space:]]*"niri-overrides.kdl"[[:space:]]*$/d' "$file" >"$generated"
    printf '\ninclude "niri-overrides.kdl"\n' >>"$generated"
    if ! cmp -s "$generated" "$file"; then
        backup_path "$file"
        install -m 0644 "$generated" "$file"
    fi
    rm -f "$generated"
}

configure_niri() {
    local dir="$REAL_HOME/.config/niri" config override snapshot
    local existed_override=0
    config="$dir/config.kdl"
    override="$dir/niri-overrides.kdl"
    [[ -f "$config" ]] || { err "Niri config does not exist: ${config}"; return 1; }
    snapshot="$(mktemp -d)"
    trap 'rm -rf "${snapshot:-}"; trap - RETURN' RETURN
    cp -a "$config" "$snapshot/config.kdl"
    if [[ -f "$override" ]]; then
        cp -a "$override" "$snapshot/override.kdl"
        existed_override=1
    fi
    install_symlink_with_backup "$ROOT_DIR/assets/niri-overrides.kdl" "$override"
    ensure_niri_override_include "$config"
    if ! niri validate -c "$config"; then
        cp -a "$snapshot/config.kdl" "$config"
        if ((existed_override)); then
            rm -rf -- "$override"
            cp -a "$snapshot/override.kdl" "$override"
        else
            rm -f "$override"
        fi
        err "Niri validation failed; changed Niri files were restored."
        return 1
    fi
}

homebrew_present() { [[ -x "$BREW_BIN" ]]; }

run_homebrew_installer() {
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

brew_cmd() { "$BREW_BIN" "$@"; }
brew_bin_dir() { dirname "$BREW_BIN"; }
brew_tool_present() { [[ -x "$(brew_bin_dir)/$1" ]]; }
gh_cmd() { "$(brew_bin_dir)/gh" "$@"; }
mise_cmd() { "$(brew_bin_dir)/mise" "$@"; }
jq_cmd() { "$(brew_bin_dir)/jq" "$@"; }
make_cmd() { PATH="$(brew_bin_dir):$PATH" make "$@"; }
ghostty_cmd() { ghostty "$@"; }
system_fish_cmd() { /usr/bin/fish "$@"; }

install_homebrew() {
    local bashrc line generated
    homebrew_present || run_homebrew_installer
    homebrew_present || { err "Homebrew installation failed."; return 1; }
    # shellcheck disable=SC2016 # This must run when a future Bash shell starts.
    line='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
    bashrc="$REAL_HOME/.bashrc"
    touch "$bashrc"
    if ! grep -Fqx "$line" "$bashrc"; then
        generated="$(mktemp)"
        cat "$bashrc" >"$generated"
        printf '\n%s\n' "$line" >>"$generated"
        install_file_with_backup "$generated" "$bashrc"
        rm -f "$generated"
    fi
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

configure_application_launchers() {
    local manifest="$ROOT_DIR/assets/webapps.json"
    local applications="$REAL_HOME/.local/share/applications"
    local icons="$REAL_HOME/.local/share/icons/hicolor/128x128/apps"
    local tempdir id name url domain icon_name icon_file desktop generated_icon
    jq_cmd -e 'type == "array" and all(.[]; (.id | type == "string") and (.name | type == "string") and (.url | type == "string") and (.domain | type == "string"))' \
        "$manifest" &>/dev/null || { err "Invalid web-app manifest: ${manifest}"; return 1; }
    install_root_symlink_with_backup "$ROOT_DIR/assets/launch-or-focus-webapp" /usr/local/bin/launch-or-focus-webapp
    install_root_symlink_with_backup "$ROOT_DIR/assets/launch-or-focus-tui" /usr/local/bin/launch-or-focus-tui
    remove_root_path_with_backup /usr/local/bin/launch-or-focus
    mkdir -p "$applications" "$icons"
    tempdir="$(mktemp -d)"
    trap 'rm -rf "${tempdir:-}"; trap - RETURN' RETURN
    while IFS=$'\t' read -r id name url domain; do
        [[ "$id" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ && "$url" == https://* && "$domain" != *[!A-Za-z0-9.-]* ]] || {
            err "Invalid web-app manifest entry: ${id:-missing-id}"
            return 1
        }
        icon_name="niri-webapp-$id"
        icon_file="$icons/$icon_name.png"
        if [[ ! -s "$icon_file" ]]; then
            generated_icon="$tempdir/$icon_name.png"
            if curl -fsSL --retry 2 "https://www.google.com/s2/favicons?domain=$domain&sz=128" -o "$generated_icon" && [[ -s "$generated_icon" ]]; then
                install_file_atomically_with_backup "$generated_icon" "$icon_file"
            else
                warn "Could not download ${name} icon; using the Chrome icon"
                icon_name=google-chrome
            fi
        fi
        desktop="$tempdir/niri-webapp-$id.desktop"
        printf '%s\n' \
            '[Desktop Entry]' \
            'Version=1.0' \
            'Type=Application' \
            "Name=$name" \
            "Exec=/usr/local/bin/launch-or-focus-webapp $id $url" \
            "Icon=$icon_name" \
            "StartupWMClass=niri-webapp-$id" \
            'Terminal=false' \
            'Categories=Network;WebBrowser;' \
            >"$desktop"
        install_file_atomically_with_backup "$desktop" "$applications/niri-webapp-$id.desktop"
    done < <(jq_cmd -r '.[] | [.id, .name, .url, .domain] | @tsv' "$manifest")
    have_command update-desktop-database && update-desktop-database "$applications"
    log "Application launch-or-focus helpers and web-app launchers configured"
}

configure_git() {
    git config --global init.defaultBranch main
    git config --global user.name 'Abdulrahman Ajlouni'
    git config --global user.email ajlouni2000@gmail.com
}

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

validate_dotfiles_fish() {
    local config="$1/fish/.config/fish/config.fish" plugins="$1/fish/.config/fish/fish_plugins"
    local brew_line prefix_line
    [[ -f "$config" ]] || { err "Dotfiles Fish config was not found: ${config}"; return 1; }
    [[ -f "$plugins" ]] || { err "Dotfiles Fish plugin manifest was not found: ${plugins}"; return 1; }
    [[ ! -e "$1/fish/.config/fish/fish_variables" ]] || {
        err "Dotfiles must not track mutable Fish universal variables."
        return 1
    }
    grep -Fxq 'jorgebucaran/fisher' "$plugins" || { err "fish_plugins must include Fisher."; return 1; }
    grep -Fxq 'PatrickF1/fzf.fish' "$plugins" || { err "fish_plugins must include fzf.fish."; return 1; }
    brew_line="$(grep -nFm1 '/home/linuxbrew/.linuxbrew/bin/brew shellenv' "$config" | cut -d: -f1 || true)"
    prefix_line="$(grep -nFm1 'brew --prefix' "$config" | cut -d: -f1 || true)"
    if [[ -z "$brew_line" || ( -n "$prefix_line" && "$brew_line" -ge "$prefix_line" ) ]]; then
        err "Dotfiles Fish config must initialize /home/linuxbrew/.linuxbrew/bin/brew shellenv before brew --prefix usage."
        err "Update, commit, and push the dotfiles repository before rerunning setup."
        return 1
    fi
    grep -Rqs 'mise activate fish' "$1/fish" || { err "Dotfiles Fish config does not activate Mise."; return 1; }
    grep -Rqs 'starship init fish' "$1/fish" || { err "Dotfiles Fish config does not activate Starship."; return 1; }
}

validate_dotfiles_ghostty() {
    local config="$1/ghostty/.config/ghostty/config" isolated
    [[ -f "$config" ]] || { err "Dotfiles Ghostty config was not found: ${config}"; return 1; }
    isolated="$(mktemp -d)"
    trap 'rm -rf "${isolated:-}"; trap - RETURN' RETURN
    mkdir -p "$isolated/ghostty"
    ln -s "$config" "$isolated/ghostty/config"
    XDG_CONFIG_HOME="$isolated" ghostty_cmd +validate-config || {
        err "Dotfiles Ghostty config is invalid: ${config}"
        return 1
    }
}

validate_dotfiles_makefile() {
    local dotdir=$1 makefile="$1/Makefile"
    [[ -f "$makefile" ]] || { err "Dotfiles Makefile was not found: ${makefile}"; return 1; }
    make_cmd -n -C "$dotdir" check TARGET="$REAL_HOME" &>/dev/null || {
        err "Dotfiles Makefile does not provide a valid check target."
        return 1
    }
    make_cmd -n -C "$dotdir" stow TARGET="$REAL_HOME" &>/dev/null || {
        err "Dotfiles Makefile does not provide a valid stow target."
        return 1
    }
}

prepare_fish_config_directory() {
    local dotdir=$1 config="$REAL_HOME/.config/fish" expected saved
    expected="$(readlink -f "$dotdir/fish/.config/fish")"
    if [[ -L "$config" ]]; then
        [[ "$(readlink -f "$config")" == "$expected" ]] || {
            err "Unexpected Fish config symlink: ${config}"
            return 1
        }
        saved="$(mktemp)"
        trap 'rm -f "${saved:-}"; trap - RETURN' RETURN
        [[ ! -f "$config/fish_variables" ]] || cp "$config/fish_variables" "$saved"
        rm "$config"
        mkdir -p "$config"
        [[ ! -s "$saved" ]] || install -m 0600 "$saved" "$config/fish_variables"
    elif [[ -e "$config" && ! -d "$config" ]]; then
        err "Fish config path is not a directory: ${config}"
        return 1
    else
        mkdir -p "$config"
    fi
}

prepare_ghostty_config() {
    local dotdir=$1 destination="$REAL_HOME/.config/ghostty/config" expected
    expected="$dotdir/ghostty/.config/ghostty/config"
    if [[ -L "$destination" && "$(readlink -f "$destination")" == "$(readlink -f "$expected")" ]]; then
        return 0
    fi
    if [[ -e "$destination" || -L "$destination" ]]; then
        backup_path "$destination"
        rm -rf -- "$destination"
    fi
}

install_dotfiles() {
    local dotdir="$REAL_HOME/.dotfiles"
    [[ -d "$dotdir" ]] || gh_cmd repo clone abdulrahman-aj/dotfiles "$dotdir"
    validate_existing_dotfiles
    validate_dotfiles_fish "$dotdir"
    validate_dotfiles_ghostty "$dotdir"
    validate_dotfiles_makefile "$dotdir"
    prepare_fish_config_directory "$dotdir"
    make_cmd -C "$dotdir" check TARGET="$REAL_HOME" PKGS='fish zed' || {
        err "Stow detected conflicts; no dotfiles were changed."
        return 1
    }
    prepare_ghostty_config "$dotdir"
    make_cmd -C "$dotdir" check TARGET="$REAL_HOME" || {
        err "Stow detected conflicts; the Ghostty backup was preserved, but no dotfiles were stowed."
        return 1
    }
    make_cmd -C "$dotdir" stow TARGET="$REAL_HOME"
    [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" == /usr/bin/fish ]] || s chsh -s /usr/bin/fish "$REAL_USER"
}

install_fish_plugins() {
    local bootstrap data
    bootstrap="$(mktemp)"
    trap 'rm -f "${bootstrap:-}"; trap - RETURN' RETURN
    curl -fsSL "$FISHER_BOOTSTRAP_URL" -o "$bootstrap"
    system_fish_cmd -n "$bootstrap" || { err "Downloaded Fisher bootstrap is invalid."; return 1; }
    # shellcheck disable=SC2016 # Fish expands argv inside the command string.
    system_fish_cmd -c 'source $argv[1]; fisher update' "$bootstrap"
    system_fish_cmd -c 'type -q fisher; and fisher list | string lower | string match -q patrickf1/fzf.fish' || {
        err "Fisher did not install the configured Fish plugins."
        return 1
    }
    data="${XDG_DATA_HOME:-$REAL_HOME/.local/share}/fish"
    rm -rf "$data/niri-setup/fzf.fish"
    rm -f "$data/vendor_conf.d/niri-setup-fzf.fish"
    log "Fish plugins installed from the tracked Fisher manifest"
}

install_mise_tools() {
    local tool
    for tool in "${MISE_TOOLS[@]}"; do
        mise_cmd current "$tool" &>/dev/null || mise_cmd use --global "${tool}@latest"
    done
}

install_docker() {
    local sudoers temp docker_plugin_dir update_plugin_dir
    if ! dnf repolist 2>/dev/null | grep -Eq '^docker-ce-stable([[:space:]]|$)'; then
        s dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
    fi
    s dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    install_root_symlink_with_backup "$ROOT_DIR/assets/docker-toggle" /usr/local/bin/docker-toggle
    install_root_symlink_with_backup "$ROOT_DIR/install.sh" /usr/local/bin/update-workstation
    install_root_symlink_with_backup "$ROOT_DIR/assets/workstation-update-status" /usr/local/bin/workstation-update-status
    remove_root_path_with_backup /usr/local/bin/niri-setup-update
    temp="$(mktemp)"
    trap 'rm -f "${temp:-}"; trap - RETURN' RETURN
    printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start docker.service docker.socket, /usr/bin/systemctl stop docker.service docker.socket\n' "$REAL_USER" >"$temp"
    visudo -cf "$temp" &>/dev/null || { err "Generated Docker sudoers rule is invalid."; return 1; }
    sudoers=/etc/sudoers.d/docker-toggle
    install_root_file_with_backup "$temp" "$sudoers" 0440
    remove_root_path_with_backup /etc/sudoers.d/niri-setup-docker-toggle
    docker_plugin_dir="$REAL_HOME/.config/DankMaterialShell/plugins/dockerToggle"
    update_plugin_dir="$REAL_HOME/.config/DankMaterialShell/plugins/workstationUpdate"
    install_symlink_with_backup "$ROOT_DIR/assets/dms-docker-toggle" "$docker_plugin_dir"
    install_symlink_with_backup "$ROOT_DIR/assets/dms-workstation-update" "$update_plugin_dir"
    s systemctl disable --now docker.service docker.socket
    if ! id -nG "$REAL_USER" | tr ' ' '\n' | grep -Fxq docker; then
        s usermod -aG docker "$REAL_USER"
        warn "The docker group is root-equivalent. Log out or reboot before using Docker without sudo."
    fi
    [[ "$(systemctl is-enabled docker.service 2>/dev/null || true)" == disabled ]]
    [[ "$(systemctl is-enabled docker.socket 2>/dev/null || true)" == disabled ]]
    ! systemctl is-active --quiet docker.service
    ! systemctl is-active --quiet docker.socket
    warn "Enable dockerToggle in DMS Plugins, then add it to the right side of DankBar."
}

create_xdg_dirs() { have_command xdg-user-dirs-update && xdg-user-dirs-update; }

set_graphical_target() {
    [[ "$(systemctl get-default)" == graphical.target ]] || s systemctl set-default graphical.target
}

run_workstation_phase() {
    step "Core workstation"
    run_dankinstall
    install_core_packages
    install_niri_fish_completions
    install_homebrew
    install_brew_formulae
    configure_application_launchers
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
    install_docker
    create_xdg_dirs
    set_graphical_target
}
