#!/usr/bin/env bash

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

