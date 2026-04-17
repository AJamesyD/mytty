# SwiftUI UI Primitives for a macOS Terminal Emulator (Mytty)

Target: macOS 14+ (Sonoma), built on libghostty.

---

## 1. Navigation and Layout Primitives

### NavigationSplitView (sidebar + detail)

Two-column and three-column variants. The two-column form (`sidebar` + `detail`) is the
workhorse for macOS apps. The three-column form adds a `content` column between sidebar
and detail.

- Column visibility is controlled via `NavigationSplitViewVisibility` binding (`.all`,
  `.doubleColumn`, `.detailOnly`).
- Column widths are set with `navigationSplitViewColumnWidth(min:ideal:max:)` on each
  column's content. The detail column's max-width constraint is buggy (does not cap
  properly as of macOS 14).
- The sidebar gets a toggle button automatically via `SidebarCommands()`.
- On macOS, columns are always shown side-by-side (no push navigation).

**Terminal relevance:** A session list sidebar + terminal detail pane is a natural fit.
For Mytty, the sidebar could list sessions/workspaces while the detail hosts the
terminal split tree.

### TabView

macOS TabView renders as a segmented control or tab bar depending on `.tabViewStyle()`.
Available styles: `.automatic` (segmented on macOS), and the newer `.sidebarAdaptable`
(macOS 14+, renders tabs in the sidebar).

Limitations on macOS:
- No native document-style tab bar (the kind Terminal.app and Safari use). That tab bar
  comes from `NSWindow.tabbingMode` in AppKit, not from SwiftUI's TabView.
- Customization is limited: no icons in the default style, no close buttons, no
  reordering.
- For a terminal app, the native window tab bar (AppKit) or a custom tab bar is the
  better choice.

**Terminal relevance:** SwiftUI's TabView is not suitable for terminal tabs. Use
`NSWindow` tabbing (`.tabbingMode = .preferred`) for native macOS document tabs, or a
custom tab bar component like Bonsplit.

### HSplitView / VSplitView

SwiftUI provides `HSplitView` and `VSplitView` for resizable split panes. These are
thin wrappers around `NSSplitView`.

Limitations:
- No API for min/max thickness per child, collapse behavior, or programmatic divider
  position. These are all available on `NSSplitViewController` but not exposed to
  SwiftUI.
- The divider cannot be styled.
- Nesting works (HSplitView inside VSplitView) for grid-like layouts.

Workarounds:
- Use `NSViewControllerRepresentable` wrapping `NSSplitViewController` for full control.
- Third-party: `stevengharris/SplitView` (custom SwiftUI splitter) or Bonsplit (tab bar
  + split pane library with tree-based layout model).

**Terminal relevance:** Split panes are the core multiplexing primitive. HSplitView/
VSplitView work for basic cases but lack the control needed for a terminal multiplexer
(min sizes, collapse, programmatic resize). A custom split tree (like Ghostty's
`Features/Splits/`) or Bonsplit's tree model is the practical path.

### Inspector (macOS 14+)

The `.inspector(isPresented:content:)` modifier adds a trailing sidebar. On macOS it
renders as a resizable column; on iOS it falls back to a sheet.

- Width is set via `.inspectorColumnWidth(min:ideal:max:)`.
- Can be toggled with `InspectorCommands()` (keyboard shortcut Cmd+Ctrl+I).
- Attaches to the detail column of a NavigationSplitView, or to any view.
- Toolbar items placed inside the inspector get their own toolbar area.

**Terminal relevance:** Useful for a session inspector (process info, environment
variables, scrollback search) that slides in from the right without disrupting the
terminal layout.

### WindowGroup, Window, and Multi-Window

Scene types available:
- `WindowGroup`: multi-instance windows. Each Cmd+N creates a new instance. Can be
  parameterized with a value type (`WindowGroup("Title", for: SomeID.self)`).
- `Window`: single-instance, unique window. Good for utility windows (activity monitor,
  connection manager).
- `Settings`: the standard Preferences window (Cmd+,).
- `MenuBarExtra`: persistent menu bar item.

Key APIs:
- `@Environment(\.openWindow)` / `@Environment(\.dismissWindow)` (macOS 14+) for
  programmatic window management.
- `.defaultPosition(.topLeading)`, `.defaultSize(width:height:)` for initial placement.
- `.commandsRemoved()` to hide a scene's default File menu item.
- `.keyboardShortcut()` at the scene level to customize the shortcut for opening a
  window.
- `@SceneStorage` for per-window persistent state (works across app restarts).

State sharing across windows: use a shared `@Observable` model injected via
`.environment()` at the App level, or a singleton. `@SceneStorage` is per-window only.

**Terminal relevance:** `WindowGroup` for main terminal windows (each with its own split
tree). `Window` for a single connection manager or session browser. `Settings` for
preferences. `MenuBarExtra` for quick-terminal access.

### Toolbar

- `.toolbar { }` with `ToolbarItem(placement:)` for positioning.
- Placements: `.automatic`, `.primaryAction`, `.navigation`, `.principal`,
  `.secondaryAction`, `.status`.
- `.toolbar(removing: .sidebarToggle)` to remove default items.
- `.toolbarBackground(.visible, for: .windowToolbar)` for styling.
- Toolbar items can be customizable by the user with `.toolbarRole(.editor)`.

### Composition: Can These All Coexist?

Yes, with caveats. A single window can contain:

```
WindowGroup {
    NavigationSplitView {
        // sidebar (session list)
    } detail: {
        HSplitView {
            // terminal pane 1
            VSplitView {
                // terminal pane 2
                // terminal pane 3
            }
        }
        .inspector(isPresented: $showInspector) {
            // session inspector
        }
        .toolbar { ... }
    }
}
```

The practical pattern (confirmed by msena.com's three-column article): use a two-column
NavigationSplitView with HSplitView nested in the detail for the canvas + inspector
pattern, since NavigationSplitView's three-column mode has bugs with detail column
width constraints.

---

## 2. Overlay and Modal Patterns

### Sheet, Popover, Alert

- `.sheet(isPresented:content:)`: modal sheet. On macOS, appears as a document-modal
  sheet attached to the window.
- `.popover(isPresented:attachmentAnchor:content:)`: small floating popover anchored to
  a view.
- `.alert(title:isPresented:actions:message:)`: standard alert dialog.
- `.confirmationDialog()`: action sheet equivalent.

### .overlay() for Custom Overlays

`.overlay { }` places content on top of the view. Useful for HUD-style overlays,
toast notifications, or a command palette rendered inline.

### .fullScreenCover() on macOS

Not directly available on macOS. The macOS equivalent is entering fullscreen mode via
`NSWindow`. For a modal that covers the entire window, use a ZStack with a conditional
overlay, or present a sheet.

### Floating Panels (NSPanel)

For Spotlight/Alfred-style floating UI, subclass `NSPanel`:
- Set `.nonactivatingPanel` style mask so the panel doesn't steal activation from the
  main app.
- Set `.isFloatingPanel = true` and `.level = .floating`.
- Override `canBecomeKey` and `canBecomeMain` to allow text input.
- Host SwiftUI content via `NSHostingView`.

This is the standard pattern for command palettes, quick terminals, and HUD panels.
Ghostty uses this approach for its QuickTerminal feature.

### Command Palette Pattern

No built-in SwiftUI command palette. Production approaches:

1. **NSPanel + SwiftUI content**: Create a floating panel with a search field and
   filtered list. Toggle with a global hotkey. This is what Ghostty does
   (`Features/Command Palette/`).
2. **Overlay approach**: Render a search field + list as a `.overlay()` on the main
   content view, toggled by a keyboard shortcut. Simpler but confined to the window.
3. **Sheet approach**: Present as a sheet. Less ideal because sheets are modal and
   block interaction with the underlying content.

The NSPanel approach is the most flexible and matches user expectations from VS Code,
Raycast, and Spotlight.

---

## 3. Focus and Keyboard Handling

### @FocusState

Tracks which view has focus. Can be a Bool (single view) or any Hashable type (multiple
views).

```swift
@FocusState private var focusedPane: PaneID?
// ...
TerminalView(pane: pane)
    .focused($focusedPane, equals: pane.id)
```

- `.defaultFocus($focusedPane, someValue)` sets initial focus.
- Programmatic focus changes by assigning to the binding.

### @FocusedValue / @FocusedBinding

Propagates values up the focus hierarchy to menu commands. The focused view and its
ancestors publish values; `Commands` views consume them.

```swift
// In the terminal view:
.focusedSceneValue(\.activeTerminal, $terminal)

// In Commands:
@FocusedBinding(\.activeTerminal) private var terminal
```

This is how menu items (Copy, Paste, Split Pane) know which terminal pane is active.

### .focusable() and Interactions

- `.focusable()` with no arguments: focusable for all interactions.
- `.focusable(interactions: .edit)`: for views that capture continuous input.
- `.focusable(interactions: .activate)`: for button-like controls (needs Keyboard
  Navigation enabled).
- `.focusEffectDisabled()`: suppresses the default focus ring.

### .onKeyPress() (macOS 14+)

Handles hardware keyboard input on the focused view:

```swift
.onKeyPress(.return) { ... return .handled }
.onKeyPress(characters: .alphanumerics, phases: .down) { keyPress in ... }
```

Requires the view to have focus. Returns `.handled` or `.ignored` to control event
propagation.

### .onMoveCommand()

Responds to arrow keys (macOS) or remote swipes (tvOS). Provides a `MoveCommandDirection`.

### NSEvent Monitors vs SwiftUI

- `NSEvent.addLocalMonitorForEvents(matching:)`: intercepts events within the app.
  Works regardless of SwiftUI focus state. Good for global shortcuts within the app.
- `NSEvent.addGlobalMonitorForEvents(matching:)`: intercepts events even when the app
  is not active. Requires accessibility permissions. Good for system-wide hotkeys
  (quick terminal toggle).
- SwiftUI's `.onKeyPress()` is scoped to the focused view. For a terminal emulator
  where the terminal surface handles raw key input via the Zig core, NSEvent monitors
  or direct `keyDown`/`flagsChanged` overrides on the NSView are more appropriate.

### Menu Bar Commands and Keyboard Shortcuts

```swift
.commands {
    CommandMenu("Terminal") {
        Button("New Tab") { ... }
            .keyboardShortcut("t", modifiers: .command)
        Button("Split Horizontally") { ... }
            .keyboardShortcut("d", modifiers: .command)
    }
    CommandGroup(replacing: .newItem) { ... }
    SidebarCommands()
    InspectorCommands()
}
```

Commands use `@FocusedValue` / `@FocusedBinding` to route actions to the active
terminal pane.

**Terminal relevance:** The terminal surface (NSView wrapping libghostty's Metal
renderer) will handle raw keyboard input directly. SwiftUI focus and keyboard APIs are
for the chrome: sidebar navigation, command palette, inspector. `@FocusedValue` is
critical for routing menu commands to the correct pane.

---

## 4. State and Data Flow

### @Observable (macOS 14+) vs ObservableObject

`@Observable` (Observation framework) replaces `ObservableObject` + `@Published`:
- More granular tracking: SwiftUI only re-renders views that read changed properties.
- Use `@State` to own an `@Observable` object (replaces `@StateObject`).
- Pass via `.environment()` or as a plain property (no `@ObservedObject` needed).
- Caveat: `@State` with `@Observable` can call `init()` multiple times (unlike
  `@StateObject` which guaranteed single init). For objects with expensive setup, use
  a factory pattern or keep using `@StateObject`.

For macOS 14+ targets, prefer `@Observable`. It reduces boilerplate and improves
performance through fine-grained observation.

### @Environment and Custom Keys

```swift
struct ActiveTerminalKey: EnvironmentKey {
    static let defaultValue: TerminalSession? = nil
}
extension EnvironmentValues {
    var activeTerminal: TerminalSession? {
        get { self[ActiveTerminalKey.self] }
        set { self[ActiveTerminalKey.self] = newValue }
    }
}
```

Inject at any level: `.environment(\.activeTerminal, session)`.

### @SceneStorage

Per-window persistent state that survives app restarts:

```swift
@SceneStorage("selectedSidebarItem") private var selectedItem: String?
```

Only supports basic types (String, Int, Double, Bool, URL, Data). For complex state,
serialize to Data.

### Sharing State Across Windows

`WindowGroup` creates independent scenes. To share state:
1. Inject a shared `@Observable` singleton via `.environment()` at the `App` level.
2. Use an actor or class with `@Observable` that all windows reference.
3. `@SceneStorage` is per-window only, not shared.

```swift
@main
struct MyttyApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
        }
    }
}
```

---

## 5. macOS-Specific Patterns

### Settings / Preferences

```swift
Settings {
    SettingsView()
}
```

Automatically wired to the app menu's Preferences item (Cmd+,). Use a
NavigationSplitView or TabView inside for multi-pane settings.

### MenuBarExtra

```swift
MenuBarExtra("Mytty", systemImage: "terminal") {
    // Menu items or window content
}
.menuBarExtraStyle(.window)  // or .menu (default)
```

The `.window` style shows a chromeless floating window anchored to the menu bar icon.
Good for a quick-access terminal or status display.

### Dock Menu

Not directly available in SwiftUI. Override `applicationDockMenu(_:)` in the
`NSApplicationDelegate` to return an `NSMenu`.

### Touch Bar

Deprecated as of 2024. No new Macs ship with Touch Bar. Not worth investing in.

### System Integration

- **Services menu**: Ghostty implements this via `Features/Services/`. Register
  services in Info.plist with `NSServices` entries. Handle via `NSApplication`
  delegate or `validRequestor(forSendType:returnType:)`.
- **Spotlight**: Not typically relevant for terminal apps.
- **Quick Look**: Not applicable.

---

## 6. Real-World Examples

### Ghostty (terminal emulator, libghostty)

Ghostty's macOS frontend (github.com/ghostty-org/ghostty) is the closest reference for
Mytty. Its source structure under `macos/Sources/`:

- `Ghostty/`: Core types (Ghostty.App, Ghostty.Surface, Ghostty.Inspector,
  Ghostty.Action, GhosttyDelegate, NSEvent+Extension)
- `Ghostty/Surface View/`: The NSView that hosts the Metal-rendered terminal surface
- `Features/Terminal/`: Terminal window management
- `Features/Splits/`: Split pane tree implementation
- `Features/Command Palette/`: Floating command palette (NSPanel-based)
- `Features/QuickTerminal/`: System-wide quick terminal (global hotkey + floating panel)
- `Features/Settings/`: Preferences window
- `Features/Global Keybinds/`: System-wide keyboard shortcuts
- `Features/Services/`: macOS Services menu integration
- `App/`: SwiftUI App definition, Helpers

Key architectural decisions:
- The terminal surface is an NSView (not a SwiftUI view) for direct Metal rendering
  and raw keyboard input handling.
- Split panes are managed by a custom tree structure, not SwiftUI's HSplitView.
- Tabs use NSWindow's native tabbing, not SwiftUI TabView.
- SwiftUI is used for the app shell, settings, and overlays.

### Xcode's Navigator/Editor/Inspector Pattern

Xcode uses a three-column layout: navigator (left sidebar), editor (center), inspector
(right sidebar). In SwiftUI terms, this maps to:

```
NavigationSplitView (sidebar) {
    // Navigator
} detail: {
    HSplitView {
        // Editor area
        if inspectorVisible {
            // Inspector
        }
    }
}
```

Or, with macOS 14+, the `.inspector()` modifier on the detail view replaces the manual
HSplitView approach for the trailing column.

### Terminal.app's Tab Model

Terminal.app uses NSWindow's native tab bar (`.tabbingMode = .preferred`). Each tab
contains a terminal session. This is AppKit's `NSWindowTabGroup`, not SwiftUI's TabView.
SwiftUI apps can opt into this by setting the window's tabbing mode via AppKit interop.

### Bonsplit Library

A purpose-built SwiftUI library for tab bars + split panes. Provides:
- Tab creation, reordering, cross-pane drag
- Horizontal/vertical splits with a tree model
- Focus navigation between panes
- Geometry synchronization for external programs
- Content view lifecycle management (recreate vs keep-alive)

This is the closest off-the-shelf solution to what a terminal multiplexer needs.

### CodeEditorView (mchakravarty)

Open-source SwiftUI code editor for macOS. Demonstrates hosting a complex text-editing
NSView inside SwiftUI with proper focus and keyboard handling.

---

## Summary: Recommended Architecture for Mytty

The terminal surface (libghostty's Metal renderer) must be an NSView, wrapped in
`NSViewRepresentable` for embedding in SwiftUI. This is non-negotiable for performance
and raw input handling.

For the app shell:

| Component | Primitive | Notes |
|-----------|-----------|-------|
| App structure | `WindowGroup` + `Settings` + `MenuBarExtra` | Standard SwiftUI app lifecycle |
| Session sidebar | `NavigationSplitView` (two-column) | Collapsible sidebar with session list |
| Terminal tabs | `NSWindow` tabbing or custom tab bar | SwiftUI TabView is not suitable |
| Split panes | Custom split tree or Bonsplit | HSplitView lacks needed control |
| Inspector | `.inspector()` modifier | macOS 14+ trailing sidebar |
| Command palette | NSPanel + SwiftUI content | Floating, non-activating panel |
| Quick terminal | NSPanel + global hotkey | Like Ghostty's QuickTerminal |
| Preferences | `Settings` scene | Standard Cmd+, |
| Menu commands | `.commands { }` + `@FocusedValue` | Route to active pane |
| State | `@Observable` + `@Environment` | Shared app state, per-window scene storage |

---

## Sources

- [2026-04-14] https://developer.apple.com/wwdc23/10162 (WWDC23: The SwiftUI cookbook for focus)
- [2026-04-14] https://developer.apple.com/wwdc22/10061 (WWDC22: Bring multiple windows to your SwiftUI app)
- [2026-04-14] https://createwithswift.com/presenting-an-inspector-with-swiftui/ (Inspector modifier guide)
- [2026-04-14] https://msena.com/posts/three-column-swiftui-macos/ (Three-column editor layout with NavigationSplitView + HSplitView)
- [2026-04-14] https://www.markusbodner.com/til/2021/02/08/create-a-spotlight/alfred-like-window-on-macos-with-swiftui/ (NSPanel floating panel pattern)
- [2026-04-14] https://bonsplit.alasdairmonk.com/ (Bonsplit: tab bar + split pane library for macOS SwiftUI)
- [2026-04-14] https://github.com/ghostty-org/ghostty/tree/main/macos/Sources (Ghostty macOS source structure)
- [2026-04-14] https://www.jessesquires.com/blog/2024/09/09/swift-observable-macro/ (@Observable vs ObservableObject behavioral differences)
- [2026-04-14] https://www.avanderlee.com/swiftui/observable-macro-performance-increase-observableobject/ (@Observable performance characteristics)
- [2026-04-14] https://www.fline.dev/window-management-on-macos-with-swiftui-4/ (Window management with SwiftUI 4)
- [2026-04-14] https://steipete.me/posts/2025/showing-settings-from-macos-menu-bar-items/ (MenuBarExtra + Settings interaction)
- [2026-04-14] https://github.com/stevengharris/SplitView (Custom SwiftUI split view library)
- [2026-04-14] https://levelup.gitconnected.com/swiftui-macos-floating-window-panel-4eef94a20647 (Floating panel pattern)
- [2026-04-14] https://hackingwithswift.com/quick-start/swiftui/how-to-detect-and-respond-to-key-press-events (onKeyPress modifier)
- [2026-04-14] https://github.com/martinlexow/SwiftUIWindowStyles (Window and toolbar style showcase)
