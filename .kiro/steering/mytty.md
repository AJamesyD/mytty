# Mytty

Read docs/DESIGN.md for design tenets and architecture constraints.
This file encodes those constraints as actionable rules.

## Architecture Rules

Do not add logic to the UI layer beyond view composition and event routing.
Do not access ghostty_surface_t outside TerminalSurfaceView and GhosttyApp.swift.
Do not parse raw escape sequences. libghostty handles all terminal protocol parsing.
Do not reverse the state flow. Direction is: libghostty -> C callbacks -> NotificationCenter -> handlers -> model updates -> SwiftUI.
Do not leak storage assumptions into views. Session/Tab/Pane are protocol-based; the backing store is swappable.
Do not modify vendor/ghostty/. Track upstream, don't fork.

## Model Classes

All model classes are @MainActor @Observable.
Do not use ObservableObject or @Published (legacy patterns).
Do not use Combine in model code.

## Colors and Theming

All colors go through MyttyTheme.swift tokens.
Do not use Color literals (Color.red, .blue) directly in views.
Do not use .opacity() on theme tokens. Create a new token instead.

## Adding IPC Methods

Three files must stay in sync:
1. MyttyShared/MyttyServiceProtocol.swift (protocol declaration, async throws)
2. Mytty/Services/IPCService.swift (implementation)
3. Mytty/Services/IPCListener.swift (dispatch case in dispatchJSONRPCMethod)

JSON-RPC method names use noun.verb format: session.create, tab.list, pane.focus.
Add the CLI command in MyttyCLI/Commands/.
Stable noun+verb operations get IPC in the same commit as the GUI feature.
For mutations, add a broker.publish call in IPCService for the corresponding event.

## Adding Action Callbacks

When libghostty adds a new action type:
1. Handle in GhosttyApp.swift actionCallback (C function, no captures)
2. Add a Notification.Name in the extension
3. Add .onReceive in ContentView.contentWithNotifications
4. Add handler method in ContentView+Handlers.swift
5. Add test in MyttyTests/App/ContentViewHandlerTests.swift

## Testing

Model classes: unit test directly (SessionStore, MyttySession, etc.).
Handlers: test via the ContentView handleX(notification) pattern.
NSEvent monitors: test the extracted handler methods, not the monitors.
Views: manual testing only.
Do not mock SessionStore. Create a real instance for tests.

## File Naming

Views: FooView.swift in Views/Category/
Models: MyttyFoo.swift in Models/
Services: FooService.swift in Services/
Extensions: Type+Category.swift (e.g., ContentView+Handlers.swift)
Managers: FooManager.swift in App/ (owns NSEvent monitor lifecycle)

## Framework Dependencies

Do not add Apple framework dependencies beyond AppKit, SwiftUI, and
UserNotifications without discussion.

## Configuration

Config file (`~/.config/mytty/config.toml`) is the single source of truth.
The Settings GUI (Cmd+,) is read-only. See ADR-006.

Config types live in `Mytty/Config/`:
- `MyttyConfig.swift`: TOML parser, `load()` entry point, `configFileURL` static
- `KeybindingStore.swift`: per-mode binding storage, merge/override/unbind/reset
- `TriggerParser.swift`: parses trigger strings (e.g., `cmd+shift+t`, `unconsumed:ctrl+h`)

Config flows from file to consumers via `MyttyConfig.load().keybindingStore`.
Each consumer calls `load()` independently (no shared singleton). Consumers:
- `MyttyApp.swift`: menu shortcuts via `trigger(for:in:.global)?.toKeyboardShortcut()`
- `PaneNavigationManager.swift`: navigation keys via reverse lookup + `unconsumed:` check
- `MyttyPane.swift`: passthrough process list via `isPassthroughProcess(processes:)`

Do not add a `save()` method to MyttyConfig. The config file is user-owned.
A future GUI editor requires format-preserving TOML round-trip (see TODO in SettingsView).

Keybinding actions use kebab-case: `new-tab`, `navigate-left`, `focus-tab-1`.
TOML config key for the process list: `passthrough-processes`.
