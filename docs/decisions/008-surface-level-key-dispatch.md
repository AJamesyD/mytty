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
