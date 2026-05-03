# Hint Bar Spec

Created: 2026-04-27
Updated: 2026-05-02
Status: Accepted

## Problem

Mytty has modal features (which-key, window mode, copy mode, key sequences) but no
ambient signal telling users they exist or how to open them. Which-key solves discovery
*within* modes, but you need to know Ctrl+Space to open which-key in the first place.
This is a bootstrap problem: the discovery tool itself is undiscoverable.

## Target user

Someone who's used Mytty for a week, knows splits and tabs, but hasn't found window
mode or copy mode yet. Power users will turn it off. Day-one beginners need a tutorial,
not a hint bar.

## What

A persistent, single-line bar at the bottom of the terminal area showing mode entry
points with their configured keybindings. Example:

    ⌃␣ keys   ⌃W window   ⌘⇧C copy   ⌘⇧H hints

If the user has a leader key configured, include the first leader (by display label
sort order) before the mode items:

    ⌃A leader   ⌃␣ keys   ⌃W window   ⌘⇧C copy   ⌘⇧H hints

Shows the fixed set of mode entry points listed below. If a trigger is unbound, omit
that item. If no items have bound triggers, hide the hint bar entirely.

## Items (in order)

1. Leader key: first key from `keybindingStore.sequenceTrie.children.keys` sorted by
   `displayLabel`. Label: "leader". Omit if `sequenceTrie.children` is empty.
2. `which-key`: label "keys"
3. `window-mode`: label "window"
4. `copy-mode`: label "copy"
5. `hints-mode`: label "hints"

Triggers resolved via `keybindingStore.trigger(for:in:.global)` for items 2-5.
Leader trigger read from `keybindingStore.sequenceTrie.children.keys`.

## What it does NOT show

- Common actions (split, new tab) already in the menu bar
- Mode-specific actions (those are in the existing overlays)
- Context-sensitive content that changes per mode

## Design rationale

### Role in the discovery system

The hint bar is the collapsed state of the which-key system, not a separate feature.
Mytty's discovery stack has two layers:

1. **Within modes**: which-key overlay, window mode HUD, copy mode help, hints mode,
   sequence indicator. These are excellent once you're in a mode.
2. **Getting to modes**: the hint bar. It bridges the gap by showing mode entry points.

The hint bar says "these modes exist, here's how to enter them." Once you press a
trigger, the corresponding overlay takes over. The hint bar is a table of contents
for a book that already has good chapters.

### Visual cohesion

The hint bar uses the same visual language as the overlay system (overlayText,
overlayTextMuted tokens) so the transition from hint bar to overlay feels like
expanding a UI element, not switching to a different one.

### Terminal grid impact

The hint bar sits inside the VStack with the tab bar and pane layout. It reduces the
terminal grid by ~1 row (same mechanism as the tab bar), not an overlay that obscures
content. The terminal reflows to fit the smaller grid. No running commands or user
input are obscured.

### Prior art

No terminal emulator has a persistent keybinding hint bar. The closest prior art is
Zellij (a multiplexer), which started with a 2-line bar, evolved to a 1-line compact
variant, and lets power users replace it entirely. nano uses a similar pattern with
its bottom shortcut bar (toggleable via `set nohelp`). Both validate that a toggleable
persistent bar works for keyboard-driven terminal tools.

Research: `/tmp/ai-research-hint-bar-prior-art.md`

## Placement

Inside the `VStack(spacing: 0)` in `terminalArea` that contains the tab bar and pane
layout. After the `PaneLayoutView`/`PaneView` conditional block, before the VStack
closing brace.

Considered alternatives:
- Bottom of sidebar: fails when sidebar is hidden (common default)
- Tab bar area: gets crowded, tab bar can be hidden
- Floating badge: another overlay to manage, potential overlap

Bottom-of-window wins because it's always visible, familiar (vim statusline, VS Code),
and the existing overlays naturally replace it when active.

## Behavior

- Visible when `isAnyModalActive` is false and no key sequence is pending
  (`keySequenceManager.pendingDisplay.isEmpty`)
- Hidden when any modal is active or a key sequence is pending (the
  SequenceIndicatorView overlays the bottom of the pane and would collide)
- `showHintBar` bool stored on `PanelState` (matching the `showHints` pattern),
  set in `applyConfig(_:)`. Hint bar items computed from the config's
  `keybindingStore` in `applyConfig` and stored as `@State` on ContentView.
- Toggleable via top-level `show-hint-bar` config key, default `true`.
  Parsed in `MyttyConfig.parse()` as a top-level bool (not under a section table).
  Property: `MyttyConfig.showHintBar: Bool = true`.

## Implementation sketch

- New view: `HintBarView.swift` in `Views/Chrome/` (create directory)
- Input: `[(trigger: String, label: String)]` array, renders as HStack. The view is a
  pure renderer; the caller (ContentView) resolves triggers and passes tuples.
- Placed in ContentView's `terminalArea` VStack, after the pane layout
- Gated on `!isAnyModalActive && keySequenceManager.pendingDisplay.isEmpty && panelState.showHintBar`
- Also gated on `!items.isEmpty` to avoid showing an empty bar
- Font: system default (not monospaced, not scaled to cellHeight; this is chrome)
- Colors: overlay family tokens. `overlayText` for triggers, `overlayTextMuted` for
  labels, new `hintBarBackground` token (`bg.opacity(0.4)`) for background.
- Vertical cost: ~20px
- No IPC method needed. The hint bar is config-driven with no runtime state. The
  `show-hint-bar` toggle is read from the config file, not an IPC-mutable property.

## Risks

- Scope creep into a full status bar (git branch, process name). Guard: the view takes
  a list of tuples and renders them. Nothing else.
- Permanent vertical space cost. Mitigation: config toggle. Future evolution: adaptive
  hide after the user has triggered each mode (requires state tracking, out of scope).

## Related

- [Phase 5b: Hints Mode](phase5b-hints-mode.md): hint bar hides when hints mode is active
