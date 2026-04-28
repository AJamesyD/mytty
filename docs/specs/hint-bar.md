# Hint Bar Spec

Created: 2026-04-27
Status: Proposed

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

A persistent, single-line bar at the bottom of the window showing mode entry points
with their configured keybindings. Example:

    ctrl+space keys   ctrl+w window   cmd+shift+c copy

If the user has a leader key configured, include it:

    ctrl+a leader   ctrl+space keys   ctrl+w window   cmd+shift+c copy

Three to five items max. Reads triggers from KeybindingStore so it reflects user config.

## What it does NOT show

- Common actions (split, new tab) already in the menu bar
- Mode-specific actions (those are in the existing overlays)
- Context-sensitive content that changes per mode

## Placement

Bottom of window, status bar style.

Considered alternatives:
- Bottom of sidebar: fails when sidebar is hidden (common default)
- Tab bar area: gets crowded, tab bar can be hidden
- Floating badge: another overlay to manage, potential overlap

Bottom-of-window wins because it's always visible, familiar (vim statusline, VS Code),
and the existing bottom overlays (which-key, window mode) naturally replace it when
active.

## Behavior

- Visible when no modal overlay is active
- Hidden when any modal overlay is active (which-key, window mode, copy mode, hints)
- Reads keybindings from KeybindingStore at config load time
- Toggleable via `show-hint-bar` config key, default `true`

## Implementation sketch

- New view: `HintBarView.swift` in `Views/Chrome/`
- Input: `[(key: String, label: String)]` array, renders as HStack
- Placed in ContentView's `terminalArea`, below the pane layout
- Uses `isAnyModalActive` to hide/show
- Font: system default (not monospaced, not scaled to cellHeight; this is chrome)
- Colors: MyttyTheme tokens
- Vertical cost: ~20px

## Risks

- Scope creep into a full status bar (git branch, process name). Guard: the view takes
  a list of tuples and renders them. Nothing else.
- Permanent vertical space cost. Mitigation: config toggle.

## Related

- [Phase 5b: Hints Mode](phase5b-hints-mode.md): hint bar hides when hints mode is active
