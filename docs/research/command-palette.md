# Command Palette Research

Date: 2026-05-07

## Decision

Path B chosen: separate Cmd+K palette (not extending session manager).

- Cmd+N = navigate (sessions, directories, SSH hosts)
- Cmd+K = execute (actions)

## Rationale

Three paths evaluated:
- **A (extend session manager)**: mixes "go to a place" with "do a thing." Already 5 enum cases with 8 exhaustive switches. Rejected.
- **B (separate palette)**: clean separation, Cmd+K universally understood, simpler implementation. Chosen.
- **C (unified with `>` prefix, VS Code style)**: discoverable only if you know the convention. Rejected.

## Architecture

The AppAction registry (`buildActionRegistry()` in ContentView) is the data source.
The palette is just a consumer, same as which-key, menu bar, and hint bar.

Implementation estimate: several hundred lines across 4 files:
1. `Mytty/Models/AppAction.swift` -- shipped (commit 1 of this refactor)
2. `Mytty/Views/CommandPalette/CommandPaletteViewModel.swift` -- fuzzy filter + selection
3. `Mytty/Views/CommandPalette/CommandPaletteView.swift` -- overlay UI (clone session manager pattern)
4. ContentView wiring -- `showingCommandPalette` state, overlay, handler

Reuses: FocusableTextField, MyttyTheme.modalBackdrop, material overlay pattern.

## UI Pattern

Same overlay style as session manager: material background, centered panel,
FocusableTextField at top, LazyVStack of results below. Each result shows:
- Action label (left)
- Direct shortcut right-aligned, dimmed (graduation mechanism)
- Category as subtle badge (optional)

## Key Binding

`command-palette` action, default Cmd+K. Not bound in macOS universally,
not in current KeybindingStore.

## Prior Art

- VS Code Cmd+Shift+P: shows keybinding next to every command (passive graduation)
- Raycast: Cmd+Space, categories, recent actions
- Linear: Cmd+K, contextual actions based on current view
- Wezterm: `ActivateCommandPalette` action with shortcut labels
