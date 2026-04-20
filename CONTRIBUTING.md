# Contributing to Mytty

## Prerequisites

- macOS 14 (Sonoma) or later
- Xcode 16+ (16.3 minimum for libghostty; see macOS 26 notes below for dual-Xcode)
- [Nix](https://nixos.org/download/) (provides zig, just, swiftlint, and other dev tools)

### macOS 26 (Tahoe) notes

Building on macOS 26 requires two Xcode versions:

- **Xcode 16.3** for the zig/libghostty build (the macOS 15 SDK has arm64 tbd stubs that zig needs; the macOS 26 SDK only has arm64e stubs)
- **Latest Xcode** (26.x) for the Swift build

Install both via [xcodes](https://github.com/XcodesOrg/xcodes) (included in the nix devshell):

```sh
xcodes install 16.3
xcodes install 26.4
```

The `just build-libghostty` recipe automatically selects Xcode 16.3 via `DEVELOPER_DIR`. Set your default Xcode to 26.x for Swift builds:

```sh
sudo xcode-select -s /Applications/Xcode-26.4.app/Contents/Developer
```

If the Metal Toolchain is not installed:

```sh
xcodebuild -downloadComponent MetalToolchain
```

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

| Command | Description |
|---|---|
| `just build` | Build debug |
| `just build-release` | Build release |
| `just run` | Build, bundle, install, launch |
| `just test` | Run tests |
| `just clean` | Clean build artifacts |
| `just build-libghostty` | Rebuild libghostty from vendored Ghostty |
| `just dev` | Enter nix dev shell |
| `just fmt` | Format all code |
| `just fmt-all` | Format all code (Swift + Nix) |
| `just lint` | SwiftLint |
| `just lint-fix` | Lint and auto-fix |
| `just lint-strict` | Lint (warnings are errors) |
| `just check` | Format + lint + test |
| `just ci` | Full CI (Swift format + Nix format + typos + strict lint + build + test) |
| `just bundle` | Create Mytty.app bundle |
| `just install` | Build, bundle, install to /Applications |
| `just install-cli` | Build and install `mytty-cli` |
| `just test-filter PATTERN` | Run tests matching a filter |
| `just run-dev` | Build and run (optimized debug) |
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

Install with `just install-cli`.

## Troubleshooting

**`just build-libghostty` fails with Zig errors**

Make sure you're in the Nix dev shell (`just dev` or `nix develop`). System Zig will not work; the build requires the exact Zig version pinned in `flake.nix`.

**Build fails on macOS 26 (Tahoe)**

You need two Xcode versions. See the macOS 26 notes above. Make sure `just build-libghostty` uses Xcode 16.3 (it selects this automatically via `DEVELOPER_DIR`).

**`mytty-cli` can't connect**

The CLI communicates over a Unix socket. Make sure Mytty.app is running. The socket path is printed at launch; check Console.app or stderr if the default path doesn't work.

**Tests fail with "no such module GhosttyKit"**

Run `just build-libghostty` first. The test target depends on the compiled libghostty framework.
