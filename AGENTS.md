# Mistty

macOS terminal emulator built on libghostty with native session management.

Design tenets and architecture: `docs/DESIGN.md`
Rules and conventions: `.kiro/steering/mistty.md`, `.kiro/steering/swift.md`

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

Three targets: Mistty (app), MisttyCLI (CLI tool), MisttyShared (shared IPC types).

```
Mistty/
  App/              Entry point, content view, handlers, managers
  Models/           Session/Tab/Pane model classes, layout engine
  Views/            SwiftUI views by category
  Services/         IPC, persistence, fuzzy matching, zoxide
  Config/           TOML config parser
  Resources/        Info.plist, assets
MisttyShared/       IPC protocol, response models, constants
MisttyCLI/          CLI commands and IPC client
MisttyTests/        Unit tests (App/, Models/, Services/, Config/, Views/)
vendor/ghostty/     Ghostty git submodule
docs/               DESIGN.md, ROADMAP.md, plans/, research/, specs/
```

## Key Files

| File | Role |
|------|------|
| `Mistty/App/GhosttyApp.swift` | C callbacks bridging libghostty to Swift |
| `Mistty/App/ContentView+Handlers.swift` | Notification handlers for terminal events |
| `MisttyShared/MisttyServiceProtocol.swift` | IPC contract between app and CLI |
| `Mistty/App/MisttyTheme.swift` | Single source for all color tokens |

## Gotchas

- `vendor/ghostty/` is a git submodule. Do not modify it.
- libghostty requires Zig from the nix devshell (`just dev`). System Zig will not work.
- `MisttyCLI/XPCClient.swift` is misnamed. It is a Unix socket client, not XPC.
- Release builds depend on `just build-libghostty`, which needs `nix develop`.
