# Mytty

A macOS terminal emulator built on [libghostty](https://github.com/ghostty-org/ghostty) with native session management. Mytty brings tmux-style workflows directly into the terminal: sessions, tabs, split panes, and a fuzzy session switcher, all without a separate multiplexer.

## Features

- **Session manager** (`Cmd+J`): fuzzy-find and switch between sessions, recent directories (via zoxide), and SSH hosts
- **Tabs and split panes**: standard terminal multiplexing built in
- **Sidebar**: persistent session tree, collapsible with `Cmd+S`
- **Keyboard-driven**: every function accessible via keyboard shortcut
- **Configurable**: XDG-compliant config at `~/.config/mytty/config.toml`
- **Native macOS**: SwiftUI interface, system integration

## CLI Control

Mytty includes a CLI tool for scripting and automation:

```bash
# Install
just install-cli

# Sessions
mytty-cli session list
mytty-cli session create --name "project" --directory ~/code

# Tabs
mytty-cli tab create --session 1 --name "editor"
mytty-cli tab list --session 1

# Panes
mytty-cli pane active
mytty-cli pane create --tab 1 --direction horizontal
mytty-cli pane send-keys "echo hello"
mytty-cli pane run-command "npm test"

# JSON output (auto-detected when piped, or force with --json)
mytty-cli session list | jq .
mytty-cli session list --json
```

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 16.3 (for building libghostty via Zig)
- Xcode 26+ (for Swift 6.3 build, if on macOS 26)
- [Nix](https://nixos.org/download/) (provides Zig 0.15.2 for the Ghostty build)
- [just](https://github.com/casey/just) (command runner, optional but recommended)

### macOS 26 (Tahoe) notes

Building on macOS 26 requires two Xcode versions:

- **Xcode 16.3** for the zig/libghostty build (the macOS 15 SDK has arm64 tbd stubs that zig needs; the macOS 26 SDK only has arm64e stubs)
- **Xcode 26+** for the Swift build (Swift 6.3 support)

Install both via [xcodes](https://github.com/XcodesOrg/xcodes) (included in the nix devshell):

```sh
xcodes install 16.3
xcodes install 26.0
```

The `just build-libghostty` recipe automatically selects Xcode 16.3 via `DEVELOPER_DIR`. Set your default Xcode to 26.x for Swift builds:

```sh
sudo xcode-select -s /Applications/Xcode-26.0.app/Contents/Developer
```

If the Metal Toolchain is not installed:

```sh
xcodebuild -downloadComponent MetalToolchain
```

## Setup

```sh
# Clone with submodules
git clone --recurse-submodules mytty.git
cd mytty

# Or if already cloned:
just setup

# Build libghostty (requires nix for Zig 0.15.2)
just build-libghostty

# Build the app
just build

# Run
just run
```

## Development

| Command | Description |
|---|---|
| `just build` | Build debug |
| `just build-release` | Build release |
| `just run` | Build and run |
| `just test` | Run tests |
| `just clean` | Clean build artifacts |
| `just build-libghostty` | Rebuild libghostty from vendored Ghostty |
| `just dev` | Enter nix dev shell |
| `just fmt` | Format Swift code |
| `just lint` | SwiftLint |
| `just check` | Format + lint + test |
| `just info` | Show project info |

### Nix dev shell

The project uses a Nix flake to provide Zig 0.15.2 (required by Ghostty's build system). Swift is expected from the system Xcode installation.

```sh
# Enter the shell manually
nix develop

# Or use direnv (with .envrc already configured)
direnv allow
```

### Project structure

```
mytty/
  Mytty/              # App source
    App/               # Entry point, content view, handlers, managers
    Config/            # TOML config parser, keybinding store
    Models/            # Session/Tab/Pane model classes, layout engine
    Views/             # SwiftUI views by category
    Services/          # IPC, persistence, fuzzy matching
    Resources/         # Info.plist, assets
  MyttyShared/        # IPC protocol, response models, constants
  MyttyCLI/           # CLI commands and IPC client
  MyttyTests/         # Unit tests
  vendor/ghostty/      # Ghostty git submodule
  docs/                # Design, specs, decisions, research
  Package.swift        # Swift package manifest
  flake.nix            # Nix dev environment
  justfile             # Task runner
```

## Architecture

Mytty uses a three-layer architecture:

- **UI Layer** (SwiftUI): sidebar, session manager, tab bar, terminal views
- **Session Layer** (Swift protocols): `SessionStore` > `MyttySession` > `MyttyTab` > `MyttyPane`, designed for future migration from in-memory to a background daemon
- **Terminal Layer** (libghostty): `NSViewRepresentable` wrapping a `ghostty_surface_t` for terminal rendering

See [docs/DESIGN.md](docs/DESIGN.md) for the full design document.

## Acknowledgments

Mytty is built on [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto, which provides the terminal rendering engine (libghostty).

This project was originally named "Mistty" and shares early design DNA with [milch/mistty](https://github.com/milch/mistty), another libghostty-based terminal. The rename to Mytty was made to avoid confusion between the two projects.

Other projects that informed Mytty's design:

- [Cmux](https://github.com/manaflow-ai/cmux) for patterns around libghostty integration and session architecture
- [tmux](https://github.com/tmux/tmux) for the session/window/pane workflow model
- [smart-splits.nvim](https://github.com/mrjones2014/smart-splits.nvim) for the bidirectional Neovim pane navigation pattern
- [zoxide](https://github.com/ajeetdsouza/zoxide) for recent directory tracking in the session manager

## License

TBD
