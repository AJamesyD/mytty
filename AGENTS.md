# Mytty

macOS terminal emulator built on libghostty with native session management.

Design tenets and architecture: `docs/DESIGN.md`
Rules and conventions: `.kiro/steering/mytty.md`, `.kiro/steering/swift.md`

## Build & Test

```
just build              # Debug build (swift build)
just build-release      # Release build (rebuilds libghostty first)
just test               # All tests (swift test)
just test-filter NAME   # Tests matching a filter
just fmt                # Format all code (Swift + Nix)
just lint               # SwiftLint
just check              # Format check + lint + test
just build-libghostty   # Rebuild libghostty (requires nix devshell)
just dev                # Enter nix devshell
just run                # Build, bundle, install, launch
just setup              # First-time: init git submodules
```

## Repo Structure

Three targets: Mytty (app), MyttyCLI (CLI tool), MyttyShared (shared IPC types).

```
Mytty/
  App/              Entry point, content view, handlers, managers
  Models/           Session/Tab/Pane model classes, layout engine
  Views/            SwiftUI views by category
  Services/         IPC, persistence, fuzzy matching, zoxide
  Config/           TOML config parser
  Resources/        Info.plist, assets
MyttyShared/       IPC protocol, response models, constants
MyttyCLI/          CLI commands and IPC client
MyttyTests/        Unit tests (App/, Models/, Services/, Config/, Views/)
vendor/ghostty/     Ghostty git submodule
docs/               DESIGN.md, ROADMAP.md, decisions/, research/, specs/
```

## Key Files

| File | Role |
|------|------|
| `Mytty/App/GhosttyApp.swift` | C callbacks bridging libghostty to Swift |
| `Mytty/App/ContentView.swift (Notifications & Handlers extension)` | Notification handlers for terminal events |
| `MyttyShared/MyttyServiceProtocol.swift` | IPC contract between app and CLI |
| `Mytty/App/MyttyTheme.swift` | Single source for all color tokens |

## Gotchas

- `vendor/ghostty/` is a git submodule. Do not modify it.
- libghostty requires Zig from the nix devshell (`just dev`). System Zig will not work.
- MyttyCLI uses a Unix domain socket for IPC, not XPC.
- Release builds depend on `just build-libghostty`, which needs `nix develop`.
