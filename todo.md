# TODO

- [ ] Choose a database client:
  - GUI: [DBeaver Community](https://dbeaver.io/) or
    [Beekeeper Studio Community](https://www.beekeeperstudio.io/).
  - Terminal: [Harlequin](https://harlequin.sh/) or
    [Rainfrog](https://github.com/achristmascarl/rainfrog).
- [ ] Implement Niri-native web-app and launch-or-focus helpers:
  - Use Chrome app windows and exact matches from `niri msg -j windows`.
  - Focus matches with `niri msg action focus-window --id`; never use `eval`.
  - Generate named, correctly iconed `.desktop` launchers for DMS search and
    application menus.
- [ ] Implement a Niri-native launch-or-focus TUI helper:
  - Accept a command and arguments safely.
  - Derive a stable per-command Ghostty app ID.
  - Focus an existing exact match or launch with
    `xdg-terminal-exec --app-id=...`.
  - Replace `dockerToggle`'s temporary direct lazydocker launch.
- [ ] Add launch-or-focus shortcuts:
  - `Mod+Shift+N`: Notion (`https://www.notion.so`)
  - `Mod+Shift+R`: Reddit (`https://www.reddit.com`)
  - `Mod+Shift+C`: Google Calendar (`https://calendar.google.com`)
  - `Mod+Shift+A`: ChatGPT (`https://chatgpt.com`)
  - `Mod+Shift+Y`: YouTube (`https://www.youtube.com`)
  - `Mod+Shift+M`: YouTube Music (`https://music.youtube.com`)
  - `Mod+Shift+G`: Gmail (`https://mail.google.com`)
  - `Mod+Shift+D`: Discord (`https://discord.com/app`)
  - `Mod+Shift+Z`: Zed
  - `Mod+Shift+E`: Nautilus
  - Intentionally replace DMS actions currently occupying
    `Mod+Shift+N`, `Mod+Shift+R`, and `Mod+Shift+E`.
- [ ] Try `focus-window-or-workspace-down` and
  `focus-window-or-workspace-up` for `Mod+J/K`.
