# Fedora Niri workstation setup

Personal automation that turns a fresh Fedora 44 Workstation into a Niri desktop
with DankMaterialShell (DMS), Ghostty, my dotfiles, development tools, and
on-demand Docker.

Run as a regular user with sudo on Fedora 44 Workstation (x86_64, Intel
graphics) with an internet connection.

## Install

The repository must be public for this unauthenticated bootstrap. Review
`install.sh` first if you don't already trust the remote:

```bash
curl -fsSL https://raw.githubusercontent.com/abdulrahman-aj/niri-setup/main/install.sh | bash
```

This keeps a clean HTTPS clone at `~/.local/share/niri-setup`. To run a
development checkout directly, use `./setup.sh`.

During an interactive run: DankInstall opens a TUI when Niri, DMS, or Ghostty is
missing (select Niri and Ghostty); GitHub CLI may open Chrome for auth; and you
are offered Kickstart.nvim plus the third-party CodexBar and Wallpaper Discovery
DMS plugins (default yes). Non-interactive runs install Kickstart and skip the
DMS plugins. Optional failures never fail the core setup.

## Update

```bash
workstation-update
```

This resolves the managed clone and delegates to its `install.sh`, so bootstrap
and updates share one validation path. It refuses dirty checkouts or unexpected
remotes. Niri and Docker-widget assets are linked from whichever checkout last
ran `setup.sh`.

## Dotfiles prerequisite

The installer stows [`abdulrahman-aj/dotfiles`](https://github.com/abdulrahman-aj/dotfiles)
into `~/.dotfiles`. Before bootstrapping a fresh machine, ensure that repo:

- Evaluates `/home/linuxbrew/.linuxbrew/bin/brew shellenv` before its first
  `brew` use in Fish.
- Tracks `fish_plugins` but leaves `fish_variables` untracked.
- Contains a valid `ghostty/.config/ghostty/config` (setup validates it in an
  isolated config home before Stow runs).

## What it does

Idempotent and rerunnable. Each run still performs a system upgrade and resets
Docker to disabled. DankInstall and setup-invoked DMS commands use
`DMS_PRIVESC=sudo`.

- **System:** DNF with 10 parallel downloads and `defaultyes=True`; timezone
  `Asia/Amman` with `en_US.UTF-8` time locale and 12-hour clocks (repo-managed
  DMS preferences merged over generated settings); installs Chrome, debloats
  Firefox/LibreOffice/select GNOME extras, then full upgrade.
- **Desktop stack:** enables the DMS and DankLinux COPRs; installs Niri, DMS,
  Ghostty, Zed, JetBrainsMono Nerd Font, Homebrew, CLI tools, and rootful
  Docker CE. Sets Chrome as default browser, Ghostty as XDG terminal, Fish as
  login shell, and `graphical.target` as the default target.
- **Dev environment:** configures Git, requires GitHub CLI SSH auth, clones or
  validates `~/.dotfiles`, and stows `fish`, `ghostty`, `zed`.
- **Assets and commands:** symlinks managed Niri/helper/DMS assets (backing up
  replacements as timestamped `.backup-*`), links every `bin/` script into
  `/usr/local/bin`, and installs the local `dockerToggle` DMS plugin.

DankInstall and Nerd Font downloads are version-pinned and checksum-verified. To
bump a pin: change its version and URL, download the archive, recompute the hash
with `sha256sum`, update the recorded checksum, and run the tests.

## Installed behavior

- **Tools:** Fedora provides Make. Homebrew installs Stow, Starship, lazygit,
  lazydocker, fzf, bat, eza, ripgrep, GitHub CLI, Mise, Zoxide, `tlrc`, jq, fd,
  and `steipete/tap/codexbar`. Mise installs OpenCode, Codex, and Claude Code.
  Dotfiles conflict checks and installation run via the repo's `make check` and
  `make stow`.
- **Shell/editor config:** Fish, Ghostty, and Zed config come from dotfiles.
  Ghostty uses Dark Modern colors (matching Zed), JetBrains Mono Nerd Font
  Regular size 10, and a compact decoration-free window; an existing
  DMS-generated Ghostty config is backed up once before replacement, and DMS's
  `themes/dankcolors` is left untouched. Fish has Zoxide-backed `cd`. Fisher
  installs plugins from `fish_plugins` (including `fzf.fish`); add more with
  `fisher install owner/repo` and commit only the `fish_plugins` manifest.
- **Niri:** US/Arabic layout switching on `Alt+Shift`, repeat delay `200` /
  rate `25`, DMS lock on lid close, maximized Zed/Chrome/Ghostty/TUI windows,
  and full-width new columns. Subtle non-interactive chevrons at the screen
  edges indicate additional columns. Keys: `Mod+Return` Ghostty, `Mod+W` close,
  `Mod+Tab` workspace nav, `Mod+O` Overview, hybrid window/workspace nav on
  `Mod+J/K` and `Mod+Up/Down`, Chrome on `Mod+Shift+B` (incognito
  `Mod+Shift+Alt+B`).
- **Web apps:** open as Chrome app windows and focus their existing Niri window
  on relaunch; downloaded favicons fall back to Chrome's icon. `webapp-install`
  takes an ID, display name, HTTPS URL, and favicon domain.
- **Docker:** stays disabled until started. The `dockerToggle` widget shows a
  Docker icon, toggles the daemon on left-click, and opens/focuses lazydocker
  (without starting Docker) on right-click.

### Application shortcuts

| Shortcut | Application | | Shortcut | Application |
| --- | --- | --- | --- | --- |
| `Mod+Shift+N` | Notion | | `Mod+Shift+M` | YouTube Music |
| `Mod+Shift+R` | Reddit | | `Mod+Shift+G` | Gmail |
| `Mod+Shift+C` | Google Calendar | | `Mod+Shift+D` | Discord |
| `Mod+Shift+A` | ChatGPT | | `Mod+Shift+Z` | Zed |
| `Mod+Shift+Y` | YouTube | | `Mod+Shift+E` | Files |

## After installation

Set `eDP-1` scale to `1.67` in DMS, then reboot or re-login. In DMS Settings,
enable the local `dockerToggle` and `workstationUpdate` plugins and place them on
DankBar (ordering is manual), and add **Keyboard Layout Name** with its
**Compact** option to show `EN`/`AR`.

Verify:

- [ ] Chrome opens desktop links; Ghostty is the default terminal.
- [ ] GitHub auth, SSH fetch, and SSH push work.
- [ ] **Workstation Update** stays hidden while current; when shown, left-click
  opens `workstation-update` in a new terminal and right-click refreshes status.
- [ ] Docker is inactive after reboot; the widget toggles it, right-click opens
  lazydocker without starting it, and `docker run --rm hello-world` works without
  sudo while active.
- [ ] Niri loads without warnings; scaling, keybindings, maximized windows,
  Arabic switching, and Nerd Font rendering all work.
- [ ] Installed CLI tools are available in a fresh Fish login shell, with Zoxide
  `cd`.
- [ ] Selected optional plugins and Kickstart.nvim work, including Wayland
  clipboard integration.

## Validation

```bash
bash tests/setup-test.sh
```
