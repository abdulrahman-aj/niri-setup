# Fedora Niri workstation setup

Personal automation for turning a fresh Fedora 44 Workstation installation
into a Niri desktop with DankMaterialShell (DMS), Ghostty, development tools,
my dotfiles, and on-demand Docker.

## Requirements

Run as a regular user with sudo access on Fedora 44 Workstation, x86_64, Intel
graphics, and an internet connection.

## What it does

- Sets DNF to 10 parallel downloads and `defaultyes=True`.
- Sets the system timezone to `Asia/Amman`, uses `en_US.UTF-8` time-locale
  semantics, and merges repository-managed DMS preferences—including 12-hour
  AM/PM clocks—over the generated DMS settings.
- Installs Chrome from Fedora's managed repository before debloating, removes
  Firefox, LibreOffice, and selected GNOME extras, then runs a full system
  upgrade.
- Enables the DMS and DankLinux COPRs, installs Niri, DMS, Ghostty, Zed,
  JetBrainsMono Nerd Font, Homebrew, developer CLI tools, and rootful Docker
  CE.
- Sets Chrome as the default browser, Ghostty as the XDG terminal, Fedora Fish as the
  login shell, and `graphical.target` as the default target.
- Configures Git, requires GitHub CLI auth over SSH, clones or validates
  `~/.dotfiles`, and stows only `fish` and `zed`.
- Installs a local `dockerToggle` DMS plugin and keeps Docker disabled until
  explicitly started.
- Installs Niri-native launch-or-focus helpers and named Chrome web-app
  launchers for DMS search and application menus.
- Symlinks managed Niri, helper, and DMS assets from this repo, backing up
  replaced files with timestamped `.backup-*` names.

The setup is intended to be rerunnable. Each run still performs a system
upgrade and disables/stops Docker again to restore the expected default state.

## Dotfiles prerequisite

The installer uses
[`abdulrahman-aj/dotfiles`](https://github.com/abdulrahman-aj/dotfiles). Its
Fish configuration must evaluate
`/home/linuxbrew/.linuxbrew/bin/brew shellenv` before its first `brew --prefix`
use, track `fish_plugins`, and leave `fish_variables` untracked. Commit and push
those changes before bootstrapping a fresh machine.

## Install

The repository must be public for this unauthenticated bootstrap:

```bash
curl -fsSL https://raw.githubusercontent.com/abdulrahman-aj/niri-setup/main/install.sh | bash
```

This maintains a clean HTTPS clone at `~/.local/share/niri-setup`. Review
`install.sh` before piping it to Bash if the remote contents are not already
trusted.

To run a development checkout directly:

```bash
./setup.sh
```

DankInstall opens an interactive TUI when Niri, DMS, or Ghostty is missing;
select Niri and Ghostty. GitHub CLI may open Chrome for authentication.

## Update

Update the managed clone and rerun the setup with:

```bash
update-workstation
```

The command is a symlink to the checkout's `install.sh`, so bootstrap and
updates share the same validation and update path. It refuses dirty checkouts
or unexpected remotes. Repository assets for Niri and the Docker widget are
also linked from whichever checkout last ran `setup.sh`.

DankInstall and Nerd Font downloads are version-pinned and checksum-verified.
To update a pin, change its version and URL, download the new archive, calculate
its hash with `sha256sum`, update the recorded checksum, and run the tests.

## Installed behavior

- Homebrew installs Starship, lazygit, lazydocker, fzf, bat, eza, ripgrep, GitHub CLI,
  Mise, Zoxide, `tlrc`, jq, Stow, and fd. Mise installs OpenCode, Codex, and
  Claude Code.
- Fish and Zed configuration comes from the dotfiles repo. Fish includes your
  Zoxide-backed `cd` behavior. Fisher installs the plugins tracked in
  `fish_plugins`, including `fzf.fish`; generated plugin files, universal
  variables, and Niri completions remain outside the dotfiles checkout.
- Add plugins with `fisher install owner/repository`. Commit only the resulting
  `fish_plugins` manifest when the plugin should follow you to other machines.
- The local Niri override enables US/Arabic layout switching with `Alt+Shift`,
  repeat delay `200`, repeat rate `25`, DMS lock on lid close, maximized
  Zed/Chrome windows, `Mod+W` close, `Mod+Return` Ghostty, and Chrome normal
  and incognito on `Mod+Shift+B` and `Mod+Shift+Alt+B`.
- Web apps open as Chrome app windows and focus their existing Niri window on
  subsequent launches. Their downloaded favicons fall back to Chrome's icon if
  unavailable.
- The `dockerToggle` DMS widget shows a Docker icon, toggles the daemon on
  left-click, and opens or focuses lazydocker without starting Docker on
  right-click.

### Launch-or-focus shortcuts

| Shortcut | Application |
| --- | --- |
| `Mod+Shift+N` | Notion |
| `Mod+Shift+R` | Reddit |
| `Mod+Shift+C` | Google Calendar |
| `Mod+Shift+A` | ChatGPT |
| `Mod+Shift+Y` | YouTube |
| `Mod+Shift+M` | YouTube Music |
| `Mod+Shift+G` | Gmail |
| `Mod+Shift+D` | Discord |
| `Mod+Shift+Z` | Zed |
| `Mod+Shift+E` | Files |

## Optional prompts

Interactive runs offer Kickstart.nvim and the third-party CodexBar and
Wallpaper Discovery DMS plugins. Both prompts default to yes. Non-interactive
runs install Kickstart and skip the DMS plugins. Optional failures do not fail
the core setup.

## After installation

Set `eDP-1` scale to `1.67` through DMS, then reboot or log out and back in.
Enable the local `dockerToggle` plugin in DMS Settings and add it to DankBar's
right side.

- [ ] Chrome opens desktop links; Ghostty is the default terminal.
- [ ] GitHub authentication, SSH fetch, and SSH push work.
- [ ] Docker is inactive after reboot; its widget toggles it, right-click opens
  lazydocker without starting it, and `docker run --rm hello-world` works
  without sudo while active.
- [ ] Niri loads without warnings; display scales, keybindings, maximized
  windows, Arabic switching, and Nerd Font rendering work as expected.
- [ ] All installed CLI tools are available in a fresh Fish login shell, and
  `cd` uses normal paths plus Zoxide queries.
- [ ] Selected optional plugins and Kickstart.nvim work, including Wayland
  clipboard integration.

## Validation

```bash
bash tests/setup-test.sh
```
