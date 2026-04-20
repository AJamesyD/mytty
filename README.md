# Mytty

[![CI](https://github.com/AJamesyD/mytty/actions/workflows/ci.yml/badge.svg)](https://github.com/AJamesyD/mytty/actions/workflows/ci.yml)

*Mighty terminal. My TTY.* A macOS terminal emulator with built-in session management, powered by [libghostty](https://github.com/ghostty-org/ghostty).

<!-- TODO: screenshot or demo GIF -->

Mytty puts sessions, tabs, split panes, and a fuzzy session switcher inside a native macOS terminal. No tmux, no extra process.

> [!NOTE]
> Mytty is under active development. Core features work, but expect rough edges and breaking changes.

## Features

- **Session manager**: fuzzy-find sessions, recent directories ([zoxide](https://github.com/ajeetdsouza/zoxide)), and SSH hosts
- **Splits and tabs**: horizontal and vertical splits with tabbed sessions
- **Pane navigation**: move between splits with configurable keys
- **Which-key overlay**: shows available shortcuts in context, so you don't have to memorize them
- **Dropdown terminal**: a system-wide hotkey summons a slide-down terminal
- **Sidebar**: persistent session tree with background activity indicators
- **CLI**: `mytty-cli` controls sessions, tabs, and panes over a JSON-RPC socket
- **Copy mode**: vi-style text selection and yank (Cmd+Shift+C to enter, y to yank, Esc to exit)
- **Window mode**: swap, zoom, break-to-tab, join, rotate panes, and preset layouts (Ctrl+W to enter)
- **Key sequences**: leader key support with configurable timeout (e.g., `ctrl+a>h` syntax in config)
- **Popup windows**: named floating terminal windows, controllable via CLI
- **Configurable**: keybindings, sidebar position, and passthrough processes are set in `~/.config/mytty/config.toml`. Changes apply on save.

## Quick Start

Requires macOS 14+, Xcode 16+, and [Nix](https://nixos.org/download/).
Nix provides the dev toolchain (just, zig, swiftlint). On macOS 26, see [CONTRIBUTING.md](CONTRIBUTING.md) for the dual-Xcode setup.

```sh
git clone --recurse-submodules https://github.com/AJamesyD/mytty.git
cd mytty
direnv allow            # or: nix develop
just build-libghostty   # Nix provides Zig for the Ghostty build
just build && just run
```

For development setup, build commands, project structure, and macOS 26 notes, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Configuration

Mytty reads two kinds of config:

- **`~/.config/mytty/config.toml`** controls Mytty's chrome: sidebar, keybindings, tab bar, passthrough processes. All fields are optional; defaults apply when omitted. Reloads live on save.
- **Ghostty config** controls terminal rendering: fonts, colors, themes, cursor, shell integration.
  - `~/.config/ghostty/config` is loaded as a base. If you already use [Ghostty](https://ghostty.org), your settings carry over automatically.
  - `~/.config/mytty/ghostty.conf` (optional) overrides the base. Use this for Mytty-specific tweaks. See [Ghostty docs](https://ghostty.org/docs/config) for all options.

Ghostty config files reload automatically when saved.

```toml
# ~/.config/mytty/config.toml

[sidebar]
position = "right"
mode = "auto-hide"

[keybindings]
toggle-sidebar = "cmd+b"
split-horizontal = "cmd+shift+d"

# Apps that receive all keys directly (bypasses Mytty keybindings)
passthrough-processes = ["nvim", "emacs", "htop"]
```

```ini
# ~/.config/mytty/ghostty.conf (optional, overrides ~/.config/ghostty/config)
# See https://ghostty.org/docs/config for all options.

font-family = BlexMono Nerd Font
font-size = 16
font-thicken = true
```

## Keybindings

| Action | Default | Mode |
|--------|---------|------|
| Toggle sidebar | `Cmd+\` | Global |
| Toggle tab bar | `Cmd+Shift+T` | Global |
| New tab | `Cmd+T` | Global |
| Split horizontal | `Cmd+D` | Global |
| Split vertical | `Cmd+Shift+D` | Global |
| Close pane | `Cmd+W` | Global |
| Close tab | `Cmd+Shift+W` | Global |
| Navigate left/down/up/right | `Ctrl+H/J/K/L` | Global |
| Next/previous tab | `Cmd+Shift+]/[` | Global |
| Focus tab 1-9 | `Cmd+1-9` | Global |
| Next/previous session | `Cmd+Alt+Down/Up` | Global |
| Next/previous prompt | `Cmd+Shift+Down/Up` | Global |
| Rename tab | `Cmd+Shift+R` | Global |
| Enter copy mode | `Cmd+Shift+C` | Global |
| Enter window mode | `Ctrl+W` | Global |
| Show which-key | `Ctrl+Space` | Global |
| Dropdown terminal | `` Ctrl+` `` | System-wide |

All keybindings except the dropdown hotkey can be remapped in `~/.config/mytty/config.toml`. Press Ctrl+Space to open the which-key overlay and discover shortcuts interactively.

## CLI

```sh
mytty-cli session list              # List sessions (JSON when piped)
mytty-cli session create --name dev --directory ~/code
mytty-cli tab create --session 1
mytty-cli pane focus --direction left
mytty-cli pane send-keys "npm test"
mytty-cli popup open --name scratch  # Open a named popup window
mytty-cli popup toggle --name scratch
mytty-cli window list                # List open windows
mytty-cli window focus --id 1
```

Window mode actions (swap, zoom, rotate, layouts) are keyboard-only via Ctrl+W. See the keybindings table above.

Install with `just install-cli`. See [CONTRIBUTING.md](CONTRIBUTING.md) for the full command reference.

## Design

See [docs/DESIGN.md](docs/DESIGN.md) for architecture, tenets, and constraints.

## Acknowledgments

Mytty began as a fork of [mistty](https://github.com/milch/mistty) by Manu Wallner. Built on [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto (terminal rendering engine).

Inspired by [tmux](https://github.com/tmux/tmux) (session model), [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) (Neovim pane navigation), and [zoxide](https://github.com/ajeetdsouza/zoxide) (directory tracking).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT License. See [LICENSE](LICENSE).
