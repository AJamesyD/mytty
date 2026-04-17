# Mytty

*Mighty terminal. My TTY.* A macOS terminal emulator with built-in session management, powered by [libghostty](https://github.com/ghostty-org/ghostty).

<!-- TODO: screenshot or demo GIF -->

Mytty puts sessions, tabs, split panes, and a fuzzy session switcher inside a native macOS terminal. No tmux, no extra process, no second config file.

> [!NOTE]
> Mytty is under active development. Core features work, but expect rough edges and breaking changes.

## Features

- **Session manager** (`Cmd+J`): fuzzy-find sessions, recent directories ([zoxide](https://github.com/ajeetdsouza/zoxide)), and SSH hosts
- **Splits and tabs**: `Cmd+D` / `Cmd+T`, navigate with `Ctrl+h/j/k/l` (works across Neovim panes via [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim))
- **Keyboard-driven**: which-key overlay (`Ctrl+Space`) shows available shortcuts in context
- **Dropdown terminal**: system-wide hotkey summons a slide-down terminal
- **Sidebar**: persistent session tree with background activity indicators
- **CLI**: `mytty-cli` controls sessions, tabs, and panes over a JSON-RPC socket
- **Live config**: `~/.config/mytty/config.toml`, changes apply on save

## Quick Start

Requires macOS 14+, Xcode 16.3, [Nix](https://nixos.org/download/), and [just](https://github.com/casey/just).

```sh
git clone --recurse-submodules https://github.com/AJamesyD/mytty.git
cd mytty
just build-libghostty   # Nix provides Zig for the Ghostty build
just build && just run
```

For development setup, build commands, project structure, and macOS 26 notes, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Configuration

Mytty reads `~/.config/mytty/config.toml`. All fields are optional; defaults apply when omitted.

```toml
font_size = 14
font_family = "JetBrains Mono"

[sidebar]
position = "right"
mode = "auto-hide"

[keybindings]
toggle-sidebar = "cmd+b"
split-horizontal = "cmd+shift+d"

# Apps that receive all keys directly (bypasses Mytty keybindings)
passthrough-processes = ["nvim", "emacs", "htop"]
```

## CLI

```sh
mytty-cli session list              # List sessions (JSON when piped)
mytty-cli session create --name dev --directory ~/code
mytty-cli pane send-keys "npm test"
mytty-cli pane focus --direction left
```

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
