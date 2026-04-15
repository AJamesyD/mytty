# Swift Conventions

Project-specific Swift and SwiftUI patterns. For architecture rules and
file naming, see `.kiro/steering/mistty.md`.

## Concurrency

IPC service methods use `Task { @MainActor in }` to bridge from nonisolated context.
Do not use `DispatchQueue.main.async` in model code. Use `@MainActor` instead.
`DispatchQueue` is acceptable only in:
- GhosttyApp.swift C callbacks (bridging C to Swift)
- IPCListener.swift (socket I/O on a dedicated queue)
- Timer-based delays where `Task.sleep` is not appropriate

## View Decomposition

ContentView is the root. Extensions split by concern (e.g., `+Handlers`).
Overlays compose via `.overlay { }` chains on the content body.
Do not use separate windows or sheets for overlay UI.
Manager classes (e.g., `CopyModeManager`, `WindowModeManager`) own NSEvent
monitors and are held as `@State` on ContentView.

## Error Handling

Use guard-let with early return. Do not force-unwrap outside of tests.
IPC errors use the `MisttyIPC.error(.code, "message")` factory.
Do not throw raw `NSError` from IPC methods.

## Imports

Import only what the file needs.
Do not import `GhosttyKit` unless the file touches libghostty types directly.
Files that import `GhosttyKit`: GhosttyApp.swift, ContentView.swift,
ContentView+Handlers.swift, TerminalSurfaceView.swift, PaneView.swift,
MisttyApp.swift, CopyModeManager.swift, IPCService.swift.
Do not add new `GhosttyKit` imports without verifying the file needs
direct access to `ghostty_surface_t` or related C types.

## Notification Pattern

Post notifications with `NotificationCenter.default.post(name:object:userInfo:)`.
Receive in SwiftUI with `.onReceive(NotificationCenter.default.publisher(for:))`.
Do not use Combine publishers, delegate callbacks, or async streams as
alternatives to NotificationCenter for libghostty events.

## Property Wrappers

Use `@Observable` (Observation framework). Do not use `@ObservableObject`
or `@Published`. These are legacy patterns in this project.
Use `@State` for view-local state. Use `@Environment` to pass the store.
Do not use `@StateObject` or `@EnvironmentObject`.
