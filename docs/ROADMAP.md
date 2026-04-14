# Mistty Roadmap

Created: 2026-04-14
Iteration: 7 (final)

## Principles

1. **Time to daily driver**: optimize for the shortest path to replacing your current terminal setup.
2. **Personal-first, generalizable**: solve your own workflow pain, design interfaces that generalize.
3. **Contextual awareness**: Mistty's identity is "you never leave your flow to check what's happening."
4. **Infrastructure ships with features**: build plumbing when a feature needs it, not before.
5. **Dependency-ordered**: phases are sequenced by what unblocks what. No fake timelines.
6. **Visual quality is not optional**: polish ships with features, not after them.

---

## Completed

### Phase 0: Quality Gate
All tests pass (271, 0 failures), zero compiler warnings, zero swiftlint violations. Cleanup shipped: test isolation, swift format, swiftlint config, CopyModeManager bug fixes, dead code removal.

### Phase 1a: Which-Key Overlay
Transient hierarchical keybinding overlay (Ctrl+Space). Categorized actions (w=windows, p=panes, s=sessions). Fades after selection or timeout. Hardcoded keybindings until config system lands.

---

## Phase 1b: Daily Driver Polish

**Why first:** the app works but looks like a prototype. Every user's first impression is visual. These items are the difference between "interesting project" and "I could use this."

- [ ] Cmd+/- beep fix: add no-op menu commands so AppKit stops alerting (ghostty handles font size internally)
- [ ] Sidebar/terminal divider: 1px separator or subtle shadow between panels
- [ ] Tab active/inactive contrast: increase highlight difference
- [ ] Typography hierarchy: lighter weight or smaller size for sidebar labels vs terminal text
- [ ] Tab drag-and-drop reordering: SwiftUI `onDrag`/`onDrop` on sidebar and tab bar items
- [ ] Sidebar truncation: tooltips on hover for truncated session names
- [ ] Dropdown / Quake mode: global hotkey summons a floating terminal panel (NSPanel, slides from top). Hardcoded hotkey initially, configurable when 4a lands. Top-voted WezTerm issue, natural macOS fit.

- Complexity: 3 (visual polish items are individually small, but dropdown mode is a real feature)

**Done when:** no system alert sounds on standard shortcuts, clear visual boundaries between all UI regions, tabs are reorderable by drag, global hotkey summons dropdown terminal.

---

## Phase 1c: Auto-Hide Panels

**Why here:** screen real estate is everything for a terminal. Without this, the sidebar and tab bar eat space permanently.

Sidebar and tab bar support Pinned / Auto-hide / Hidden modes. Auto-hide: overlay slides in on edge hover (150ms dwell, 20px trigger zone), out on mouse leave (300ms delay). Panels overlay terminal content (no resize/reflow). Keyboard shortcuts always work regardless of mode.

- Complexity: 2
- Design: /tmp/ai-design-autohide-panels.md

**Done when:** sidebar and tab bar can be set to auto-hide, panels overlay without reflowing terminal content, keyboard shortcuts work in all modes.

---

## Phase 2: Contextual Sidebar

**Why this phase:** the sidebar is Mistty's most visible differentiator from Ghostty. Right now it's a list of names. This phase makes it the "you never leave your flow" feature.

Merges the old 1b (OSC Foundation) and 2a (Rich Sidebar Metadata) into one coherent feature.

### OSC Foundation
Build the OSC parser as part of this feature. It's the foundation for Phase 4 (shell integration) and Phase 6 (block-based output).

- OSC 7: working directory tracking
- OSC 9/99/777: desktop notifications
- OSC 133: command boundaries (prompt, command, output markers)

### Notification Rings
Per-pane output badges (colored ring on the pane border), sidebar session badges (dot indicator). Attention coordinator debounces flash spam. Cmd+Shift+U jump-to-unread.

### Rich Sidebar Metadata
Git branch + dirty indicator, working directory (from OSC 7), listening ports per session row.

### Shell Integration (OSC 133)
Command boundary detection from the OSC parser. Cmd+Up/Down to jump between prompts, per-command exit code and duration display. Enables 6b (block-based output).

- Complexity: 3 (largest phase; the OSC parser is shared infrastructure, consumers are incremental)
- Gap analysis: cmux has notification rings. No one else combines notifications + git + ports + working directory in a sidebar.

**Done when:** sidebar shows git branch, working directory, and port info per session. Unfocused panes with output show notification badges. Cmd+Shift+U jumps to the next unread pane. Cmd+Up/Down jumps between prompts.

---

## Phase 3: Platform

**Why this phase:** the socket API is the foundation for neovim navigation (personal pain point), CLI scripting, Raycast/Hammerspoon integration, and future automation. Phase 2 and Phase 3 have no dependency between them and can run in parallel.

### 3a. @FocusedValue Migration
Replace NotificationCenter menu commands with @FocusedValue. Publish MisttySession (not SessionStore). Fixes multi-window menu targeting bug.

- Complexity: 2
- Architectural cleanup that fixes a real bug. Needed before socket API for correctness.

### 3b. Socket API + CLI
Unix domain socket (`/tmp/mistty-$UID.sock`). JSON-RPC protocol. Extends the existing `MisttyCLI` binary (currently uses direct IPC) to use the socket as transport. Access control via file permissions.

- Complexity: 3
- Enables: 3c, Raycast/Hammerspoon integration, scripting

### 3c. Neovim Split Navigation
smart-splits.nvim integration via socket API. Bidirectional Ctrl+h/j/k/l between neovim splits and Mistty panes.

- Complexity: 2 (once 3b exists)
- Depends on: 3b
- Why unsolved in Ghostty: deliberate design choice (no IPC). Mistty can solve it.
- Personal pain point.

**Done when:** menu commands work correctly in multi-window, `mistty pane list` returns JSON, Ctrl+h/j/k/l crosses neovim/Mistty boundary.

---

## Phase 4: Configuration + Persistence

**Why deferred to here:** by this point you've used the app daily for weeks and know what actually needs configuring. The investigation is grounded in real usage, not speculation.

### 4a. Configuration System
Research and build Mistty's configuration system. Keybindings, appearance, behavior, panel modes.

Investigation scope (research prior art, then decide):
- TOML (Ghostty, Alacritty): static, simple, well-understood
- Lua (WezTerm, Neovim): dynamic, scriptable, event hooks
- Hybrid (TOML for static + Lua for hooks)

Key questions to answer from real usage:
1. What have you actually wanted to configure in the past weeks?
2. Does Mistty need runtime scripting or just static config?
3. What's the migration story from Ghostty config?

- Complexity: 3 (investigation) + 2-3 (implementation)
- Retroactively enhances: which-key (1a reads keybindings from config), auto-hide (1c modes configurable)
- Enables: 5a (project layouts), 5c (Ghostty config compat)

### 4b. Session Resurrection
Auto-save (layout, working directories, scrollback) on quit. Auto-restore on launch.

Consider the unbundled alternative: integrate with shpool or zmx for session persistence instead of building from scratch. Trade external dependency for reduced complexity.

- Complexity: 3 (built-in) or 2 (shpool/zmx integration)

**Done when:** config file controls keybindings and appearance, quit+relaunch restores layout.

---

## Phase 5: Differentiators

### 5a. Declarative Project Layouts
`.mistty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects. `start_suspended` option for panes that show the command but don't execute until Enter.

Includes Layout Manager UI: "Save current layout" command that generates `.mistty.toml` from the live workspace.

- Complexity: 2
- Depends on: 4a (config format), 4b (serialization format)

### 5b. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden. Drag to reposition.

- Complexity: 3
- 201 votes on Ghostty. Mistty's SwiftUI architecture makes this easier than Ghostty's renderer-level splits.

### 5c. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

- Complexity: 2

### 5d. Hints Mode
Press a trigger key, all visible URLs/paths/hashes get short letter labels. Type the label to act (open, copy, insert). Keyboard-driven alternative to clicking links.

- Complexity: 2
- Kitty ships this ("hints kitten"). Ghostty has ~180 combined votes across related discussions.
- Pairs with 6c (inline preview panes): hints selects targets, previews displays them.

### 5e. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts. Lower priority because which-key (1a) covers discoverability.

- Complexity: 2

### 5f. Enhanced Session Manager
Enhance existing Cmd+J session manager: frecency-ranked directories (zoxide integration already exists), Nerd Font icons, preview pane showing recent output. Cmd+\` for instant last-workspace toggle.

- Complexity: 2

**Done when:** project layouts load from `.mistty.toml` with save-current-layout command, floating panes work, Ghostty themes import, hints mode selects visible targets, command palette searches all actions, session manager shows frecency-ranked results with icons.

---

## Phase 6: Moonshots

### 6a. Native tmux Control Mode
Render tmux panes as native Mistty splits via `tmux -CC`. The headline feature. Only iTerm2 has this.

- Complexity: 5
- Why genuinely hard: protocol is complex, poorly documented. Bidirectional sync edge cases (resize reflow, pane reordering, Unicode). iTerm2 invested years.
- Defensible moat: hard to copy.

### 6b. Block-Based Output
Command+output as selectable blocks. Metadata: exit code, duration, cwd. Click to select entire block. Cmd+Up/Down to navigate.

- Complexity: 4
- Depends on: Phase 2 (shell integration / OSC 133)
- Only Warp has this.

### 6c. Inline Preview Panes
Hover file paths in terminal output for Quick Look preview. Click to open in split pane.

- Complexity: 4
- No terminal does this. Novel.
- Pairs with 5d (hints mode provides keyboard-driven target selection).

### 6d. Terminal Automation API
Expose surface state (cells, colors, cursor position) via the socket API for scripting and testing. The "Playwright for terminals" gap: AI agents can write TUI code but can't see the rendered result.

- Complexity: 3
- Depends on: 3b (socket API)
- Only ghostty-automator exists in this space, and it's Ghostty-specific.

### 6e. SSH Workspace Creation
`mistty ssh user@host` creates a dedicated workspace with port detection, sidebar metadata, and proper cleanup on disconnect. Optional Eternal Terminal (`et`) integration for connection persistence.

- Complexity: 4

---

## Dependency Graph

```
Completed:
  Phase 0 (cleanup) ✓
  Phase 1a (which-key) ✓

Active path:
  1b (polish + dropdown) ──> 1c (auto-hide)
                                  │
  Phase 2 and 3 can run in parallel after 1c:
                                  │
  Phase 2 (contextual sidebar):   │
    OSC parser ──> notifications + rich metadata + shell integration
                       │
                       └──> 6b (block-based output)

  Phase 3 (platform):
    3a (FocusedValue) ──> 3b (socket API) ──> 3c (neovim nav)
                              │
                              └──> 6d (automation API)

  Phase 4 (config + persist):
    4a (config) ──> 5a (layouts), 5c (Ghostty compat)
    4b (resurrection) ──> 5a (layouts)

Standalone (slot anywhere after their dependencies):
  5b (floating panes)
  5d (hints) ··> 6c (inline previews)
  5e (command palette)
  5f (enhanced session manager)
```

## What's NOT on this roadmap

- CI/CD (GitHub Actions): deferred until contributors exist
- IPC service refactoring: works, not broken
- C callback notification replacement: works, low priority
- Cursor trail: likely ships upstream in Ghostty. Track, don't build.
- Smooth/pixel scrolling: depends on libghostty upstream. Track, don't build.
- RTL/BiDi text: renderer-level, lives in libghostty. Track, don't build.
- AI integration: interesting but premature. Revisit when the terminal is solid.
- Input broadcasting: scriptable via socket API (3b), doesn't need to be built-in.
- Multi-client shared sessions: niche for a personal-first terminal.
- Workspace snapshots: novel but no one's asking for it.
- Warp-style workflows: overlaps with project layouts (5a) and shell scripts.

## Upstream tracking (free wins if Ghostty ships them)

- Cursor trail (347 votes on Ghostty)
- Smooth pixel scrolling (112 votes on Ghostty, Kitty shipped in 0.46)
- RTL/BiDi text support

## Sources

- /tmp/ai-research-terminal-landscape-2026.md (competitive landscape, 2026-04-14)
- /tmp/ai-research-mistty-unused-ideas.md (unused ideas from prior research, 2026-04-14)
- /tmp/ai-research-mistty-roadmap-iteration.md (iteration analysis, 2026-04-14)
- /tmp/ai-brainstorm-mistty-ux.md (14 ideas scored)
- /tmp/ai-debate-mistty-features.md (debate transcript)
- /tmp/ai-design-autohide-panels.md (auto-hide panel design, 3 iterations)
- /tmp/ai-plan-mistty-improvements.md (v5, original improvement plan)
- /tmp/ai-review-mistty-plan.md (plan review findings)
- /tmp/ai-research-terminal-ux-patterns.md
- /tmp/ai-research-terminal-feature-requests.md
- ~/Documents/research/terminal/terminal-session-management-research.md
