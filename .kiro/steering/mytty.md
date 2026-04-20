# Mytty

Read docs/DESIGN.md for design tenets and architecture constraints.
This file encodes those constraints as actionable rules.

## Architecture Rules

Do not add logic to the UI layer beyond view composition and event routing.
Do not access ghostty_surface_t outside TerminalSurfaceView, GhosttyApp.swift, CopyModeManager.swift, KeySequenceManager.swift, IPCService.swift, PaneView.swift, and PaneNavigationManager.swift.
Do not parse raw escape sequences. libghostty handles all terminal protocol parsing.
Do not reverse the state flow. Direction is: libghostty -> C callbacks -> NotificationCenter -> handlers -> model updates -> SwiftUI.
Do not leak storage assumptions into views. Session/Tab/Pane are concrete @Observable classes; the IPC protocol provides the abstraction boundary.
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
4. Add handler method in ContentView.swift (Notifications & Handlers extension)
5. Add test in MyttyTests/App/ContentViewHandlerTests.swift

## Testing

Model classes: unit test directly (SessionStore, MyttySession, etc.).
Handlers: test via the ContentView handleX(notification) pattern.
NSEvent monitors: test the extracted handler methods, not the monitors.
Views: manual testing only.
Do not mock SessionStore. Create a real instance for tests.

## File Naming

Views: FooView.swift in Views/Category/
Feature modules: Views/Category/ may colocate a ViewModel (FooViewModel.swift) with its view when the ViewModel exclusively serves that view.
Models: MyttyFoo.swift in Models/
Services: FooService.swift in Services/
Extensions: Type+Category.swift (e.g., NSEvent+GhosttyKey.swift)
Managers: FooManager.swift in App/ (modal key handling and state)

## Framework Dependencies

Do not add Apple framework dependencies beyond AppKit, SwiftUI,
UserNotifications, and Carbon (transitive via GhosttyKit) without discussion.

## Configuration

Config file (`~/.config/mytty/config.toml`) is the single source of truth for Mytty chrome.
The Settings GUI (Cmd+,) is read-only. See ADR-006.

Terminal rendering config (fonts, colors, themes, cursor) uses Ghostty's format:
- `~/.config/ghostty/config` (base, shared with Ghostty.app)
- `~/.config/mytty/ghostty.conf` (optional overrides)
Both are loaded at launch and hot-reloaded on save via GhosttyConfigWatcher.

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

## Key Dispatch

Key events flow through a two-layer system (ADR-008):
1. TerminalSurfaceView.keyDown checks modal state (copy mode, window mode, key sequence)
2. If no modal consumes the key, it falls through to libghostty via ghostty_surface_key

Do not add key handling outside TerminalSurfaceView.keyDown.
Do not re-introduce a centralized key dispatcher. The previous ModalKeyDispatcher
was deleted in Phase 2 of ADR-008.

## Dropdown Terminal

DropdownController.swift manages the slide-down terminal panel.
GlobalHotkeyMonitor.swift registers a system-wide CGEvent tap for the hotkey.
DropdownPanel.swift is an NSPanel subclass for the floating terminal.

The dropdown hotkey is currently hardcoded (Ctrl+backtick, keycode 50).
Configurable hotkeys require Phase 4f-2 (global hotkey registration).

DropdownController is held as @State on MyttyApp, alongside GlobalHotkeyMonitor.

## Copy Mode

CopyModeManager.swift provides key handling methods called from TerminalSurfaceView.keyDown (see ADR-008).
CopyModeState (in Models/) tracks selection, cursor, and visual mode.
Copy mode keybindings are in the `.copyMode` binding mode in KeybindingStore.

Entry: `copy-mode` action (default Cmd+Shift+C).
Exit: Esc or yank (y).
Copy mode reads terminal text via ghostty_surface_read_text.

## Window Mode

WindowModeManager.swift provides key handling methods called from TerminalSurfaceView.keyDown (see ADR-008).
Window mode keybindings are in the `.windowMode` binding mode in KeybindingStore.

Entry: `window-mode` action (default Ctrl+W).
Exit: Esc or any window action.
Actions: swap, zoom, break-to-tab, join-pick, rotate, resize, preset layouts (1-5).

## Key Sequences

KeySequenceManager.swift handles multi-key sequences (e.g., `ctrl+a>h`).
Sequences use a state machine with a configurable timeout (default 1s).
SequenceIndicatorView shows pending leader keys with which-key integration after 500ms.
Sequence triggers use `>` as the separator in config: `ctrl+a>h`.

## Bridge Code Patterns

When adding or modifying NSTextInputClient methods, verify against the
Ghostty reference (vendor/ghostty/macos/Sources/Ghostty/SurfaceView/SurfaceView_AppKit.swift).
Every guard in Ghostty's version must have an equivalent in Mytty's.
Document intentional divergences with a comment citing the reason.

Divergence: Mytty uses NSTextInputContext.current (AppKit) instead of
Ghostty's Carbon-based KeyboardLayout helper. Avoids adding Carbon as
a framework dependency. Functionally equivalent.
