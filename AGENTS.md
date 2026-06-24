# niri-setup

Personal automation to bootstrap a fresh Fedora 44 Workstation into a Niri desktop with DankMaterialShell (DMS), Alacritty, dotfiles, and development tools.

## Purpose

Idempotent installer targeting Fedora 44 / x86_64 / Intel graphics. Designed to run both as a one-shot bootstrap (`curl | bash` via `install.sh`) and as a local dev checkout (`./setup.sh`). Updates go through `workstation-update` which resolves the managed clone at `~/.local/share/niri-setup`.

## Key directories

| Path | Contents |
|---|---|
| `setup.sh` | Entry point: validates environment, sources modules in order |
| `install.sh` | Bootstrap: clones/updates managed checkout, then delegates to `setup.sh` |
| `modules/1-system.sh` | DNF config, timezone, system upgrade, Chrome, debloat |
| `modules/2-workstation.sh` | Niri, DMS, Alacritty, dotfiles, dev tools — sources `modules/workstation/` |
| `modules/3-optional.sh` | Optional extras (DMS plugins, Kickstart.nvim) — failures never abort |
| `modules/workstation/` | Submodules: commands, desktop, development, docker, dotfiles, webapps |
| `lib/common.sh` | Shared logging helpers, `s()` sudo wrapper, guard functions |
| `lib/git-remote.sh` | Remote-validation helpers used by `workstation-update` |
| `bin/` | Installed helper scripts: `launch-or-focus`, `webapp-*`, `docker-toggle`, `workstation-update`, `tui-launch-or-focus` |
| `assets/` | Static config: `niri-overrides.kdl`, `dms-settings-override.json`, `niri-edge-indicators/`, `dms-plugins/`, `webapps.json` |
| `tests/lib.sh` | Shared test framework: `run_test`, `make_tempdir/file`, `assert_*` helpers |
| `tests/test-*.sh` | TAP-style unit tests split by domain: setup, system, desktop, dotfiles, development, commands, optional |

## Commands

```bash
# Run tests
make

# Run the full installer from a local checkout
./setup.sh

# Update from managed clone
workstation-update
```

## Architecture decisions

- **Managed clone** at `~/.local/share/niri-setup` is what live services reference (not `~/Work/niri-setup`). After local changes, sync the managed clone and restart services to verify.
- **Modules load in numeric order** (`1-system`, `2-workstation`, `3-optional`). System-level ops come first so later modules can rely on installed packages.
- **`assets/dms-settings-override.json`** is merged over generated DMS settings on every run to keep repo-managed preferences (e.g. frozen `barConfigs`).
- **No active-window decorations**: all niri focus cues (dim/ring/border/shadow) are intentionally absent — do not re-add them.
- **Terminal is Alacritty** — Ghostty was evaluated and rejected (leaked ~1.5 GB idle). Do not reintroduce it.
- **DMS_PRIVESC=sudo** is set for DankInstall and setup-invoked DMS commands.
- **Optional failures** accumulate in `OPTIONAL_FAILURES[]` and are reported at the end without aborting the install.
