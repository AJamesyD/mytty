# Mytty

[![CI](https://github.com/AJamesyD/mytty/actions/workflows/ci.yml/badge.svg)](https://github.com/AJamesyD/mytty/actions/workflows/ci.yml)

*Mighty terminal. My TTY.* A macOS terminal emulator with built-in session management, powered by [libghostty](https://github.com/ghostty-org/ghostty).

<!-- TODO: screenshot or demo GIF -->

## Why

I wanted tmux-style session management inside the terminal itself: splits, tabs, and background awareness without a separate process or config language.

You might like mytty if you:
- Use tmux mostly for splits and sessions, and wish it was native macOS
- Want your terminal to be scriptable (CLI + Unix socket) without learning tmux's command syntax
- Like modal keybindings (vim-style copy mode, window mode, leader keys)
- Want your shell to know which pane it's in, so scripts can target specific sessions
- Don't want to memorize shortcuts; prefer the app to teach you as you go

## Status

Alpha. Core features work; expect rough edges and breaking changes. Maintained on my own schedule.

Mytty started as a fork of [mistty](https://github.com/milch/mistty) by Manu Wallner, and has since diverged significantly in architecture and features. Most code is AI-generated with human direction. I use it as my daily terminal.

If you want an actively maintained libghostty terminal, [mistty](https://github.com/milch/mistty) is the better choice. Mytty is a personal project shared with friends and colleagues.

## Highlights

**Session management without tmux**

Splits, tabs, sessions, and a fuzzy switcher inside the terminal. No extra process, no config language.

**Discoverable by design**

You don't need to memorize keybindings:
- **Which-key overlay** (Ctrl+Space): shows available shortcuts in context
- **Hints mode**: label and jump to URLs, paths, or panes (like vimium)
- **Key sequences**: leader keys with visual feedback and configurable timeout

**Modal editing for terminal chrome**

- **Copy mode** (Cmd+Shift+C): vi-style text selection and yank
- **Window mode** (Ctrl+W): swap, zoom, rotate, resize, and layout panes

**Scriptable**

- **CLI**: `mytty-cli` drives sessions, tabs, and panes over a Unix socket
- **Session sources**: pluggable commands feed the fuzzy picker (zoxide dirs, SSH hosts, custom scripts)
- **Popup windows**: named floating terminals, scriptable via CLI
- **Ambient identity**: shells know their session/tab/pane via environment variables

**Always accessible**

- **Dropdown terminal**: system-wide hotkey summons a slide-down panel
- **Passthrough**: apps like nvim and emacs receive raw keys with no binding conflicts

## Quick Start

Requires: Apple Silicon Mac, macOS 15+, Xcode 16+, [Nix](https://nixos.org/download/).

```sh
git clone --recurse-submodules https://github.com/AJamesyD/mytty.git
cd mytty && nix develop
just build-libghostty && just install-all
```

Installs to `/Applications/Mytty.app` and symlinks the CLI to `~/.local/bin/mytty-cli`.

### Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for build commands, project structure, and architecture.

## Configuration

- **`~/.config/mytty/config.toml`**: keybindings, sidebar, passthrough processes. Reloads on save.
- **`~/.config/mytty/ghostty.conf`** (optional): terminal rendering overrides. Falls back to `~/.config/ghostty/config`.

```toml
# ~/.config/mytty/config.toml
[keybindings]
split-horizontal = "cmd+shift+d"
toggle-sidebar = "cmd+b"

passthrough-processes = ["nvim", "emacs", "htop"]
```

```ini
# ~/.config/mytty/ghostty.conf
font-family = BlexMono Nerd Font
font-size = 16
```

## Keybindings

| Action | Default |
|--------|---------|
| Split horizontal | `Cmd+D` |
| Close pane | `Cmd+W` |
| Navigate panes | `Ctrl+H/J/K/L` |
| Copy mode | `Cmd+Shift+C` |
| Window mode | `Ctrl+W` |

All defaults are overridable in [`config.toml`](#configuration). Press **Ctrl+Space** to discover shortcuts via the which-key overlay.

<details>
<summary>All keybindings</summary>

| Action | Default |
|--------|---------|
| Sidebar / Tab bar | `Cmd+\` / `Cmd+Shift+T` |
| New tab | `Cmd+T` |
| Split | `Cmd+D` (horiz) / `Cmd+Shift+D` (vert) |
| Close | `Cmd+W` (pane) / `Cmd+Shift+W` (tab) |
| Navigate panes | `Ctrl+H/J/K/L` |
| Switch tab | `Cmd+Shift+]` / `[` or `Cmd+1-9` |
| Switch session | `Cmd+Alt+Down/Up` |
| Rename tab | `Cmd+Shift+R` |
| Copy mode / Window mode | `Cmd+Shift+C` / `Ctrl+W` |
| Which-key | `Ctrl+Space` |
| Dropdown terminal | `` Ctrl+` `` (system-wide) |

Remappable in `config.toml` (except the dropdown hotkey).

</details>

## CLI

```sh
mytty-cli session list
mytty-cli tab create --session 1
mytty-cli pane focus --direction left
mytty-cli pane send-keys "npm test"
```

Noun.verb model over a Unix socket. Run `mytty-cli --help` or see [docs/CLI-REFERENCE.md](docs/CLI-REFERENCE.md) for the full command list.

## Acknowledgments

Mytty began as a fork of [mistty](https://github.com/milch/mistty) by Manu Wallner. The original project structure, libghostty integration, and early session model came from his work. Built on [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto. Inspired by [tmux](https://github.com/tmux/tmux), [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim), and [zoxide](https://github.com/ajeetdsouza/zoxide).

## License

[MIT](LICENSE)
