# Keybinding Discoverability

Date: 2026-05-11

## Problem

Users who discover actions through which-key (Ctrl+Space > t > n for "New Tab")
never learn that a direct shortcut (Cmd+T) exists. No graduation path from
hierarchical navigation to direct shortcuts.

## Proposals (ranked by impact x feasibility)

### 1. Which-Key Ghost Shortcuts (Phase 1, low effort)

Show the direct global shortcut right-aligned and dimmed next to each which-key entry.
Entries without a direct shortcut show nothing, making the ones that do stand out.

```
[n] New Tab                              Cmd+T
[c] Close Tab                          Cmd+Shift+W
[r] Rename Tab
```

Data source: AppAction registry id -> KeybindingStore.trigger(for:in:.global)?.displayLabel
Config: `which-key-show-shortcuts = true`
Implementation: add `shortcut: String?` to WhichKeyAction.command case, thread through buildBindings.

### 2. Command Palette Shortcut Labels (Phase 2, ships with 5f)

Display keybinding right-aligned next to every palette result. VS Code's proven model.
Solves the reverse problem: "I know the action name, what's the key?"
Config: `palette-show-shortcuts = true`

### 3. Post-Action Shortcut Toast (Phase 3, medium effort)

After completing an action via which-key or palette, show "Tip: Cmd+T" briefly.
Self-limits to 3 appearances per action (persisted to ~/.local/state/mytty/hints.json).
Config: `show-shortcut-hints = true`
Prior art: JetBrains IDEs ("You can also use Ctrl+Shift+F").

### 4. Contextual Mode Hints (Phase 2, low effort)

When entering window/copy mode, replace the hint bar with that mode's bindings.
Prior art: Zellij status bar (their most-praised UX feature).
Config: `hint-bar-mode-hints = true`

### 5. `mytty show-keys` CLI (Phase 1, low effort)

Print all keybindings grouped by category, showing both direct shortcut and which-key path.
Supports `--format json` and `--conflicts`.
Prior art: tmux `list-keys`, wezterm `show-keys`.

### 6. Cheat Sheet Overlay (deferred, medium-high effort)

Hold Cmd for 1.5s: full-screen shortcut reference organized by category.
Prior art: macOS CheatSheet app, iPadOS keyboard overlay.
Complexity: NSEvent flagsChanged monitoring, hold timer, responsive layout.

### 7. Frequency Tracker + Nudges (deferred, high effort)

Track action invocations by source. After 10+ which-key uses without direct shortcut,
nudge once in hint bar. Over-engineered for current scale.

### 8. Interactive Keybinding Trainer (deferred, niche)

Drill mode presenting random actions for shortcut practice. Niche audience.

## Shipping Plan

- **Phase 1** (immediate): Ghost shortcuts in which-key + `mytty show-keys` CLI
- **Phase 2** (with command palette): Palette shortcut labels + contextual mode hints
- **Phase 3** (polish): Post-action toasts

All features configurable (can be turned off).

## Composition

Proposals 1 + 2 + 4 form a complete passive discovery system:
- "What can I do next?" -> which-key (with ghost shortcuts)
- "What's the key for X?" -> command palette (with shortcut labels)
- "What can I do in this mode?" -> contextual mode hints

## Prior Art Summary

| Tool | Mechanism | Passive? | Graduation? |
|------|-----------|----------|-------------|
| macOS menus | Shortcut next to item | Yes | Yes (gold standard) |
| VS Code palette | Shortcut next to command | Yes | Yes |
| Zellij | Mode-specific status bar | Yes | Configurable density |
| which-key.nvim | Popup after delay | Yes | Implicit (speed) |
| Helix | Instant infobox on mode entry | Yes | Implicit (speed) |
| tmux list-keys | CLI dump | No | No |
| JetBrains | Post-action toast | Semi | Yes (3-strike) |
| Emacs which-key | Popup after idle delay | Yes | Delay-based |

Key insight: the most effective mechanisms are passive (user sees shortcuts
while doing something else) and provide graduation (user naturally stops
needing the discovery tool as they learn).
