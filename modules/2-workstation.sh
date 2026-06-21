#!/usr/bin/env bash

readonly CORE_PACKAGES=(
    xwayland-satellite libva-intel-driver intel-media-driver
    xdg-terminal-exec wl-clipboard fontconfig xdg-user-dirs which fish
)
readonly BREW_FORMULAE=(starship lazygit lazydocker fzf ripgrep gh mise tlrc zoxide jq stow fd)
readonly MISE_TOOLS=(opencode codex claude-code)

core_stack_complete() { have_command dms && have_command niri && have_command ghostty; }

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
    "$installer"
    core_stack_complete || {
        err "DankInstall finished without the complete desktop stack."
        return 1
    }
}

install_dms_greeter() {
    have_command dms-greeter || s dnf install -y dms-greeter
    if ! dms greeter status &>/dev/null; then
        dms greeter enable
    fi
    dms greeter sync -y
    dms greeter status
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
gh_cmd() { "$(dirname "$BREW_BIN")/gh" "$@"; }
mise_cmd() { "$(dirname "$BREW_BIN")/mise" "$@"; }
jq_cmd() { "$(dirname "$BREW_BIN")/jq" "$@"; }
stow_cmd() { "$(dirname "$BREW_BIN")/stow" "$@"; }

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

configure_launch_or_focus() {
    local manifest="$ROOT_DIR/assets/webapps.json"
    local applications="$REAL_HOME/.local/share/applications"
    local icons="$REAL_HOME/.local/share/icons/hicolor/128x128/apps"
    local tempdir id name url domain icon_name icon_file desktop generated_icon
    jq_cmd -e 'type == "array" and all(.[]; (.id | type == "string") and (.name | type == "string") and (.url | type == "string") and (.domain | type == "string"))' \
        "$manifest" &>/dev/null || { err "Invalid web-app manifest: ${manifest}"; return 1; }
    install_root_symlink_with_backup "$ROOT_DIR/assets/launch-or-focus" /usr/local/bin/launch-or-focus
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
            "Exec=/usr/local/bin/launch-or-focus webapp $id $url" \
            "Icon=$icon_name" \
            "StartupWMClass=niri-webapp-$id" \
            'Terminal=false' \
            'Categories=Network;WebBrowser;' \
            >"$desktop"
        install_file_atomically_with_backup "$desktop" "$applications/niri-webapp-$id.desktop"
    done < <(jq_cmd -r '.[] | [.id, .name, .url, .domain] | @tsv' "$manifest")
    have_command update-desktop-database && update-desktop-database "$applications"
    log "Launch-or-focus helpers and web-app launchers configured"
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
    local config="$1/fish/.config/fish/config.fish" brew_line prefix_line
    [[ -f "$config" ]] || { err "Dotfiles Fish config was not found: ${config}"; return 1; }
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

install_dotfiles() {
    local dotdir="$REAL_HOME/.dotfiles" fish_path
    [[ -d "$dotdir" ]] || gh_cmd repo clone abdulrahman-aj/dotfiles "$dotdir"
    validate_existing_dotfiles
    validate_dotfiles_fish "$dotdir"
    stow_cmd --simulate -d "$dotdir" -t "$REAL_HOME" fish zed || {
        err "Stow detected conflicts; no dotfiles were changed."
        return 1
    }
    stow_cmd -d "$dotdir" -t "$REAL_HOME" fish zed
    fish_path="$(command -v fish)"
    [[ "$(getent passwd "$REAL_USER" | cut -d: -f7)" == "$fish_path" ]] || s chsh -s "$fish_path" "$REAL_USER"
}

install_mise_tools() {
    local tool
    for tool in "${MISE_TOOLS[@]}"; do
        mise_cmd current "$tool" &>/dev/null || mise_cmd use --global "${tool}@latest"
    done
}

install_docker() {
    local sudoers temp plugin_dir
    if ! dnf repolist 2>/dev/null | grep -Eq '^docker-ce-stable([[:space:]]|$)'; then
        s dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
    fi
    s dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    install_root_symlink_with_backup "$ROOT_DIR/assets/docker-toggle" /usr/local/bin/docker-toggle
    install_root_symlink_with_backup "$ROOT_DIR/install.sh" /usr/local/bin/update-workstation
    remove_root_path_with_backup /usr/local/bin/niri-setup-update
    temp="$(mktemp)"
    trap 'rm -f "${temp:-}"; trap - RETURN' RETURN
    printf '%s ALL=(root) NOPASSWD: /usr/bin/systemctl start docker.service docker.socket, /usr/bin/systemctl stop docker.service docker.socket\n' "$REAL_USER" >"$temp"
    visudo -cf "$temp" &>/dev/null || { err "Generated Docker sudoers rule is invalid."; return 1; }
    sudoers=/etc/sudoers.d/docker-toggle
    install_root_file_with_backup "$temp" "$sudoers" 0440
    remove_root_path_with_backup /etc/sudoers.d/niri-setup-docker-toggle
    plugin_dir="$REAL_HOME/.config/DankMaterialShell/plugins/dockerToggle"
    install_symlink_with_backup "$ROOT_DIR/assets/dms-docker-toggle" "$plugin_dir"
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
    configure_launch_or_focus
    apply_dms_settings_override
    install_dms_greeter
    install_zed
    install_nerd_font
    configure_xdg_terminal
    configure_niri
    configure_git
    ensure_github_auth
    install_dotfiles
    install_mise_tools
    install_docker
    create_xdg_dirs
    set_graphical_target
}
