# Phase 5b: Hints Mode

Mytty macOS terminal emulator, libghostty backend.

**Status:** 5b-1 (terminal provider) and 5b-2 (chrome provider) shipped. 5b-3 (IPC) remaining.

**Goal:** A general label-and-act system with pluggable target providers. Two providers at launch: terminal (URLs, paths, hashes) and chrome (sessions, tabs, panes).

**Date:** 2026-04-22

---

## 1. Core Types

These Swift protocols and types are the implementation contract.

```swift
enum HintAction: Hashable, Sendable {
    case copy
    case open
    case paste
    case focus
    case close
}
```

```swift
@MainActor
protocol HintTarget {
    var id: String { get }
    var labelOrigin: CGPoint { get }
    var displayText: String { get }
    var availableActions: [HintAction] { get }
    var defaultAction: HintAction { get }
}
```

```swift
@MainActor
protocol HintTargetProvider {
    var providerID: String { get }
    func targets(in geometry: HintsGeometry) -> [any HintTarget]
}
```

```swift
// All access is @MainActor. No Sendable conformance needed.
enum HintsGeometry {
    case terminal(rows: Int, cols: Int, cellWidth: CGFloat, cellHeight: CGFloat, offsetX: CGFloat, offsetY: CGFloat)
    case chrome(elementFrames: [String: CGRect])
}
```

Providers are `@MainActor` because the chrome provider reads from `SessionStore` (which is `@MainActor @Observable`). The terminal provider also runs on MainActor since it calls `ghostty_surface_read_text` through the surface view.

```swift
enum TerminalMatchType: CaseIterable {
    case url, path, hash, ip, linenum
}

struct TerminalHintTarget: HintTarget {
    let id: String
    let labelOrigin: CGPoint
    let displayText: String
    let matchType: TerminalMatchType
    let row: Int
    let colRange: Range<Int>

    var availableActions: [HintAction] {
        switch matchType {
        case .url, .path: return [.copy, .open, .paste]
        case .hash, .ip, .linenum: return [.copy, .paste]
        }
    }

    var defaultAction: HintAction { .copy }
}
```

```swift
enum ChromeElement {
    case session(sessionID: Int)
    case tab(sessionID: Int, tabID: Int)
    case pane(paneID: Int)
}

struct ChromeHintTarget: HintTarget {
    let id: String
    let labelOrigin: CGPoint
    let displayText: String
    let chromeElement: ChromeElement

    var availableActions: [HintAction] { [.focus, .close] }
    var defaultAction: HintAction { .focus }
}
```

`.rename` is deferred. Rename requires a text input flow that doesn't fit the transient hints model.

```swift
struct HintLabel {
    let target: any HintTarget
    let label: String
}
```

HintLabel and HintsModeState are not Sendable. They are accessed only from the MainActor via HintsModeManager.

Column offsets in `TerminalHintTarget` count terminal cells (wide characters = 2 cells), not Swift Character indices.

```swift
enum HintsModeState {
    case inactive
    case active(labels: [HintLabel], typed: String)
    case filtering(labels: [HintLabel], typed: String, remaining: [HintLabel])
    case selected(label: HintLabel, action: HintAction)
}
```

The `.selected` state exists to support `--multiple` mode: after executing the action, the manager transitions back to `.active` with re-assigned labels for remaining targets, rather than going through `.inactive`.

`.active` with an empty `labels` array represents the zero-match state (see section 5).

State transitions:

```
inactive -> active          (activation keybinding or IPC)
active -> filtering          (first label character typed)
active -> inactive           (Esc, or zero matches after timeout)
active -> selected           (single-char label matches exactly one target)
filtering -> filtering       (additional label character narrows candidates)
filtering -> selected        (typed string matches exactly one label)
filtering -> active          (Backspace clears all typed characters)
filtering -> inactive        (Esc)
selected -> active           (--multiple mode: re-label remaining targets)
selected -> inactive         (normal mode: action executed, exit)
```

The active provider is stored on `HintsModeManager`, not in the state enum. This avoids existential type storage in the enum and keeps the state a plain value type.

`HintsModeManager` is `@MainActor @Observable`, held as `@State` on ContentView, following the CopyModeManager/WindowModeManager pattern.

---

## 2. Target Providers

### TerminalHintTargetProvider

Reads visible terminal text via `ghostty_surface_read_text` with viewport-relative coordinates. Applies built-in regex patterns for each `TerminalMatchType`. Converts cell coordinates to point positions using the `cellWidth`, `cellHeight`, `offsetX`, and `offsetY` values from `HintsGeometry.terminal`. The provider iterates from row 0 to `rows - 1`, calling the line-reader for each row. Targets ordered top-to-bottom, left-to-right.

Built-in patterns:

| Type | Regex | Notes |
|------|-------|-------|
| url | `https?://[^\s<>"{}|\\^` `` ` `` `\[\]]+` | HTTP and HTTPS URLs |
| path | `/[\w.-]+/[\w./-]+` or `\.{0,2}/[\w./-]+\.\w+` | Absolute paths (two+ components), relative paths with extensions |
| hash | `\b[0-9a-f]{7,40}\b` | Git-style hex hashes |
| ip | `\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b` | IPv4 addresses |
| linenum | `[\w./+-]+:\d+` | filename:line patterns (e.g., `foo.swift:42`) |

Post-match trim: strip trailing `[.,;:!?)'\">\]]+` from the matched URL. This prevents capturing punctuation that follows URLs in prose.

The `hash` pattern excludes matches immediately preceded by `#` (to avoid matching CSS color codes). The `ip` pattern validates octets are 0-255 as a post-match filter.

Single-component absolute paths like `/tmp` require the two-component pattern to match (e.g., `/tmp/foo`). This trades recall for precision.

Patterns are applied in order. When matches overlap, the longer match wins. When equal length, the earlier pattern in the table wins.

The provider receives a line-reader closure `(Int) -> String?` (returning the text of a given viewport row) and `HintsGeometry` at activation time, rather than holding a reference to `ghostty_surface_t`. This keeps the provider in `Models/` without requiring a `GhosttyKit` import. The line-reader closure returns `nil` for rows outside the viewport. The provider skips those rows.

Cell-to-point conversion must account for wide characters (CJK, emoji) that occupy two terminal cells but one Swift Character. The provider walks the terminal text counting display widths (using Unicode East Asian Width or a `wcwidth` equivalent) rather than using `String.Index` distance. Concretely: iterate `Character` values, check each scalar's `Unicode.GeneralCategory` and East Asian Width property to determine if it occupies 1 or 2 cells. This ensures `labelOrigin.x` is correct for lines containing wide characters.

### ChromeHintTargetProvider

Reads from `SessionStore`. Labels sidebar sessions, tabs within the active session, and panes within the active tab. `labelOrigin` positions come from the `elementFrames` dictionary in `HintsGeometry.chrome` (keyed by element ID). Targets ordered: sessions top-to-bottom, tabs left-to-right, panes by layout position.

Chrome targets are positioned in the chrome UI (sidebar, tab bar), not in the terminal pane. Terminal hints overlay is rendered in PaneView (like CopyModeOverlay). Chrome hints overlay is rendered in ContentView (above the sidebar and tab bar). These are separate overlay views sharing the same HintsOverlayView component, differing only in coordinate space and backdrop scope.

Frame collection uses SwiftUI anchor preferences. Each labelable chrome element (sidebar session row, tab bar tab, pane container) applies `.anchorPreference(key: ChromeElementFrameKey.self, value: .bounds)` with its element ID. ContentView collects frames via `.overlayPreferenceValue(ChromeElementFrameKey.self)` and passes them as `HintsGeometry.chrome(elementFrames:)` to the provider. Only currently-visible elements report frames (SwiftUI preference keys naturally exclude off-screen views). When the sidebar is collapsed, no session or tab frames are reported, so chrome hints label only panes.

Chrome hints label navigation targets (sessions, tabs, panes) only, not interactive buttons (new tab, toggle sidebar, session manager). These buttons already have dedicated keybindings. Adding a `.button` case to `ChromeElement` is deferred unless users request it.

Pane labels are placed at a fixed inset from the top-left corner of the pane's visible rect (8pt from each edge). This avoids overlap with the tab bar, sidebar, and terminal content at the edges.

---

## 3. Label Algorithm

Home-row-first frequency-optimized alphabet. Default: `asdfghjkl` (configurable via `[hints] alphabet`). Labels are deterministic: given the same terminal content and alphabet, the same targets get the same labels. Labels do not depend on cursor position. Across invocations with different content, labels will differ because the target set differs.

When all targets fit in the alphabet (count <= alphabet.count), assign single-character labels. When targets exceed the alphabet, assign ALL labels as two-character combinations (no mixing of single and two-char labels). This eliminates prefix ambiguity: every label has the same length, so each keystroke is unambiguous.

The first character partitions targets into groups. Typing the first character narrows to that group and shows only the second characters. The second character selects within the group.

With a 9-character alphabet: up to 9 targets get single-char labels. 10-81 targets get two-char labels. This is a clean threshold, not a mix.

```swift
func assignLabels(targets: [any HintTarget], alphabet: String) -> [HintLabel]
```

Maximum displayed targets: `alphabet.count` (single-char) or `alphabet.count * alphabet.count` (two-char). With the default 9-character alphabet: 9 or 81. Targets beyond this limit are not labeled. The provider returns all matches, but `assignLabels` truncates to the applicable limit. This keeps labels to at most two characters.

### Alternatives rejected

- **Proximity-based ordering** (WezTerm, flash.nvim): closer targets get shorter labels. Rejected because terminal output patterns are spatially stable across invocations. Users learn "the URL at the top is always 'a'." Proximity ordering destroys that spatial memory.
- **Prefix-free tree** (Vimium): optimal for large target counts, but labels shift unpredictably as count changes. Complexity not justified for typical target counts (<20 in a terminal viewport).

---

## 4. Visual Design

Semi-transparent backdrop overlay for figure/ground separation. Canvas-rendered labels at match start positions. Action hint bar at the bottom showing available actions for the current target type.

Theme tokens (added to `MyttyTheme.swift`):

| Token | Purpose |
|-------|---------|
| `hintsBackdrop` | Dim overlay, theme-adaptive opacity |
| `hintLabelBackground` | Label background (high contrast) |
| `hintLabelForeground` | Label text |

Overlay view hierarchy:

```
HintsOverlayView
  ZStack {
    MyttyTheme.hintsBackdrop       // dim layer (single Color view)
    Canvas { ... }                  // batch-rendered labels
    VStack {
      Spacer()
      HStack { ... }               // action bar: "Return copy  Shift open  Ctrl paste"
    }
  }
```

Labels overlay the start of matched text, covering the first N characters (where N is label length). Canvas rendering follows the `SearchHighlightView` pattern: filled rects for backgrounds, then `context.draw(Text(...))` for label text. This is O(1) SwiftUI views regardless of target count. Label text uses the system monospace font at the terminal's cell height, bold weight. This ensures labels align with terminal grid cells.

When two labels would overlap horizontally (adjacent matches on the same line), the second label is offset downward by one cell height. If vertical space is also constrained, the lower-priority label (further from top-left) is hidden.

For the chrome provider, the overlay is rendered in ContentView (not in PaneView) so labels can appear on sidebar items and tab bar items. The ContentView chrome overlay covers the entire window (including the terminal area) so pane labels render correctly over pane content. This is distinct from the terminal-provider overlay in PaneView, which only covers the active pane.

HintsModeManager is passed from ContentView through PaneView to HintsOverlayView as a direct parameter, matching the CopyModeOverlay pattern.

---

## 5. Key Handling

Design goal: 2 keystrokes from activation to action for single-character labels (activate + label character).

`HintsModeManager` is added to the `modalKeyHandler` chain in ContentView, after `windowModeManager`:

```swift
TerminalSurfaceView.modalKeyHandler = { [self] event in
    if whichKeyManager.handleKeyDown(event) == nil { return nil }
    if copyModeManager.handleKeyDown(event) == nil { return nil }
    if windowModeManager.handleKeyDown(event) == nil { return nil }
    if hintsModeManager.handleKeyDown(event) == nil { return nil }
    return event
}
```

Hints mode is last in the chain. Since mutual exclusion ensures only one modal is active at a time, ordering only matters for the degenerate case where deactivation fails. Last position is safest: it cannot accidentally consume keys meant for other modes.

Activating hints mode deactivates copy mode, window mode, and which-key. Activating copy mode, window mode, or which-key deactivates hints mode. Only one modal mode is active at a time.

Only one provider is active at a time. Activating terminal hints while chrome hints are active (or vice versa) replaces the current provider and re-labels.

Mutual deactivation happens in the ContentView handler (`handleHintsMode()`), not inside HintsModeManager. The handler holds references to all managers.

Activation flow: keybinding triggers `handleHintsMode()` in ContentView (Notifications & Handlers extension). The handler deactivates other modal modes, constructs a `TerminalHintTargetProvider` with a line-reader closure from the active pane's surface and `HintsGeometry` from the pane's grid metrics, then calls `hintsModeManager.activate(provider:geometry:)`. The manager calls `provider.targets(in: geometry)`, runs `assignLabels`, and transitions to `.active`.

`KeySequenceManager` runs separately inside `TerminalSurfaceView.keyDown` (via `keyDispatch`), after the `modalKeyHandler` closure. When hints mode is active, key sequences are not processed because `modalKeyHandler` consumes the event first.

When active, hints mode consumes all key events. Special keys:

- **Esc**: cancel hints mode, return to normal
- **Backspace**: undo last typed character (revert to previous candidate set)

Label characters narrow candidates. When exactly one candidate remains, the action executes immediately.

Modifier keys at the time of the final label keystroke determine the action:

| Modifier | Action |
|----------|--------|
| (none) | Default action for the target type |
| Shift | `open` (URLs, paths) or `close` (chrome targets) |
| Ctrl | `paste` into terminal |

Modifier-to-action mappings are hardcoded at launch. Three fixed modifiers match the ecosystem convention (tmux-fingers, tmux-thumbs, Kitty). A `[hints.actions]` config table can be added if users request custom mappings.

Hints mode auto-exits after action execution. In `--multiple` mode (IPC only), the mode stays active after selection and re-labels remaining targets.

In `--multiple` mode, labels are re-assigned after each selection. The remaining targets are re-labeled from the start of the alphabet, so labels shift between selections. This is a known trade-off: batch selection prioritizes coverage over label stability.

When the provider returns zero targets, hints mode shows a brief "No matches" message in the action bar area and auto-exits after 1 second or on any keypress.

Hints mode auto-cancels when the viewport changes (scroll, new output). The manager registers a viewport-change callback (or observes the surface's scroll state) and calls `deactivate()` on any change. Re-scanning on every scroll would be expensive and confusing (labels shifting mid-selection). Cancellation is the simpler, safer behavior.

Window resize invalidates all label positions. Hints mode deactivates on resize via `.onChange(of: geometry)` in the overlay view.

Tab or session switch deactivates hints mode. ContentView observes `store.activeSession?.activeTab?.id` and calls `hintsModeManager.deactivate()` on change.

Post-activation type filtering (e.g., pressing a key to show only URLs) is deferred to Phase 5b-4. Users can pre-filter by type via IPC (`hints.activate` with a `--type` flag, Phase 5b-4) or by disabling types in config.

---

## 6. Config

```toml
[hints]
alphabet = "asdfghjkl"
types = ["url", "path", "hash", "ip", "linenum"]
# Phase 5b-4: custom-patterns = ["regex1", "regex2"]

[keybindings]
hints-mode = "cmd+shift+h"
chrome-hints-mode = "cmd+shift+g"
```

Esc (cancel) and Backspace (undo) are hardcoded. A `[keybindings.hints-mode]` section can be added later if configurability is needed.

Parsed into `HintsConfig` (nested struct on `MyttyConfig`):

```swift
struct HintsConfig {
    var alphabet: String = "asdfghjkl"
    var types: Set<TerminalMatchType> = Set(TerminalMatchType.allCases)
}
```

Alphabet characters are reserved within hints mode and must not overlap with any future `[keybindings.hints-mode]` bindings.

If Phase 5b-4 (user regex) requires per-type config (custom regex per type, per-type default actions), migrate from the flat `types` array to `[[hints.type]]` array-of-tables.

`types` controls which built-in patterns are active. All enabled by default. Removing a type from the array disables that pattern.

`alphabet` sets the label character pool. Users on Colemak or Dvorak can set their own home-row characters. Alphabet must contain at least 2 unique characters. `MyttyConfig.load()` falls back to the default (`asdfghjkl`) if the value is empty, has fewer than 2 characters, or contains duplicates after deduplication.

Config is parsed by `MyttyConfig.swift` and reloaded on file save, following the existing pattern.

---

## 7. IPC

JSON-RPC methods (noun.verb format):

| Method | Params | Description |
|--------|--------|-------------|
| `hints.activate` | (none) | Activate terminal hints mode on the focused pane |
| `hints.activate-chrome` | (none) | Activate chrome hints on the window |
| `hints.cancel` | (none) | Cancel hints mode (deferred to 5b-4) |

### Design Rationale: Activation-Only IPC

`hints.activate` and `hints.activate-chrome` are activation-only methods: they enter hints mode but don't select a target. This breaks the pattern of other IPC methods (`pane.zoom`, `tab.rotate`) which are complete, atomic operations. The exception is justified by a specific use case:

**Cross-app trigger**: A user in another app (browser, editor) sees a URL in the terminal and wants to act on it. Their external hotkey daemon (skhd, Hammerspoon) calls `mytty-cli hints activate`. The method forefronts Mytty and enters hints mode in one call, collapsing "focus app + enter mode" into a single operation. The in-app keybinding can only do the second step.

The method's contract is "foreground the app and enter hints mode," not "select a hint target." The state change (app foregrounded, labels displayed, key handling switched) is observable and complete for this use case.

**Why not keystroke synthesis?** External hotkey daemons can synthesize the in-app keybinding via CGEvent, but this fails under macOS secure input (expanded in macOS 14+), requires accessibility permissions, and has race conditions when switching from apps that hold secure input. IPC over the Unix socket is reliable regardless of window server state.

**Why not copy-mode/window-mode IPC?** Those modes lack the cross-app trigger use case; they're only useful when the user is already in Mytty. Hints is different because the user sees terminal content from another app and wants to act on it.

**Future extensions**: `--label` (activate and select in one call) and `--query` (filter targets before showing labels) would make hints IPC a full automation primitive. These are deferred to Phase 5b-4.

Three files must stay in sync per the IPC rules:

1. `MyttyShared/MyttyServiceProtocol.swift` (protocol declaration)
2. `Mytty/Services/IPCService.swift` (implementation)
3. `Mytty/Services/IPCListener.swift` (dispatch case)

CLI commands in `MyttyCLI/Commands/` wrap these methods.

IPC activation posts a notification handled by ContentView's existing `handleHintsMode()` / `handleChromeHintsMode()`. This reuses the full activation path (geometry calculation, provider construction, label assignment) without duplicating logic in IPCService.

---

## 8. Entry Points and Wiring

New files:

| File | Purpose |
|------|---------|
| `Mytty/App/HintsModeManager.swift` | Modal manager, state machine, key handling |
| `Mytty/Models/HintTarget.swift` | Protocol and type definitions from section 1 |
| `Mytty/Models/TerminalHintTargetProvider.swift` | Terminal text scanning and regex matching |
| `Mytty/Models/ChromeHintTargetProvider.swift` | Chrome element scanning from SessionStore |
| `Mytty/Models/LabelAssigner.swift` | Label assignment algorithm |
| `Mytty/Views/Hints/HintsOverlayView.swift` | Overlay rendering (backdrop, canvas, action bar) |
| `MyttyCLI/Commands/HintsCommand.swift` | CLI commands for hints |

Modified files:

| File | Changes |
|------|---------|
| `Mytty/App/ContentView.swift` | Add HintsModeManager to modalKeyHandler chain, add overlay, add `hintsModeManager.deactivate()` to `onDisappear`, add `"hints-mode"` and `"chrome-hints-mode"` cases to `dispatchSequenceAction`. No tab-level state cleanup needed (hints state lives only on HintsModeManager, unlike window mode which has tab-level windowModeState). |
| `Mytty/App/TerminalCommands.swift` | Add `hintsMode()` and `chromeHintsMode()` closure properties |
| `Mytty/App/MyttyApp.swift` | Register `.keyboardShortcut(from:)` for `hints-mode` and `chrome-hints-mode` actions |
| `Mytty/App/MyttyTheme.swift` | Add hint-related color tokens |
| `Mytty/Config/MyttyConfig.swift` | Parse `[hints]` section |
| `MyttyShared/MyttyServiceProtocol.swift` | Add IPC method declarations |
| `Mytty/Services/IPCService.swift` | Implement IPC methods |
| `Mytty/Services/IPCListener.swift` | Dispatch IPC methods |
| `Mytty/Views/Terminal/PaneView.swift` | Add HintsOverlayView for terminal provider, pass HintsModeManager as parameter |
| `Mytty/Config/KeybindingStore.swift` | Add `hints-mode` and `chrome-hints-mode` to `defaultBindings` with default triggers |

---

## 9. Phasing

- **Phase 5b-1**: Core types, label algorithm, terminal provider (all five built-in types: url, path, hash, ip, linenum), overlay in PaneView, key handling, config. No IPC, no chrome provider.
- **Phase 5b-2**: Chrome provider, second overlay instance in ContentView for chrome targets.
- **Phase 5b-3**: IPC methods (`hints.activate`, `hints.activate-chrome`), CLI commands. Activation-only; `--label`/`--query` deferred to 5b-4.
- **Phase 5b-4** (future): `--label` and `--query` IPC flags for full programmatic selection. User-configurable regex patterns (`custom-patterns`).

---

## 10. Testing

New test files:

| File | Category | Notes |
|------|----------|-------|
| `MyttyTests/Models/LabelAssignerTests.swift` | Model unit test | Pure function, test with synthetic targets |
| `MyttyTests/Models/TerminalHintTargetProviderTests.swift` | Model unit test | Inject line-reader closure with test strings |
| `MyttyTests/Models/ChromeHintTargetProviderTests.swift` | Model unit test | Real SessionStore, synthetic HintsGeometry |
| `MyttyTests/App/HintsModeManagerTests.swift` | Manager test | State transitions via handleKeyDown with synthetic NSEvents |

Existing test file additions:

| File | Addition |
|------|----------|
| `MyttyTests/App/ContentViewHandlerTests.swift` | `handleHintsMode` and `handleChromeHints` handler tests |

Views (HintsOverlayView): manual testing only.

Viewport-change cancellation is signaled via an injected closure (not by observing ghostty_surface_t directly), keeping the manager testable without a real surface.

---

## 11. Alternatives Rejected

**Nesting hints inside copy mode.** Hints as a sub-mode of copy mode would reuse existing infrastructure and reduce the learning surface. Rejected because it adds a mandatory extra keystroke to every hints invocation (enter copy mode, then trigger hints). Hints mode's value is speed. A dedicated keybinding is one keystroke to activate.

**User regex at launch.** Configurable regex patterns from day one would cover edge cases (Kubernetes IDs, Terraform resources). Rejected because the built-in types (url, path, hash, ip, linenum) cover common git and development workflows. The architecture supports adding user regex as a Phase 2 feature without restructuring. Users who need arbitrary text selection can use copy mode as a workaround.

**Action picker after selection.** A picker overlay after label selection would be more discoverable and extensible. Rejected because it adds a keystroke between selection and action execution. Modifier keys (Shift, Ctrl) provide up to 4 quick actions, which matches the ecosystem (Kitty, tmux-fingers both cap at 4). The action hint bar at the bottom provides discoverability without interaction cost.

**Proximity-based label ordering.** See section 3.

**Prefix-free tree algorithm.** See section 3.

**Mixed single/two-char labels.** The initial design assigned single-char labels to the first N targets and two-char to the rest. This creates prefix ambiguity: typing `a` could select target `a` or begin the two-char label `as`. Rejected in favor of uniform-length labels per activation.

## Related

- [Hint Bar](hint-bar.md): hint bar hides when hints mode is active
