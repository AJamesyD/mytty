# Auto-Hide Sidebar and Tab Bar: Design Document

Mytty, a macOS terminal emulator built with SwiftUI.

## Iteration 1: Basic Design

The starting point. Sidebar and tab bar each have three modes: Pinned, Auto-hide, Hidden.

**Sidebar (left edge):**
- An invisible `Color.clear` strip (8px wide) along the left edge of the window acts as the hover trigger.
- On mouse enter, the sidebar slides in from the left with a spring animation.
- On mouse exit, wait 300ms, then slide the sidebar out.

**Tab bar (top edge):**
- Same pattern: 8px invisible strip along the top edge.
- On hover, tab bar slides down. On exit, 300ms delay, slides up.

**Problems identified:**
- 8px is too narrow for trackpad users (imprecise cursor control).
- No consideration for modal states (session manager, copy mode).
- No keyboard interaction model.
- No thought given to title bar / traffic light integration.
- SwiftUI's `.onHover` is unreliable at high cursor velocity (known bug: exit events are missed). This makes the basic approach fragile.
- Sidebar sliding in resizes the terminal, causing reflow. Bad for a terminal app.

---

## Iteration 2: Addressing Core Issues

### Hover detection

Replace `.onHover` with an `NSViewRepresentable` wrapping `NSTrackingArea`. This gives reliable `mouseEntered`/`mouseExited` events even at high cursor velocity. Use `.inVisibleRect` + `.activeInKeyWindow` options.

Widen the trigger region to 20px but add a 150ms dwell requirement: the cursor must remain in the trigger zone for 150ms before the panel reveals. This prevents accidental triggers when the user sweeps the cursor across the window. The macOS Dock uses a 200ms dwell by default (`autohide-delay`); 150ms feels slightly more responsive while still filtering drive-by hovers.

### Overlay, not resize

The sidebar and tab bar overlay the terminal content instead of pushing it. This avoids terminal resize/reflow, which is disruptive (text rewraps, cursor position shifts). The tradeoff: the panel covers terminal content while visible. Acceptable because the panel is transient in auto-hide mode.

Add a subtle drop shadow on the panel's inner edge to visually separate it from the terminal content beneath.

### Keyboard interaction model

- `Cmd+S` toggles the sidebar between temporarily pinned and dismissed. If the mode is Auto-hide, `Cmd+S` pins it open (ignoring hover-out). Pressing `Cmd+S` again dismisses it back to auto-hide behavior. If the mode is Hidden, `Cmd+S` still reveals it (temporarily pinned until dismissed).
- `Cmd+Shift+T` toggles the tab bar similarly.
- This means keyboard always gives you access, regardless of the auto-hide mode.

### Modal state suppression

When any of these are active, suppress auto-hide triggers entirely:
- Session manager overlay (`Cmd+J`)
- Copy mode
- Window mode (pane management)
- Any modal sheet or popover

The panels stay in their current state (visible or hidden) until the modal dismisses. This prevents the sidebar from sliding in/out while the user is focused on a modal interaction.

### Tab bar and title bar

The tab bar sits below the macOS title bar. The title bar (with traffic lights) is always visible. The tab bar auto-hides independently beneath it. This avoids fighting with `NSWindow` title bar behavior and keeps the traffic lights accessible.

**Problems remaining:**
- No visual affordance that auto-hide is active. New users won't discover the hover region.
- No handling of floating panes near edges.
- Configuration story is undefined.
- Multi-monitor edge conflicts not addressed.
- Accessibility (VoiceOver) not addressed.

---

## Iteration 3: Final Design

### Three modes

| Mode | Sidebar behavior | Tab bar behavior |
|------|-----------------|-----------------|
| Pinned | Always visible. Terminal content area is narrower (resize, not overlay). | Always visible below title bar. Terminal content area is shorter. |
| Auto-hide | Hidden by default. Reveals on edge hover or keyboard shortcut. Overlays terminal content. | Hidden by default. Reveals on top-edge hover or keyboard shortcut. Overlays terminal content. |
| Hidden | Never shown via hover. Keyboard shortcut still works (temporary reveal). | Never shown via hover. Keyboard shortcut still works (temporary reveal). |

Default for new users: Pinned (both). Auto-hide is opt-in. This avoids confusing new users who don't know about the hover regions.

### Hover trigger zone

- Sidebar: 20px wide invisible region along the left edge of the content area (below the title bar, above the bottom edge).
- Tab bar: 20px tall invisible region along the top of the content area (just below the title bar).
- Dwell time: 150ms. The cursor must stay in the trigger zone for 150ms before the panel begins to reveal. Passing through quickly does nothing.
- Dismiss delay: 300ms after the cursor leaves both the trigger zone and the revealed panel. If the cursor re-enters either region within 300ms, the dismiss is cancelled.

Implementation: `NSViewRepresentable` with `NSTrackingArea` using `.mouseEnteredAndExited`, `.inVisibleRect`, `.activeInKeyWindow`. Do not use SwiftUI's `.onHover` (unreliable at high velocity). Use a `DispatchWorkItem` for the dwell and dismiss timers so they can be cancelled.

### Animation

- Reveal: `easeOut` curve, 200ms duration. The panel slides in from the edge.
- Dismiss: `easeIn` curve, 150ms duration. Slightly faster out than in (feels snappier on dismiss).
- SwiftUI: `.animation(.easeOut(duration: 0.2), value: isSidebarRevealed)` on the offset/position.
- The panel's position is driven by an offset: `offset(x: isSidebarRevealed ? 0 : -sidebarWidth)` for the sidebar, `offset(y: isTabBarRevealed ? 0 : -tabBarHeight)` for the tab bar.

### Overlay behavior

In Auto-hide and Hidden modes, the panel overlays the terminal. The terminal does not resize. The panel has:
- A background blur (`.ultraThinMaterial`) matching the rest of the app's chrome.
- A 1px shadow on the inner edge (right edge for sidebar, bottom edge for tab bar).

In Pinned mode, the panel is part of the layout. The terminal resizes to accommodate it. This is the standard non-auto-hide behavior.

### Keyboard interaction

| Shortcut | Current mode | Action |
|----------|-------------|--------|
| `Cmd+S` | Pinned | Switches to Hidden (sidebar disappears, terminal expands). |
| `Cmd+S` | Auto-hide | Temporarily pins the sidebar open. Press again to return to auto-hide. |
| `Cmd+S` | Hidden | Temporarily reveals the sidebar (pinned open). Press again to hide. |
| `Cmd+Shift+T` | (same logic for tab bar) | |

"Temporarily pinned" means: the panel stays open until the user presses the shortcut again. Hover-out does not dismiss it. This gives keyboard users full control.

### Modal state suppression

Suppress auto-hide hover triggers when any of these are active:
- Session manager overlay (`Cmd+J`)
- Copy mode
- Window mode
- Any presented sheet, popover, or alert
- Context menus (right-click menus)

Implementation: a shared `@Observable` state object (e.g., `ModalStateTracker`) that each modal sets a flag on when it activates. The hover trigger checks `modalStateTracker.isAnyModalActive` before starting the dwell timer.

If a panel is already revealed when a modal activates, it stays revealed (don't yank it away mid-interaction). When the modal dismisses, normal auto-hide behavior resumes.

### Floating panes near edges

If a floating pane is positioned within 40px of the left edge, the sidebar trigger zone shrinks to 8px (the minimum) to reduce accidental triggers. The pane takes priority. Same logic for the tab bar trigger zone and panes near the top edge.

Implementation: the trigger zone width is a computed property that checks the positions of floating panes.

### Tab bar and title bar integration

The title bar (with traffic lights: close, minimize, zoom) is always visible. It uses `.windowStyle(.hiddenTitleBar)` is NOT used; the standard title bar remains.

The tab bar is a separate view below the title bar. In Pinned mode, it's part of the layout. In Auto-hide mode, it overlays the terminal content just below the title bar.

The 20px trigger zone for the tab bar starts at the bottom edge of the title bar. This means the user moves the cursor to the title bar area and slightly below to trigger the tab bar. The title bar itself is not a trigger (it has its own click targets: traffic lights, window drag).

Tab switching shortcuts (`Cmd+1` through `Cmd+9`) always work regardless of tab bar visibility.

### Visual hint

When auto-hide is active, show a subtle indicator at the edge:
- Sidebar: a 2px wide, 24px tall translucent bar centered vertically on the left edge. Color: `Color.primary.opacity(0.15)`. Disappears when the panel is revealed.
- Tab bar: a 24px wide, 2px tall translucent bar centered horizontally at the top of the content area.

This hint is optional and can be disabled in settings (`showAutoHideHints`). Enabled by default.

### Multi-monitor and screen-edge windows

macOS edge gestures (Mission Control, Spaces switching) are trackpad swipe gestures, not cursor-position-based. They don't conflict with hover detection because hover uses `NSTrackingArea` (cursor position), while Spaces switching uses multi-finger swipe (handled by the system before the app sees it).

The Dock auto-hide does use cursor position at the screen edge. If the Mytty window's left edge is flush with the screen's left edge and the Dock is also on the left with auto-hide, both triggers compete. Mitigation: the 150ms dwell requirement means a quick bump to the edge (which triggers the Dock at 200ms) won't trigger Mytty's sidebar if the user moves away within 150ms. In practice, the Dock's trigger zone extends below the app window, so the overlap is minimal. No special handling needed beyond the dwell timer.

If the window is not at the screen edge, there's no conflict at all.

### Configuration

Settings are stored in the app's config file (e.g., `~/.config/mytty/config.toml`) and exposed in the Settings UI.

```toml
[sidebar]
mode = "pinned"  # "pinned" | "auto-hide" | "hidden"

[tab-bar]
mode = "pinned"  # "pinned" | "auto-hide" | "hidden"

[auto-hide]
dwell-ms = 150
dismiss-delay-ms = 300
show-hints = true
```

The Settings UI provides a segmented control for each panel's mode (three options). The timing values are advanced settings, not shown by default.

Right-click on the sidebar or tab bar also offers "Pin Sidebar" / "Auto-hide Sidebar" / "Hide Sidebar" in a context menu for quick switching.

### Accessibility

- VoiceOver: keyboard shortcuts (`Cmd+S`, `Cmd+Shift+T`, `Cmd+1-9`) always work regardless of mode. VoiceOver users never need hover.
- The sidebar and tab bar are in the accessibility tree even when visually hidden in auto-hide mode. VoiceOver can navigate to them. When VoiceOver focus enters the sidebar region, the sidebar reveals (using `NSAccessibility` notifications, not hover).
- The trigger zone is not in the accessibility tree (it's a transparent hit-test region, not interactive content).
- Reduced Motion: if the user has "Reduce motion" enabled in System Settings, replace slide animations with a crossfade (opacity transition, 150ms).

---

## Implementation Notes for SwiftUI

### State model

```swift
enum PanelMode: String, Codable {
    case pinned, autoHide, hidden
}

@Observable
final class PanelState {
    var sidebarMode: PanelMode = .pinned
    var tabBarMode: PanelMode = .pinned
    var isSidebarRevealed: Bool = false
    var isTabBarRevealed: Bool = false
    var isSidebarTempPinned: Bool = false
    var isTabBarTempPinned: Bool = false
}
```

### Hover trigger view

Use `NSViewRepresentable` with `NSTrackingArea` for the trigger zone. Do not use `.onHover`.

```swift
struct EdgeTriggerView: NSViewRepresentable {
    let onDwell: () -> Void
    let onExit: () -> Void
    let dwellDuration: TimeInterval

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
            owner: context.coordinator,
            userInfo: nil
        )
        view.addTrackingArea(area)
        return view
    }

    // Coordinator handles mouseEntered/mouseExited with dwell timer
}
```

### Layout structure

```
NSWindow (standard title bar with traffic lights)
├── Title bar (always visible)
└── Content area (ZStack)
    ├── Terminal view (full size, always present)
    ├── Sidebar overlay (conditional, offset-animated)
    ├── Tab bar overlay (conditional, offset-animated)
    ├── Sidebar trigger zone (20px, left edge, invisible)
    └── Tab bar trigger zone (20px, top edge, invisible)
```

In Pinned mode, use `HStack` / `VStack` instead of `ZStack` so the terminal resizes.

### Key SwiftUI modifiers

- `.animation(.easeOut(duration: 0.2), value: panelState.isSidebarRevealed)` for reveal.
- `.accessibilityElement(children: .contain)` on the sidebar/tab bar.
- `@Environment(\.accessibilityReduceMotion)` to switch to opacity transitions.
- `.background(.ultraThinMaterial)` on the panel.
- `.shadow(color: .black.opacity(0.1), radius: 2, x: 1, y: 0)` on the sidebar's trailing edge.

### Timer management

Use `DispatchWorkItem` for dwell and dismiss timers. Store them on the coordinator so they can be cancelled when the cursor re-enters.

```swift
class TriggerCoordinator: NSResponder {
    var dwellWork: DispatchWorkItem?
    var dismissWork: DispatchWorkItem?

    override func mouseEntered(with event: NSEvent) {
        dismissWork?.cancel()
        dwellWork = DispatchWorkItem { [weak self] in
            self?.onDwell()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + dwellDuration,
            execute: dwellWork!
        )
    }

    override func mouseExited(with event: NSEvent) {
        dwellWork?.cancel()
        guard !isTempPinned else { return }
        dismissWork = DispatchWorkItem { [weak self] in
            self?.onExit()
        }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + dismissDelay,
            execute: dismissWork!
        )
    }
}
```

### Reduced Motion support

```swift
@Environment(\.accessibilityReduceMotion) var reduceMotion

var revealAnimation: Animation {
    reduceMotion
        ? .easeInOut(duration: 0.15).opacity
        : .easeOut(duration: 0.2)
}
```

## Sources

- [2026-04-14] https://macos-defaults.com/dock/autohide-delay.html (macOS Dock autohide delay default: 0.2s)
- [2026-04-14] https://gist.github.com/importRyan/c668904b0c5442b80b6f38a980595031 (Reliable SwiftUI mouse hover via NSTrackingArea)
- [2026-04-14] https://nilcoalescing.com/blog/TrackingHoverLocationInSwiftUI/ (onContinuousHover, macOS 13+)
- [2026-04-14] https://github.com/zen-browser/desktop/issues/2587 (Zen Browser sidebar hover issues)
- [2026-04-14] https://github.com/martinlexow/SwiftUIWindowStyles (SwiftUI window and toolbar style combinations)
