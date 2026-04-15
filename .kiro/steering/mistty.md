# Mistty

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

All colors go through MisttyTheme.swift tokens.
Do not use Color literals (Color.red, .blue) directly in views.
Do not use .opacity() on theme tokens. Create a new token instead.

## Adding IPC Methods

Three files must stay in sync:
1. MisttyShared/MisttyServiceProtocol.swift (protocol declaration)
2. Mistty/Services/IPCService.swift (implementation)
3. Mistty/Services/IPCListener.swift (dispatch case)

Add the CLI command in MisttyCLI/Commands/.
Stable noun+verb operations get IPC in the same commit as the GUI feature.

## Adding Action Callbacks

When libghostty adds a new action type:
1. Handle in GhosttyApp.swift actionCallback (C function, no captures)
2. Add a Notification.Name in the extension
3. Add .onReceive in ContentView.contentWithNotifications
4. Add handler method in ContentView+Handlers.swift
5. Add test in MisttyTests/App/ContentViewHandlerTests.swift

## Testing

Model classes: unit test directly (SessionStore, MisttySession, etc.).
Handlers: test via the ContentView handleX(notification) pattern.
NSEvent monitors: test the extracted handler methods, not the monitors.
Views: manual testing only.
Do not mock SessionStore. Create a real instance for tests.

## File Naming

Views: FooView.swift in Views/Category/
Models: MisttyFoo.swift in Models/
Services: FooService.swift in Services/
Extensions: Type+Category.swift (e.g., ContentView+Handlers.swift)
Managers: FooManager.swift in App/ (owns NSEvent monitor lifecycle)

## Framework Dependencies

Do not add Apple framework dependencies beyond AppKit, SwiftUI, and
UserNotifications without discussion.
