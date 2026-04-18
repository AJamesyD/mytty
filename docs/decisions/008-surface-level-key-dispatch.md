# ADR-008: Surface-Level Key Dispatch

Status: accepted
Date: 2026-04-17

## Context

Mytty uses five independent NSEvent keyDown monitors to intercept keys
before they reach the terminal surface. Each manager (PaneNavigationManager,
WindowModeManager, CopyModeManager, WhichKeyManager, session manager)
installs its own monitor. No other terminal emulator uses this pattern.
Ghostty, Kitty, Alacritty, and WezTerm all check bindings at a single
point after the key reaches the terminal layer.

This architecture causes a class of bugs where a monitor consumes a key
that should have reached the terminal (e.g., the consumed_mods bug fixed
2026-04-16). Adding more monitors for Phase 4f-3 (key tables) would
increase the surface area for these bugs.

Two options were evaluated:

**Option A (incremental):** Consolidate five monitors into one with an
explicit dispatch chain. Each manager keeps its handler logic. Lower risk
per change, but the dispatch still happens before the surface view.

**Option B (full rework):** Remove all NSEvent key monitors. Let every key
reach `TerminalSurfaceView.keyDown`, then use `ghostty_surface_key_is_binding()`
to decide whether to execute a Mytty action or pass to libghostty.

## Decision

Option B: move all key binding dispatch into the surface keyDown path.

Option A cannot support Phase 4f-3 key tables correctly.
`activate_key_table` is an action dispatched by `ghostty_surface_key()`,
which only runs after NSEvent monitors have already intercepted. Under
Option A, the consolidated monitor would need to duplicate key table
activation logic outside the Ghostty key processing pipeline.

`ghostty_surface_key_is_binding()` is already available in the C API and
used in two places (PaneNavigationManager, KeySequenceManager).

## Implementation

Two phases, each independently shippable:

**Phase 1:** Move always-on dispatch (PaneNavigationManager, KeySequenceManager)
into `TerminalSurfaceView.keyDown`. Remove the PaneNavigationManager monitor.

**Phase 2:** Move modal dispatch (WindowModeManager, CopyModeManager,
WhichKeyManager, session manager) into the same keyDown path. Remove all
remaining monitors.

Each phase: refactor only (preserve behavior), verify with existing tests,
then run `just ci`.

## Consequences

- Eliminates the "monitor eats a key it shouldn't" bug class
- Phase 4f-3 key tables integrate naturally into surface-level dispatch
- Touches every key handler manager (high blast radius, mitigated by phasing)
- Modal managers (CopyMode, WindowMode, WhichKey) intercept keys that are
  not Ghostty bindings. The keyDown path needs a Mytty-specific modal
  dispatch layer before the `ghostty_surface_key_is_binding()` check. This
  is a two-layer dispatch (Mytty modals, then Ghostty bindings), not a
  pure Ghostty model.
- Testing gap: existing tests use synthetic NSEvents on monitors. Phase 1
  must verify that the same handler methods work when called from keyDown.

## Reversal conditions

- `ghostty_surface_key_is_binding()` cannot distinguish key table context
- Surface keyDown dispatch breaks IME or dead key input
- The dispatch preamble grows beyond a manageable size (>30 lines)

## Outcome

**Phase 1: complete.** PaneNavigationManager and KeySequenceManager dispatch
from `TerminalSurfaceView.keyDown` via a static `keyDispatch` closure. The
PaneNavigationManager NSEvent monitor is removed.

**Phase 2: complete.** Modal dispatch (session manager, which-key, copy mode,
window mode) moved from `ModalKeyDispatcher` (NSEvent monitor) into a second
static closure, `modalKeyHandler`, on `TerminalSurfaceView`. Called at the
top of `keyDown`, before `keyDispatch`. `ModalKeyDispatcher.swift` deleted.

### Architecture (single dispatch point)

`TerminalSurfaceView.keyDown(with:)` in
`Mytty/Views/Terminal/TerminalSurfaceView.swift`:

1. `Self.modalKeyHandler` (set by ContentView): chains sessionManager,
   whichKey, copyMode, windowMode. Returns nil to consume.
2. `Self.keyDispatch` (set by PaneNavigationManager): delegates to
   KeySequenceManager, then checks navigation bindings via
   `ghostty_surface_key_is_binding()`. Returns nil to consume.
3. `interpretKeyEvents` then `ghostty_surface_key()`.

No NSEvent key monitors remain. The only NSEvent monitor is the dropdown
terminal global hotkey (GlobalHotkeyMonitor), which is app-wide, not
per-surface.

The static closure pattern keeps the surface view decoupled from modal
state: it calls closures without knowing what modals exist. ContentView
owns the closure lifecycle (set in onAppear, nil in onDisappear).