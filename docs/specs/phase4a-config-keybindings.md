# Phase 4a: Configurable Keybindings

Mistty macOS terminal emulator, libghostty backend.

**Goal:** Make all keybindings configurable via `~/.config/mistty/config.toml`. Users override only the bindings they want to change; unspecified bindings keep their defaults. The trigger string syntax is compatible with Ghostty's modifier format.

**Date:** 2026-04-15

---

## 1. Config format

Option E from the design brainstorm: per-mode TOML sections with action names as keys and Ghostty-compatible trigger strings as values.

```toml
[keybindings]
# Global shortcuts (appear in macOS menu bar)
new-tab = "cmd+t"
close-pane = "cmd+w"
close-tab = "cmd+shift+w"
split-horizontal = "cmd+d"
split-vertical = "cmd+shift+d"
toggle-sidebar = "cmd+s"
toggle-tab-bar = "cmd+shift+t"
session-manager = "cmd+j"
enter-window-mode = "cmd+x"
enter-copy-mode = "cmd+shift+c"
which-key = "ctrl+space"
rename-tab = "cmd+shift+r"
next-tab = "cmd+]"
previous-tab = "cmd+["
focus-tab-1 = "cmd+1"
focus-tab-2 = "cmd+2"
# ... through focus-tab-9
next-session = "cmd+opt+down"
previous-session = "cmd+opt+up"
next-prompt = "cmd+shift+down"
previous-prompt = "cmd+shift+up"
increase-font-size = "cmd++"
decrease-font-size = "cmd+-"
navigate-left = "unconsumed:ctrl+h"
navigate-down = "unconsumed:ctrl+j"
navigate-up = "unconsumed:ctrl+k"
navigate-right = "unconsumed:ctrl+l"

[keybindings.window-mode]
# Active only in window mode. Single keys, no modifiers needed.
exit = "escape"
swap-left = "left"
swap-right = "right"
swap-up = "up"
swap-down = "down"
zoom = "z"
break-to-tab = "b"
rotate = "r"
join-pick = "m"
layout-even-horizontal = "1"
layout-even-vertical = "2"
layout-main-horizontal = "3"
layout-main-vertical = "4"
layout-tiled = "5"
resize-left = "cmd+left"
resize-right = "cmd+right"
resize-up = "cmd+up"
resize-down = "cmd+down"
# join-pick digit selection (1-9) is hardcoded, not configurable

[keybindings.copy-mode]
# Vim-style navigation. Active only in copy mode.
exit = "escape"
cursor-left = "h"
cursor-down = "j"
cursor-up = "k"
cursor-right = "l"
line-start = "0"
line-end = "$"
top = "gg"
bottom = "shift+g"
select-char = "v"
select-line = "shift+v"
select-block = "ctrl+v"
half-page-down = "ctrl+d"
half-page-up = "ctrl+u"
page-down = "ctrl+f"
page-up = "ctrl+b"
word-forward = "w"
word-forward-big = "shift+w"
word-backward = "b"
word-backward-big = "shift+b"
word-end = "e"
word-end-big = "shift+e"
find-char = "f"
find-char-reverse = "shift+f"
till-char = "t"
till-char-reverse = "shift+t"
repeat-find = ";"
repeat-find-reverse = ","
search-forward = "/"
search-backward = "?"
search-next = "n"
search-prev = "shift+n"
word-end-backward = "ge"
word-end-backward-big = "gE"
toggle-help = "g?"
yank = "y"
confirm-search = "return"

[keybindings.which-key.window]
swap-left = "h"
swap-right = "l"
swap-up = "k"
swap-down = "j"
zoom = "z"
break-to-tab = "b"
rotate = "r"
equalize = "="

[keybindings.which-key.pane]
split-vertical = "v"
split-horizontal = "h"
close = "x"

[keybindings.which-key.session]
new = "n"
manager = "j"
close = "c"

[keybindings.which-key.tab]
new = "n"
close = "x"
focus-1 = "1"
focus-2 = "2"
# ... through focus-9
```

Action names are TOML keys. Trigger strings are values. Each mode gets its own section, matching the user's mental model: `[keybindings]` for global shortcuts, `[keybindings.window-mode]` for window mode, `[keybindings.copy-mode]` for copy mode.

Which-key groups map to nested TOML tables. Each sub-table under `[keybindings.which-key]` becomes a which-key group (e.g., `[keybindings.which-key.window]` produces the "window" group in the which-key overlay).

Trigger string syntax: `[prefix:]modifier+key`. Modifiers: `cmd`, `ctrl`, `alt`/`opt`, `shift`. Keys: lowercase letters, `escape`, `return`, `space`, `up`/`down`/`left`/`right`, `tab`, `+`, `-`, `[`, `]`, `$`, and other symbols.

Modifier aliases are accepted on read and normalized on write: `command`/`super` become `cmd`, `control` becomes `ctrl`, `option` becomes `opt`/`alt`.

### Alternatives rejected

1. **Ghostty-native string arrays (Option C):** `keybind = ["cmd+d=split-horizontal", ...]`. Near-1:1 Ghostty migration, but TOML array replacement semantics mean specifying one custom binding requires re-specifying ALL defaults. This would be the #1 support question. Ghostty's own config format allows repeated keys (not valid TOML), so each `keybind = ...` line is additive. In real TOML, we lose that property.

2. **Alacritty-style structured arrays (Option B):** `[[keybindings]]` with key/mods/action fields. Multi-bind is trivial, but extremely verbose (~4x line count). 30 copy-mode bindings at 4 lines each = 120 lines for copy mode alone. Merge semantics are the same array-replacement problem as Option C.

3. **Trigger-as-key tables (Option D):** `"cmd+d" = "split-horizontal"`. TOML structurally prevents duplicate-trigger conflicts, and multi-bind is trivial. But rebinding an action requires two lines (unbind old trigger + bind new trigger), and the config is organized by "what keys do" rather than "what features exist." The action-centric view is more useful for a config file users edit occasionally.

4. **Hybrid formats (Option F):** Every hybrid tried either introduced two ways to do the same thing (requiring precedence rules) or combined the weaknesses of its parents. Two keybind syntaxes in one file is worse than either syntax alone.

5. **Flat action-as-key without per-mode sections (Option A):** Works for global bindings but doesn't communicate that window-mode and copy-mode bindings are modal. Users would need to know which actions are modal from documentation alone. Per-mode sections make this structural.

---

## 2. Merge semantics

User config merges per-action within each section. Unspecified actions keep their compiled-in defaults. To override one binding, specify just that action in the relevant section. To remove a default binding, set the action to `"unbind"`. To clear all defaults in a section, add `_reset = true` to that section.

```toml
# Override just one global binding
[keybindings]
split-horizontal = "cmd+shift+d"  # was cmd+d

# Remove a binding entirely
[keybindings]
enter-copy-mode = "unbind"

# Replace all copy-mode bindings with custom ones
[keybindings.copy-mode]
_reset = true
exit = "q"
yank = "y"
```

When `_reset = true` is set on a section, all compiled-in defaults for that section are discarded. Only the bindings explicitly listed in the section apply. This is useful for users who want full control over a mode.

To clear ALL keybinding defaults across every section, add `_reset = true` directly inside `[keybindings]` (before any sub-tables). This resets global bindings and all mode sections. Not recommended for most users.

### Alternatives rejected

- **Array replacement (Ghostty/Alacritty model):** User specifies the complete binding set. Simple to build but hostile to users: changing one binding requires copying all defaults. New defaults added in Mistty updates are silently lost.
- **Additive-only (no unbind):** Simpler but users can't remove bindings that conflict with their workflow.

---

## 3. Trigger string syntax

Grammar:

```
trigger     = [prefix ":"] [modifiers "+"] key
prefix      = "unconsumed"
modifiers   = modifier ("+" modifier)*
modifier    = "cmd" | "ctrl" | "alt" | "opt" | "shift"
key         = letter | digit | special | symbol
letter      = "a".."z"
digit       = "0".."9"
special     = "escape" | "return" | "space" | "tab" | "backspace" | "delete"
            | "up" | "down" | "left" | "right"
            | "f1".."f12"
symbol      = "+" | "-" | "=" | "[" | "]" | "\\" | ";" | "'" | "," | "."
            | "/" | "`" | "$" | "^" | "?" | "!"
```

Parsing rules:

- Case-insensitive on read, normalized to lowercase on write.
- Modifier order is normalized to `ctrl+alt+shift+cmd` (alphabetical).
- `gg` in copy mode is a two-character sequence, not a modifier combo. Copy mode handles multi-character inputs specially.
- The `unbind` keyword is reserved and cannot be used as a key name.

Copy mode supports multi-character triggers: `gg` (go to top), `ge` (word-end backward), `gE` (word-end backward, big word), `g?` (toggle help). These are `g`-prefixed sequences, not modifier combinations. The trigger parser accepts them as literal multi-character strings. The copy-mode dispatcher handles the `g` prefix state internally: when `g` is pressed, it waits for the next character to resolve the action. Other modes do not support multi-character triggers.

### Alternatives rejected

- **Separate modifier and key fields (Alacritty):** `key = "d"`, `mods = "cmd"`. More structured but splits one concept across two fields. The combined string is more readable and matches Ghostty's format.
- **macOS symbolic notation:** `⌘D`, `⌃H`. Not ASCII-friendly, hard to type, not portable.

---

## 4. `unconsumed:` semantics

This is the most important design decision in the spec.

`unconsumed:` means "only fire this Mistty binding if libghostty did not consume the key." It does NOT mean "only fire if the running TUI app didn't consume the key."

The implementation:

1. Mistty's NSEvent monitor intercepts a key press (e.g., Ctrl+H).
2. Check if the key matches a Mistty binding with the `unconsumed:` prefix.
3. Call `ghostty_surface_key_is_binding(surface, event, &flags)` to query libghostty.
4. If libghostty returns `true` (any flags): libghostty has a binding for this key. Pass it through to libghostty, skip the Mistty action. This covers both consumed bindings (Ghostty swallows the key) and unconsumed bindings (Ghostty performs its action and passes the key to the terminal). In either case, Mistty should not intercept.
5. If libghostty returns `false`: no Ghostty binding matches. Mistty handles the key (e.g., pane navigation).

The rule is simple: `unconsumed:` means "Mistty handles this key only when Ghostty has no opinion about it."

For bindings WITHOUT the `unconsumed:` prefix, Mistty intercepts the key unconditionally (current behavior).

Default pane navigation bindings use `unconsumed:` so that Ghostty keybindings take precedence. Users who configure `keybind = ctrl+h=...` in their Ghostty config will have that binding respected.

### The TUI app passthrough problem

No terminal emulator has solved the problem of knowing whether a TUI app consumed a key. The terminal sends keys to the app via the PTY, but there is no back-channel for the app to report "I didn't use this key."

Existing approaches across the ecosystem:

| Approach | Used by | Limitation |
|----------|---------|------------|
| Process name list | wezterm, tmux-vim-navigator | Fragile. Must maintain a list. Breaks for unknown TUI apps. |
| Alternate screen detection | Proposed in Ghostty #9901 (closed) | Too coarse. fzf, lazygit, and shell completions use alt screen. |
| Editor-side edge detection | smart-splits.nvim | Only works for editors with plugins. Most correct approach. |
| Kitty keyboard protocol | Ghostty, kitty, wezterm | Solves key disambiguation (Tab vs Ctrl+I), not key routing between layers. No "report unconsumed" extension exists. |

Mistty's approach for TUI app passthrough (separate from `unconsumed:`):

1. **Primary:** smart-splits.nvim integration (Phase 3b). Neovim detects it's at an edge, calls `mistty-cli pane focusByDirection`. The key never reaches Mistty's interceptor.
2. **Fallback:** Configurable process name list for non-neovim TUI apps.

### Alternatives rejected

- **`unconsumed:` relative to the TUI app:** Not possible. No terminal protocol supports this. Would require inventing a new protocol extension, getting adoption from terminal apps, and waiting years. Defining `unconsumed:` this way would be a promise we can't keep.
- **Alternate screen heuristic:** Check if the terminal is in alternate screen mode and pass keys through if so. Too coarse: fzf, lazygit, and many tools use alternate screen but don't need Ctrl+HJKL. Would break pane navigation whenever a user runs `less` or `man`.
- **No `unconsumed:` prefix at all:** Force users to choose between Mistty bindings and Ghostty bindings with no layering. Users who configure Ghostty keybindings would have silent conflicts.

---

## 5. Configurable process name list

A new config key for TUI app detection:

```toml
[keybindings]
passthrough-processes = ["nvim", "vim", "helix", "lazygit"]
```

When the foreground process matches an entry, Mistty passes navigation keys (Ctrl+HJKL) through to the terminal instead of handling pane navigation. This is the existing behavior with a hardcoded list; this section makes it configurable.

Default list: `["nvim", "vim", "helix", "lazygit"]` (expanded from current `["nvim", "neovim", "vim"]`).

Matching: exact process name match, or process name followed by a space (e.g., `nvim` matches `nvim` and `nvim --clean` but not `nvim-qt`). Case-sensitive.

This is a stopgap. The process name list is inherently fragile. The long-term solution is editor-side integration (smart-splits.nvim or equivalent for each TUI app). This is a known limitation, not a design choice.

### Alternatives rejected

- **No process detection at all:** Ctrl+HJKL would always be intercepted by Mistty, breaking vim/helix/lazygit navigation. Unacceptable until smart-splits.nvim covers all TUI apps (it doesn't, and won't).
- **Automatic detection via Kitty keyboard protocol flags:** If a TUI app enables the Kitty keyboard protocol, treat it as "wants all keys." Speculative; no terminal does this. Would break apps that enable the protocol but don't want modifier keys.

---

## 6. Multi-bind and conflict detection

Multiple triggers for one action use an array value:

```toml
toggle-sidebar = ["cmd+s", "cmd+shift+s"]
```

Conflict detection at config load time:

- Build a reverse map (trigger -> action) per mode after merging defaults with user config.
- If two actions map to the same trigger in the same mode, log a warning naming both actions and the conflicting trigger.
- The action that appears later in the compiled-in defaults list wins. For user-defined bindings that conflict with each other, the conflict is logged and behavior is undefined (fix the config).
- Conflicts across modes are fine (`z` in window-mode and `z` in copy-mode don't conflict).

---

## 7. macOS menu bar integration

Global keybindings from `[keybindings]` that correspond to menu items are reflected in the macOS menu bar. SwiftUI `.keyboardShortcut()` reads from a `KeybindingStore` model populated by the config parser. When config reloads, the store updates and SwiftUI re-renders menu shortcuts.

Constraint: macOS menu shortcuts only support single key + modifiers. No sequences, no `unconsumed:` prefix. If a menu action is bound to an `unconsumed:` trigger, the menu shortcut is omitted (the binding still works via the NSEvent monitor path).

---

## 8. Implementation plan

**Phase 4a-1: Config parsing and KeybindingStore**

- Add `KeybindingStore` model class holding the merged binding map.
- Extend `MisttyConfig.parse()` to read `[keybindings]` sections.
- Add trigger string parser (modifiers, key, prefix).
- Add merge logic (defaults + user overrides).
- Add conflict detection and warning.
- Handle multi-character triggers for copy mode (g-prefixed sequences).
- Tests for parsing, merging, conflicts, `unbind`, `_reset`.

**Phase 4a-2: Wire global keybindings**

- Replace hardcoded `.keyboardShortcut()` calls in MisttyApp.swift with `KeybindingStore` lookups.
- Replace hardcoded Ctrl+HJKL in PaneNavigationManager with store lookups.
- Add `unconsumed:` check using `ghostty_surface_key_is_binding()`.
- Update process name list to read from config.

**Phase 4a-3: Wire modal keybindings**

- Replace hardcoded keyCodes in WindowModeManager with store lookups.
- Replace hardcoded characters in CopyModeState with store lookups.
- Replace hardcoded `WhichKeyManager.defaultBindings()` with config-driven tree.

---

## 9. Files changed

New files:

| File | Purpose |
|------|---------|
| `Mistty/Config/KeybindingStore.swift` | Binding store, trigger parser, merge logic |
| `Mistty/Config/TriggerParser.swift` | Trigger string -> KeyboardTrigger |
| `MisttyTests/Config/KeybindingStoreTests.swift` | Tests for store, merge, conflicts |
| `MisttyTests/Config/TriggerParserTests.swift` | Tests for trigger parsing |

Modified files:

| File | Changes |
|------|---------|
| `Mistty/Config/MisttyConfig.swift` | Parse `[keybindings]` sections |
| `Mistty/App/MisttyApp.swift` | Dynamic menu shortcuts from KeybindingStore |
| `Mistty/App/PaneNavigationManager.swift` | Configurable keys, `unconsumed:` check |
| `Mistty/App/WindowModeManager.swift` | Configurable keys from store |
| `Mistty/Models/CopyModeState.swift` | Configurable keys from store |
| `Mistty/App/WhichKeyManager.swift` | Config-driven tree |
| `Mistty/Models/MisttyPane.swift` | Configurable process name list |

---

## 10. Testing

- Trigger parser: valid triggers, invalid triggers, modifier normalization, alias resolution.
- Merge logic: defaults only, single override, full section reset, unbind.
- Conflict detection: same trigger in same mode warns; same trigger in different modes does not.
- Multi-bind: array values parsed correctly.
- Which-key tree: nested TOML tables produce correct tree structure.
- Process name matching: exact match, prefix match, case sensitivity.
- Integration: config file with keybindings section loads and produces correct KeybindingStore.

---

## 11. Out of scope

| Feature | Reason | Target |
|---------|--------|--------|
| Key sequences (`ctrl+a>n`) | Trigger parser accepts them syntactically but no dispatch logic is built | Future phase |
| Chained actions (one trigger fires multiple actions) | Not needed yet | Future phase |
| Live config reload | Config is read at launch; hot reload is a separate feature | Future phase |
| Theme/color configuration | Separate concern | Future phase |
| Copy mode custom motions and text objects | Beyond single-key remapping | Future phase |
| Exporting/importing keybinding configs | Not needed for initial release | Future phase |
| GUI keybinding editor | Not needed for initial release | Future phase |

---

## 12. Acceptance criteria

1. All existing keybindings work with default config (no `[keybindings]` section in config.toml).
2. User can override any single binding by adding one line to config.toml.
3. User can unbind any default binding with `action = "unbind"`.
4. User can reset an entire mode with `_reset = true`.
5. Pane navigation keys use `unconsumed:` by default and defer to Ghostty bindings when present.
6. Process name list is configurable and defaults include nvim, vim, helix, lazygit.
7. macOS menu bar reflects configured shortcuts.
8. Conflicting triggers produce a warning at config load time.
9. All existing tests continue to pass.
10. New tests cover trigger parsing, merge logic, conflict detection, and process name matching.
11. Copy mode multi-character sequences (gg, ge, gE, g?) work with default and custom bindings.
