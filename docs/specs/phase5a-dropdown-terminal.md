# Phase 5a: Dropdown Terminal

Mytty macOS terminal emulator, libghostty backend.

**Status:** Implemented

**Goal:** Add a quake-style dropdown terminal that slides in from the top of the screen on a global hotkey. The dropdown is a single-pane terminal that persists across show/hide cycles, independent of the main window.

**Date:** 2026-04-16

**Research:** `/tmp/ai-research-dropdown-terminal.md`

---

## 1. Overview

A global hotkey toggles a borderless terminal panel that slides down from the top of the screen. The panel floats above other windows, auto-hides on focus loss, and works across all Spaces. The dropdown owns a detached session (IDs from SessionStore, but not in the sessions array).

Primary reference: Ghostty's QuickTerminal (`vendor/ghostty/macos/Sources/Features/QuickTerminal/`).

## 2. Window

### 2.1 Class

`DropdownPanel` subclasses `NSPanel`:

```swift
class DropdownPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
```

Both overrides are required because removing `.titled` from the style mask causes NSPanel to return `false` by default.

### 2.2 Style mask

- Remove `.titled` (no title bar, square corners)
- Insert `.nonactivatingPanel` (showing the panel does not activate the app or bring other windows forward)

### 2.3 Window level

Two-phase strategy (from Ghostty):

| Phase | Level | Reason |
|-------|-------|--------|
| During animation | `.popUpMenu` | Renders above the menu bar while sliding in from off-screen |
| After animation | `.floating` | Stays above normal windows but allows IME popups and system UI to appear on top |

### 2.4 Collection behavior

Flags: `.canJoinAllSpaces`, `.ignoresCycle`, `.fullScreenAuxiliary`.

- `.canJoinAllSpaces`: visible on every Space
- `.ignoresCycle`: excluded from Cmd+\` window cycling
- `.fullScreenAuxiliary`: can appear alongside fullscreen apps

A future config option could offer `moveToActiveSpace` as an alternative to `canJoinAllSpaces`.

### 2.5 Accessibility

Set `window.identifier` to `"com.mytty.dropdownTerminal"` and `accessibilitySubrole` to `.floatingWindow` so tiling window managers (AeroSpace, yabai) can identify and float it.

## 3. Global hotkey

### 3.1 Mechanism

`CGEvent` tap via `CGEvent.tapCreate`. This is the only approach that can consume the event (return `nil`), preventing other apps from seeing the hotkey.

Requires Accessibility permissions. On first use, macOS shows the system permission dialog. No custom onboarding needed for v1.

### 3.2 Hardcoded key

Phase 5a ships with a hardcoded hotkey. Configurable hotkeys come in Phase 4f-2 (global hotkey support in the keybinding system).

Default: **Ctrl+\`** (backtick). Matches Guake/Yakuake convention. Not commonly bound by other apps on macOS.

### 3.3 Implementation

A `GlobalHotkeyMonitor` class:

- Creates a `CGEvent` tap on `.cgSessionEventTap` for `keyDown` events
- Attaches to `CFRunLoopGetMain()` on `.commonModes`
- Checks incoming events against the hardcoded trigger
- Returns `nil` to consume matched events
- Handles both active and inactive cases (Ctrl+\` is not a useful terminal input, safe to consume globally)
- Retries tap creation on a timer if Accessibility permissions are not yet granted

Owned by `MyttyApp` (or an `AppDelegate` if needed for lifecycle reasons).

### 3.4 Menu item

The menu item (section 8.3) displays the Ctrl+\` shortcut for discoverability. The CGEvent tap handles the actual key event in all cases. SwiftUI menu shortcuts with Ctrl-only modifiers are unreliable on macOS, so the menu item is display-only.

## 4. Controller

`DropdownController` manages the dropdown lifecycle. It is a plain Swift class, not a SwiftUI view.

### 4.1 State

A single `visible` bool (not a state machine). `animateIn` guards on `!visible`, `animateOut` guards on `visible`. A toggle during animation is a no-op. This matches Ghostty's approach, which has proven reliable.

### 4.2 Show (animateIn)

1. If `!NSApp.isActive`, store `NSWorkspace.shared.frontmostApplication` as `previousApp` (only if not Mytty itself)
2. Determine target screen (see section 6)
3. Set window level to `.popUpMenu`
4. Position window at initial origin (above visible frame, fully off-screen)
5. Set `alphaValue = 0`
6. Call `window.orderFrontRegardless()`
7. Animate with `NSAnimationContext.runAnimationGroup`:
   - `alphaValue`: 0 -> 1
   - `setFrame`: initial origin -> final origin
   - Duration: 0.2s, timing: `.easeIn`
8. On completion: set window level to `.floating`, call `NSApp.activate()` (the `ignoringOtherApps:` variant is deprecated since macOS 14), make window key
9. Retry `makeKeyAndOrderFront` + `makeFirstResponder` (on the terminal surface view) up to 10 times at 25ms intervals (macOS focus bug workaround from Ghostty). Without `makeFirstResponder`, the window is key but keyboard input doesn't reach the terminal.

### 4.3 Hide (animateOut)

0. If `!window.isOnActiveSpace`, skip animation: clear `previousApp`, call `window.orderOut(self)`, return. Animating a window on a different space produces visual artifacts.
1. Restore `previousApp` via `previousApp.activate(options: [])` before the animation (so macOS doesn't bring forward another Mytty window)
2. Set window level to `.popUpMenu`
3. Animate with `NSAnimationContext.runAnimationGroup`:
   - `alphaValue`: 1 -> 0
   - `setFrame`: final origin -> initial origin (slide up)
   - Duration: 0.2s, timing: `.easeOut`
4. On completion: `window.orderOut(self)`

### 4.4 Auto-hide

On `windowDidResignKey`: animate out. The controller is the window's delegate.

Guards before acting:
- If `!visible`, return (prevents double-processing after animateOut)
- If `window.attachedSheet != nil`, return (don't hide during modal dialogs)

When focus moves to another Mytty window (`NSApp.isActive` is still true), clear `previousApp` so focus is not restored to a stale app on next hide.

Space-switching: track `previousActiveSpace` (via `CGSSpace.active()`) on each show. In `windowDidResignKey`, if the active space changed, the user swiped Spaces. Since the window has `.canJoinAllSpaces`, re-key it on the new space instead of hiding:

```
if currentActiveSpace != previousActiveSpace {
    // User switched spaces, re-show on new space
    window.makeKeyAndOrderFront(nil)
    previousActiveSpace = currentActiveSpace
} else {
    // Same space, lost focus to another app/window
    animateOut()
}
```

### 4.5 Focus restoration

Track `previousApp` on show. Restore on hide. If `previousApp` is `nil` (Mytty was already frontmost), skip restoration.

## 5. Position and sizing

### 5.1 Position

Top-only for v1. The panel spans the full width of the target screen's visible frame.

- Initial origin: `(screen.visibleFrame.minX, screen.visibleFrame.maxY)` (just above visible area)
- Final origin: `(screen.visibleFrame.minX, screen.visibleFrame.maxY - panelHeight)`

### 5.2 Size

- Width: `screen.visibleFrame.width` (full width)
- Height: 40% of `screen.visibleFrame.height` (default)

Future config: `dropdown-height = 40` (percentage) or `dropdown-height = 600` (pixels).

## 6. Screen selection

Show on the screen containing the mouse cursor:

```swift
let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) }
    ?? NSScreen.main
    ?? NSScreen.screens.first
```

Screen is determined on each show (not cached), so the dropdown follows the user across monitors.

Future config: `dropdown-screen = "mouse"` (default), `"main"`, or `"menu-bar"`.

## 7. Session model

### 7.1 Dedicated session

The dropdown controller owns its own `MyttySession`, created via `SessionStore.createDetachedSession()`. This method uses the store's shared ID counters (avoiding collisions with IPC lookups) but does not add the session to the store's `sessions` array.

The session:

- Is created lazily on first toggle
- Persists across show/hide cycles
- Is re-created if the shell exits (user types `exit`)
- Has a single tab with a single pane (no splits, no tabs in the dropdown for v1)
- Uses the user's default shell and home directory
- Starts fresh on each app launch (no persistence)

### 7.2 Why detached instead of in SessionStore?

Putting the dropdown session in SessionStore's `sessions` array would require:
- An `isDropdown` flag on MyttySession
- Filtering in the sidebar view
- Handling edge cases (user tries to close/rename/split the dropdown session from the sidebar)
- Persistence logic that doesn't apply (dropdown should start fresh)

The detached approach gives safe IDs without any of this. If a future phase wants to show the dropdown in the session manager, the session can be moved into the array then.

### 7.3 Surface hosting

The dropdown panel's `contentView` is an `NSHostingView` wrapping a SwiftUI view that contains `PaneView` (the existing terminal view component). This reuses the full terminal rendering stack without duplicating any view code.

## 8. App integration

### 8.1 Ownership

`DropdownController` is created and held by `MyttyApp`. The global hotkey monitor calls `controller.toggle()`.

### 8.2 App lifecycle

The dropdown can be hidden (window ordered out) while the main window is closed. Without intervention, SwiftUI's default behavior terminates the app when the last window closes.

Add an `NSApplicationDelegateAdaptor` that returns `false` from `applicationShouldTerminateAfterLastWindowClosed`. This keeps the app alive so the dropdown can be toggled back.

The controller registers for `NSApplication.willTerminateNotification` to clean up global state (order out the window, restore any future Dock hiding).

### 8.2 Activation policy

Static `.regular` for v1 (app always in Dock and Cmd+Tab). Dynamic switching is deferred: the edge cases around focus and Dock icon visibility are not worth the complexity for the initial release.

### 8.3 Menu bar

Add a "Toggle Dropdown Terminal" menu item under the View menu with the hotkey displayed. This also serves as discoverability for the feature.

## 9. Config (future, not in v1)

These config keys are reserved for when configurable hotkeys (4f-2) and dropdown options ship:

```toml
[dropdown]
position = "top"           # top (v1 only), bottom, left, right, center (future)
height = 40                # percentage of screen height
screen = "mouse"           # mouse, main, menu-bar
auto-hide = true           # hide on focus loss
animation-duration = 0.2   # seconds
space-behavior = "move"    # move (all spaces) or remain (pull to active)
```

The global hotkey will be configured through the keybinding system (4f-2):

```toml
[keybindings]
toggle-dropdown = "ctrl+`"
```

## 10. Files

| File | Purpose |
|------|---------|
| `Mytty/App/DropdownPanel.swift` | NSPanel subclass |
| `Mytty/App/DropdownController.swift` | Show/hide state, animation, focus management, window delegate, session ownership |
| `Mytty/App/GlobalHotkeyMonitor.swift` | CGEvent tap for the hardcoded hotkey |
| `Mytty/App/MyttyApp.swift` | Own DropdownController and GlobalHotkeyMonitor, add menu item, add NSApplicationDelegateAdaptor |
| `Mytty/App/MyttyAppDelegate.swift` | `applicationShouldTerminateAfterLastWindowClosed` returns `false` |
| `Mytty/Models/SessionStore.swift` | Add `createDetachedSession()` method |

## 11. Phasing

### Phase 5a-1: Core (this spec)

- DropdownPanel (NSPanel subclass)
- DropdownController (show/hide/toggle, animation, auto-hide, focus restore)
- GlobalHotkeyMonitor (CGEvent tap, hardcoded Ctrl+\`)
- Dedicated session owned by the controller (not in SessionStore)
- Top-only, full-width, 40% height
- Mouse-cursor screen selection
- Menu item for discoverability

### Phase 5a-2: Polish (follow-up)

- Configurable position (bottom, left, right, center)
- Configurable size (percentage or pixels)
- Configurable screen selection
- Configurable animation duration
- Space behavior option (move vs remain)
- Dock conflict auto-hide

### Phase 4f-2: Configurable hotkey (separate track)

- Global hotkey support in the keybinding system
- `toggle-dropdown` action replaces the hardcoded Ctrl+\`

## 12. Out of scope

- Tabs or splits within the dropdown (the dropdown is a single pane)
- Session transfer between dropdown and main window
- Dynamic activation policy switching
- Multiple dropdown windows
- Custom theme/profile for the dropdown session

## 13. Known limitations (v1)

- **Dock conflict**: if the Dock is positioned at the top of the screen (rare), the dropdown may overlap it. Dock auto-hide is deferred to Phase 5a-2.
- **Not resizable**: the dropdown has a fixed 40% height. Manual resize support is deferred.
- **No persistence**: the dropdown session starts fresh on each app launch.
- **Accessibility permission**: if revoked mid-session, the global hotkey stops working. The menu item still works when Mytty is active.

## 14. Acceptance criteria

1. Ctrl+\` toggles the dropdown from any app
2. The dropdown slides down from the top of the screen with a fade-in animation
3. The dropdown slides up and fades out on toggle or focus loss
4. The terminal in the dropdown is functional (input, output, shell integration)
5. The dropdown persists across show/hide (shell state preserved)
6. The dropdown appears on the screen with the mouse cursor
7. The dropdown works on all Spaces and alongside fullscreen apps
8. The dropdown is excluded from Cmd+\` window cycling
9. A menu item shows the hotkey for discoverability
10. Ctrl+\` works both when Mytty is active and when another app is focused
11. If the shell exits, the next toggle re-creates the session
12. The dropdown does not activate the app or bring other Mytty windows forward when shown
13. The dropdown does not appear in the sidebar or session manager
