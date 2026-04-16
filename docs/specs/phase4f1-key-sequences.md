# Phase 4f-1: Key Sequences

Mistty macOS terminal emulator, libghostty backend.

**Goal:** Support multi-key bindings (e.g., `ctrl+a>h`) in config. Parse `>` as a sequence separator in `TriggerParser`. Add a sequence state machine that tracks pending leaders and dispatches the final action. Timeout after 1s (configurable). Visual indicator for pending sequences.

**Date:** 2026-04-16

**Research:** `/tmp/ai-research-key-sequences.md`

---

## 1. Overview

Key sequences let users bind actions to a chain of keypresses separated by `>`. The first key in the chain is the "leader." Pressing the leader enters a pending state; subsequent keys walk the sequence tree until a leaf action is reached or the sequence is cancelled.

Config syntax:

```toml
[keybindings]
navigate-left = "ctrl+a>h"
navigate-right = "ctrl+a>l"
navigate-up = "ctrl+a>k"
navigate-down = "ctrl+a>j"
new-tab = "ctrl+a>c"
```

These are user overrides. The compiled-in defaults remain single-key bindings (`unconsumed:ctrl+h`, `cmd+t`, etc.). Sequences are opt-in for users who want a tmux/vim-style leader key workflow.

### Prior art

| Emulator | Syntax | Timeout | Invalid key behavior |
|----------|--------|---------|---------------------|
| Ghostty | `ctrl+a>n=new_tab` | None (waits indefinitely) | Flushes all buffered keys to terminal |
| Kitty | `ctrl+f>2 set_font_size 20` | Configurable (`map_timeout`, default 0 = off) | Discards buffered keys |
| tmux | Prefix key + one key | None for non-repeat bindings | Ignores invalid key, returns to root |

Mistty follows Kitty's timeout model (configurable, default 1s) and Kitty's discard-on-invalid behavior. Flushing buffered leader keys to the terminal after a timeout or invalid key is confusing: the user waited too long or pressed the wrong key, and the leader suddenly appears in their shell.

## 2. Config syntax

Extend the existing trigger string format (Phase 4a, section 3) with `>` as a sequence separator. Each segment between `>` characters is a standard trigger (modifiers + key).

```
sequence    = trigger (">" trigger)*
trigger     = [prefix ":"] [modifiers "+"] key
```

The `>` separator is only valid in the `[keybindings]` (global) section. Modal sections (`[keybindings.window-mode]`, `[keybindings.copy-mode]`) do not support sequences because those modes already have their own single-key dispatch.

Examples:

```toml
[keybindings]
# tmux-style leader
navigate-left = "ctrl+a>h"
navigate-right = "ctrl+a>l"
navigate-up = "ctrl+a>k"
navigate-down = "ctrl+a>j"
new-tab = "ctrl+a>c"
close-pane = "ctrl+a>x"
split-horizontal = "ctrl+a>d"
split-vertical = "ctrl+a>shift+d"

# Deeper sequences
toggle-sidebar = "ctrl+a>g>s"

# unconsumed: applies to the whole binding
navigate-left = "unconsumed:ctrl+a>h"
```

Multi-bind arrays work with sequences:

```toml
new-tab = ["cmd+t", "ctrl+a>c"]
```

## 3. Parsing

### TriggerParser changes

`TriggerParser.parse(_:)` currently returns a single `KeyboardTrigger`. Add a new method `TriggerParser.parseSequence(_:)` that returns a `KeySequence`.

```swift
struct KeySequence: Sendable, Equatable, Hashable {
    var prefix: TriggerPrefix?
    var triggers: [KeyboardTrigger]
}
```

Parsing rules:

1. Split the input on `>` (after extracting the optional `unconsumed:` prefix).
2. Parse each segment as a `KeyboardTrigger` (reusing the existing `parse` logic, but without prefix handling per-segment).
3. The `unconsumed:` prefix, if present, is stored on the `KeySequence`, not on individual triggers.
4. A single-key binding produces a `KeySequence` with one trigger. All bindings are sequences; single-key is the degenerate case.

The existing `TriggerParser.parse(_:)` method remains for callers that expect a single `KeyboardTrigger`. `parseSequence` is the new primary entry point for config loading.

New error case:

```swift
case sequenceTooDeep(Int)  // depth exceeds max (5)
```

### Validation

- Maximum sequence depth: 5. Reject deeper sequences at parse time with `sequenceTooDeep`.
- Empty segments (e.g., `ctrl+a>>h`) are a parse error (existing `TriggerParseError.empty`).
- Sequences in modal sections (`window-mode`, `copy-mode`) produce a warning and are ignored.

## 4. Storage

### KeybindingStore changes

The current `KeybindingStore` maps `[BindingMode: [String: KeyboardTrigger]]` (action name to single trigger). This flat map cannot represent sequence trees.

Add a trie structure for sequence lookup:

```swift
struct SequenceTrieNode: Sendable, Equatable {
    let children: [KeyboardTrigger: SequenceTrieNode]
    let action: String?
    let isUnconsumed: Bool
}
```

The trie is immutable after construction. `KeybindingStore.build()` constructs it using a mutable builder, then freezes it into the struct form.

`KeybindingStore` gains:

```swift
private(set) var sequenceTrie: SequenceTrieNode = SequenceTrieNode()
```

### Build pipeline changes

Currently, `MisttyConfig` parses each trigger string into a `KeyboardTrigger` and passes `[BindingMode: [String: KeyboardTrigger]]` to `KeybindingStore.build()`. With sequences:

1. `MisttyConfig` parses each trigger string using `TriggerParser.parseSequence()` instead of `TriggerParser.parse()`, producing `KeySequence` values.
2. For single-key sequences (length 1), extract the `KeyboardTrigger` and store in the existing `[String: KeyboardTrigger]` map (no change to the flat binding path).
3. For multi-key sequences (length > 1), store in a new `[String: KeySequence]` map passed to `build()`.
4. `KeybindingStore.build()` gains a new parameter: `sequenceOverrides: [String: KeySequence]`. It builds the trie from these, then checks for leader-shadows-standalone conflicts against the flat bindings.

This keeps the existing `build()` signature backward-compatible (the new parameter has a default empty value).

1. For each global binding, call `parseSequence` on the trigger string.
2. If the sequence has length 1, store it in the existing flat `bindings` map (no change).
3. If the sequence has length > 1, insert it into the trie. Each trigger in the sequence creates or traverses a child node. The final node stores the action name.

### Leader-shadows-standalone detection

After building the trie, check: if a trigger appears as both a trie root key (leader) and a key in the flat `bindings[.global]` map, the standalone binding is unreachable. Add a warning:

```
"'ctrl+a' is a sequence leader and also bound to 'some-action'; the standalone binding is unreachable"
```

The standalone binding is removed from the flat map. The leader takes precedence.

## 5. State machine

New enum in `Mistty/App/KeySequenceManager.swift`:

```swift
enum KeySequenceState {
    case idle
    case pending(node: SequenceTrieNode, keys: [KeyboardTrigger])
}
```

State transitions:

| Current | Event | Next | Side effect |
|---------|-------|------|-------------|
| `idle` | Key matches trie root (leader) | `pending(child, [leader])` | Consume event, start timeout, show indicator |
| `pending` | Key matches child node with action (leaf) | `idle` | Execute action, cancel timeout, hide indicator |
| `pending` | Key matches child node without action (intermediate) | `pending(deeper child, keys + [key])` | Consume event, reset timeout, update indicator |
| `pending` | Key does not match any child | `idle` | Discard all buffered keys, cancel timeout, hide indicator |
| `pending` | Escape pressed | `idle` | Discard all buffered keys, cancel timeout, hide indicator |
| `pending` | Timeout fires | `idle` | Discard all buffered keys, hide indicator |
| `pending` | Modifier-only key (bare Shift, Ctrl, etc.) | `pending` (unchanged) | Ignore, do not reset timeout |

Modifier-only events are ignored so that `ctrl+a>ctrl+b` works: the user releases `a`, presses `ctrl` alone (modifier-only event), then presses `b` while holding `ctrl`.

## 6. Key dispatch integration

`KeySequenceManager` does not install its own NSEvent monitor. Instead, it exposes a `handleKeyDown(_: NSEvent) -> NSEvent?` method that is called by `PaneNavigationManager` at the top of its existing monitor callback, before any navigation logic.

### Event flow

```
NSEvent (keyDown)
  -> PaneNavigationManager monitor
    -> KeySequenceManager.handleKeyDown (sequences)
      -> if consumed: return nil
      -> if not consumed: PaneNavigationManager continues with navigation logic
        -> WhichKeyManager (which-key overlay)
          -> libghostty (terminal)
```

`PaneNavigationManager` already owns the local key monitor. Adding sequence handling at the top of its callback avoids undefined monitor ordering. `KeySequenceManager` returns `nil` to consume the event (leader matched or sequence advanced) or returns the event unchanged to let navigation proceed.

### Integration point

`KeySequenceManager` is instantiated as `@State` on `ContentView`, similar to `PaneNavigationManager`. It is passed to `PaneNavigationManager` during activation. `PaneNavigationManager.handleKeyDown` calls `sequenceManager.handleKeyDown(event)` first; if that returns `nil`, the event is consumed.

When a sequence completes, `KeySequenceManager` calls a dispatch closure `(String) -> Void` that maps action names to the same handlers used by single-key bindings. This closure is provided during activation, keeping the manager decoupled from specific action implementations.

### unconsumed: handling

For sequences with the `unconsumed:` prefix, the check happens on the final key only. The leader is always consumed (entering sequence mode requires it). When the final key is reached and `isUnconsumed` is true, call `ghostty_surface_key_is_binding` for that key. If libghostty claims the key, discard the sequence (do not execute the action).

### Mode guards

Sequences are only active in normal mode. `KeySequenceManager.handleKeyDown` returns the event unmodified (passes through) when:

- Window mode is active (`tab.isWindowModeActive`)
- Copy mode is active (`tab.isCopyModeActive`)

If a sequence is pending when the user enters window mode or copy mode, the sequence is cancelled (transition to `idle`, discard buffered keys).

## 7. Timeout

Default: 1 second. Configurable:

```toml
[keybindings]
sequence-timeout = 1.0
```

Value is in seconds. Minimum: 0.1. Maximum: 10.0. A value of 0 disables the timeout (wait indefinitely, like Ghostty).

Implementation: a `Task` that sleeps for the configured duration, similar to `WhichKeyManager.resetTimeout()`. The timer resets on each valid key in a multi-level sequence (e.g., pressing the second key in a 3-key sequence resets the 1s timer).

On timeout: transition to `idle`, discard buffered keys, hide the visual indicator. Do not flush keys to the terminal.

`KeySequenceManager` reads the timeout value from `KeybindingStore` (parsed from config by `MisttyConfig`).

## 8. Visual indicator

When a sequence is pending, show a floating text overlay near the bottom of the active pane displaying the pressed leader key(s) and an animated ellipsis.

Example: after pressing `ctrl+a`, the overlay shows `ctrl+a …`. After pressing `ctrl+a>g` in a 3-key sequence, it shows `ctrl+a > g …`.

### Implementation

A new `SequenceIndicatorView` (SwiftUI) that reads from `KeySequenceManager.pendingDisplay` (a stored property on the `@Observable` class, empty string when idle). The view:

- Appears with a spring animation (0.3s response, 0.8 damping)
- Uses `MisttyTheme` tokens for colors (no `Color` literals)
- Positioned at the bottom center of the active pane via `.overlay` on the pane content
- Text only for v1 (no keycap styling)
- Disappears when the sequence completes, is cancelled, or times out

`pendingDisplay` is computed from the `keys` array in the `pending` state, formatted using `TriggerParser.normalize`.

## 9. Which-key integration

When a sequence is pending and a short delay elapses (500ms, separate from the normal which-key 3s delay), show the available continuations in the which-key overlay. The shorter delay is appropriate because the user has already pressed a leader key and is waiting for guidance, unlike the normal which-key flow where the user may just be pausing.

Note: if `sequence-timeout` is less than 500ms, the which-key overlay will not appear (the sequence times out first). This is acceptable: very short timeouts indicate an expert user who doesn't need the overlay.

### Mechanism

`KeySequenceManager` exposes `pendingContinuations: [WhichKeyBinding]?`, computed from the current trie node's children. Each child trigger maps to a `WhichKeyBinding`:

- If the child is a leaf (has an action), it becomes a `.command` binding.
- If the child is an intermediate node (has children), it becomes a `.group` binding.

`WhichKeyManager` gains a method `showContinuations(_: [WhichKeyBinding])` that displays the overlay without installing its own key monitor. During an active sequence, which-key is display-only: `KeySequenceManager` owns all key dispatch. `WhichKeyManager` does not consume events while `KeySequenceManager` is in `pending` state.

When the sequence completes or is cancelled, `KeySequenceManager` calls `WhichKeyManager.deactivate()` to hide the overlay.

### Natural mapping

The sequence trie maps directly to which-key's tree structure. A leader like `ctrl+a` with children `h`, `l`, `k`, `j`, `c` produces a which-key group showing those keys and their action labels. Nested leaders produce nested groups.

## 10. Edge cases

### Leader shadows standalone binding

When a trigger is both a sequence leader and a standalone binding, the leader wins. The standalone binding is unreachable. `KeybindingStore.build()` emits a warning at config load time and removes the standalone binding from the flat map.

### Escape cancels

Escape pressed during a pending sequence discards all buffered keys and returns to `idle`. This is the default behavior. Users can override it by binding `escape` as a continuation in the sequence tree:

```toml
some-action = "ctrl+a>escape"
```

If `escape` is a valid continuation in the current trie node, it is treated as a normal key (not a cancel).

### Modifier-only keys during sequence

Bare modifier presses (Shift, Ctrl, Alt, Cmd without an accompanying key) are ignored during a pending sequence. This allows `ctrl+a>ctrl+b` to work: the `ctrl` keyDown between releasing `a` and pressing `b` does not cancel the sequence. The timeout is not reset by modifier-only events.

### `unconsumed:` on sequences

The `unconsumed:` prefix applies to the final key only. The leader is always consumed (it must be, to enter sequence mode). An `unconsumed:` leader would be contradictory: you cannot both enter sequence mode and pass the key through.

### Sequence depth

`TriggerParser.parseSequence` accepts arbitrary depth. `KeybindingStore.build()` rejects sequences deeper than 5 with a warning (not a hard error; the binding is skipped).

### Window mode and copy mode interaction

Sequences are only active in normal mode. If a sequence is pending when the user enters window mode or copy mode (via a non-sequence binding), the pending sequence is cancelled. Sequences defined in `[keybindings.window-mode]` or `[keybindings.copy-mode]` are rejected with a warning at config load time.

### Rapid typing

If the user types faster than the event loop processes events, each keyDown is still delivered sequentially by AppKit. The state machine processes them in order. No special batching is needed.

### Focus loss during sequence

If the user presses a leader key then switches to another app (Cmd+Tab) or clicks the mouse in the terminal, the pending sequence is cancelled. `KeySequenceManager` observes `NSApplication.didResignActiveNotification` and cancels on that event. Mouse clicks in the terminal (detected via the existing event flow) also cancel a pending sequence.

### Config reload during sequence

If the user edits their config while a sequence is pending, `KeySequenceManager.reloadConfig()` cancels the pending sequence and rebuilds the trie from the new config. This is called from the existing `.configDidChange` notification handler in `ContentView+Handlers`.

### Multiple leaders

Different leaders can coexist. `ctrl+a>h` and `ctrl+b>h` define two independent sequence trees rooted at `ctrl+a` and `ctrl+b`. Pressing `ctrl+a` enters one tree; pressing `ctrl+b` enters the other.

## 11. Files

### New files

| File | Purpose |
|------|---------|
| `Mistty/App/KeySequenceManager.swift` | State machine, NSEvent monitor, timeout, pending display state |
| `Mistty/Views/Terminal/SequenceIndicatorView.swift` | Floating overlay showing pending leader keys |
| `MisttyTests/App/KeySequenceManagerTests.swift` | State machine transitions, timeout, edge cases |
| `MisttyTests/Config/KeySequenceParsingTests.swift` | `parseSequence`, depth validation, `>` splitting |

### Modified files

| File | Changes |
|------|---------|
| `Mistty/Config/TriggerParser.swift` | Add `KeySequence` type, `parseSequence(_:)` method, `sequenceTooDeep` error |
| `Mistty/Config/KeybindingStore.swift` | Add `SequenceTrieNode`, trie construction in `build()`, leader-shadows-standalone detection, `sequence-timeout` storage |
| `Mistty/Config/MisttyConfig.swift` | Parse `sequence-timeout` from `[keybindings]` section |
| `Mistty/App/WhichKeyManager.swift` | Add `showContinuations(_:)` method for display-only mode during sequences |
| `Mistty/App/ContentView.swift` | Add `@State` for `KeySequenceManager`, wire `.overlay` for `SequenceIndicatorView` |
| `Mistty/App/ContentView+Handlers.swift` | Activate/deactivate `KeySequenceManager`, provide action dispatch closure |

## 12. Phasing

### Phase 4f-1a: Parsing and storage

- `KeySequence` type and `TriggerParser.parseSequence(_:)`.
- `SequenceTrieNode` and trie construction in `KeybindingStore.build()`.
- Leader-shadows-standalone warning.
- Depth validation (max 5).
- `sequence-timeout` config parsing.
- Tests for parsing and trie construction.

### Phase 4f-1b: State machine and dispatch

- `KeySequenceManager` with state machine, NSEvent monitor, timeout.
- Integration with `ContentView` (event interception above existing managers).
- Action dispatch via closure.
- `unconsumed:` handling on final key.
- Mode guards (skip in window mode / copy mode).
- Tests for state transitions.

### Phase 4f-1c: Visual feedback

- `SequenceIndicatorView` overlay.
- `pendingDisplay` on `KeySequenceManager`.
- Which-key integration (`showContinuations`).

## 13. Out of scope

| Feature | Reason | Target |
|---------|--------|--------|
| `end_key_sequence` action (flush buffered keys to terminal) | Ghostty-specific; Mistty discards on cancel | Future, if requested |
| Sequences in window mode / copy mode | Those modes have their own dispatch | Not planned |
| `global:` prefix on sequence leaders | Global hotkeys are a separate feature (Phase 4f-2) | Phase 4f-2 |
| Configurable cancel key (replacing Escape) | Escape is overridable by binding it in the sequence tree | Not planned |
| Keycap-styled visual indicator | Text-only for v1 | Future polish |

## 14. Acceptance criteria

1. `TriggerParser.parseSequence("ctrl+a>h")` returns a `KeySequence` with two triggers: `ctrl+a` and `h`.
2. `TriggerParser.parseSequence("ctrl+a>g>s")` returns a `KeySequence` with three triggers.
3. Sequences deeper than 5 are rejected with a `sequenceTooDeep` error.
4. `KeybindingStore.build()` constructs a trie from sequence bindings in the global section.
5. A trigger that is both a sequence leader and a standalone binding produces a warning, and the standalone binding is removed.
6. Pressing a leader key enters `pending` state and consumes the event (key is not sent to the terminal).
7. Pressing a valid continuation in `pending` state either advances to the next level or executes the leaf action.
8. Pressing an invalid key in `pending` state discards the sequence and returns to `idle`.
9. Pressing Escape in `pending` state cancels the sequence (unless Escape is a valid continuation).
10. The sequence times out after the configured duration (default 1s) and discards buffered keys.
11. `sequence-timeout = 0` disables the timeout.
12. Modifier-only key events during a pending sequence are ignored.
13. The visual indicator shows the pressed leader keys with `…` while a sequence is pending.
14. The visual indicator disappears when the sequence completes, is cancelled, or times out.
15. Which-key shows available continuations when its delay elapses during a pending sequence.
16. Which-key does not consume key events during an active sequence.
17. Sequences are inactive during window mode and copy mode.
18. A pending sequence is cancelled when the user enters window mode or copy mode.
19. `unconsumed:` on a sequence applies to the final key only; the leader is always consumed.
20. Single-key bindings (sequences of length 1) continue to work identically to the current behavior.
21. All existing tests pass without modification.
