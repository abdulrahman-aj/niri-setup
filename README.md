# Fedora Niri setup

Personal automation: fresh Fedora 44 Workstation → Niri + DankMaterialShell, Alacritty, and dev tools. Idempotent; safe to rerun.

**Requirements:** Fedora 44 Workstation · x86\_64 · Intel graphics · regular user with sudo.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/abdulrahman-aj/niri-setup/main/install.sh | bash
```

Keeps a managed clone at `~/.local/share/niri-setup`. For local dev: `./setup.sh`.
## Update

```bash
workstation-update
```

Resolves the managed clone and reruns `install.sh`. Refuses dirty checkouts or unexpected remotes.

## What gets installed

- **System:** DNF tuned, Chrome, debloat, full upgrade.
- **Desktop:** Niri, DMS, Alacritty, Zed, Fish, Docker CE (disabled by default).
- **CLI:** Starship, lazygit, fzf, gh, mise, jq, …etc (via Homebrew).
- **Dev tools:** OpenCode, Codex, Claude Code (via Mise).
- **Web apps:** Common sites as Chrome app windows (Notion, YouTube, Gmail, …etc).

## Shortcuts

| Shortcut | Action | | Shortcut | Action |
| --- | --- | --- | --- | --- |
| `Mod+Return` / `Mod+T` | Alacritty | | `Mod+W` | Close window |
| `Mod+O` | Overview | | `Mod+Tab` | Next workspace |
| `Mod+Shift+B` | Chrome | | `Mod+Shift+Z` | Zed |
| `Mod+Shift+E` | Files | | `Alt+Shift` | Toggle layout |

## Development

```bash
make        # run all tests
./setup.sh  # run the installer from a local checkout
```
