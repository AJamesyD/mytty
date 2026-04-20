# Contributing to Mytty

## Prerequisites

- Apple Silicon Mac (arm64 only)
- macOS 14 (Sonoma) or later
- Xcode (latest version for your macOS; on macOS 26, also keep any Xcode 16.x installed for the libghostty build)
- [Nix](https://nixos.org/download/) (provides zig, just, swiftlint, and other dev tools)

## Setup

```sh
git clone --recurse-submodules https://github.com/AJamesyD/mytty.git
cd mytty
just build-libghostty   # Requires nix (provides Zig 0.15.2)
just build && just run
```

If you already cloned without submodules: `just setup` initializes them.

### Nix dev shell

The project uses a Nix flake to provide Zig 0.15.2 (required by Ghostty's build system). Swift comes from the system Xcode installation.

```sh
nix develop

# Or use direnv (with .envrc already configured)
direnv allow
```

## Development Commands

**For daily use:** `just install-all` (release build, one command)  
**For development:** `just run` (debug build, rebuilds each invocation)

| Command | Description |
|---|---|
| `just build` | Build debug |
| `just build-release` | Build release |
| `just run` | Build, bundle, install, launch |
| `just test` | Run tests |
| `just clean` | Clean build artifacts |
| `just build-libghostty` | Rebuild libghostty from vendored Ghostty |
| `just dev` | Enter nix dev shell |
| `just fmt` | Format all code (Swift + Nix + Shell) |
| `just lint` | Lint all code (strict: warnings are errors) |
| `just lint-fix` | Lint and auto-fix |
| `just check` | Format + lint + test |
| `just ci` | Full CI pipeline (format + lint + build + verify + test) |
| `just verify-cli-ref` | Check CLI reference is up to date |
| `just bundle` | Create Mytty.app bundle |
| `just install` | Build, bundle, install to /Applications |
| `just install-cli` | Build and install `mytty-cli` |
| `just install-all` | Install release app + CLI for daily use |
| `just test-filter PATTERN` | Run tests matching a filter |
| `just build-cli` | Build the CLI tool |

## Project Structure

```
Mytty/                 # App source
  App/                  # Entry point, content view, handlers, managers
  Config/               # TOML config parser, keybinding store
  Models/               # Session/Tab/Pane model classes, layout engine
  Views/                # SwiftUI views by category
  Services/             # IPC, persistence, fuzzy matching
  Resources/            # Info.plist, assets
MyttyShared/           # IPC protocol, response models, constants
MyttyCLI/              # CLI commands and IPC client
MyttyTests/            # Unit tests
vendor/ghostty/         # Ghostty git submodule (do not modify)
docs/                   # Design, specs, decisions, research
Package.swift           # Swift package manifest
flake.nix               # Nix dev environment
justfile                # Task runner
```

## Guidelines

1. Run `just ci` before submitting changes
2. Read [docs/DESIGN.md](docs/DESIGN.md) for architecture constraints and design tenets
3. Features get a written spec before implementation (see `docs/specs/`)

## CLI Reference

```sh
# Sessions
mytty-cli session list
mytty-cli session get --id 1
mytty-cli session create --name "project" --directory ~/code
mytty-cli session close --id 1

# Tabs
mytty-cli tab create --session 1 --name "editor"
mytty-cli tab list --session 1
mytty-cli tab get --id 1
mytty-cli tab rename --id 1 --name "editor"
mytty-cli tab move 1 0

# Panes
mytty-cli pane active
mytty-cli pane create --tab 1 --direction horizontal
mytty-cli pane focus --direction left
mytty-cli pane send-keys "echo hello"
mytty-cli pane run-command "npm test"
mytty-cli pane list --tab 1
mytty-cli pane close --id 1
mytty-cli pane resize --direction right --amount 10
mytty-cli pane get-text --id 1
mytty-cli pane at-edge --direction left

# Popups
mytty-cli popup open --name scratch
mytty-cli popup close --name scratch
mytty-cli popup toggle --name scratch
mytty-cli popup list

# Windows
mytty-cli window list
mytty-cli window get 1
mytty-cli window close 1
mytty-cli window focus 1

# JSON output (auto-detected when piped, or force with --json)
mytty-cli session list | jq .
mytty-cli session list --json
```

Install with `just install-cli`. Requires the app to be installed first (`just install-release`). Symlinks into `~/.local/bin/`.

## Troubleshooting

**`just build-libghostty` fails with Zig errors**

Make sure you're in the Nix dev shell (`just dev` or `nix develop`). System Zig will not work; the build requires the exact Zig version pinned in `flake.nix`.

**`just build-libghostty` fails with `DarwinSdkNotFound` or undefined symbols**

The build needs an Xcode 16.x SDK (the macOS 26 SDK uses arm64e stubs that Zig can't link). The recipe auto-discovers Xcode 16.x in /Applications. If you only have Xcode 26.x installed, install any Xcode 16.x version alongside it.

**`mytty-cli` can't connect**

The CLI communicates over a Unix socket. Make sure Mytty.app is running. The socket path is printed at launch; check Console.app or stderr if the default path doesn't work.

**Tests fail with "no such module GhosttyKit"**

Run `just build-libghostty` first. The test target depends on the compiled libghostty framework.
