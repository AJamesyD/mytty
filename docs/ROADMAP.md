# Mistty Roadmap

Created: 2026-04-14
Iteration: 10

## Principles

1. **Time to daily driver**: optimize for the shortest path to replacing your current terminal setup.
2. **Personal-first, generalizable**: solve your own workflow pain, design interfaces that generalize.
3. **Contextual awareness**: Mistty's identity is "you never leave your flow to check what's happening."
4. **Infrastructure ships with features**: build plumbing when a feature needs it, not before.
5. **Dependency-ordered**: phases are sequenced by what unblocks what. No fake timelines.
6. **Visual quality is not optional**: polish ships with features, not after them.
7. **Spec before code**: every feature gets a written spec (prior art, what's opinionated vs configurable, interaction patterns, edge cases) before implementation begins. Spec can be brief (20 lines for small features) or a full design doc. Approved before coding starts.
8. **Opinionated defaults, constrained configuration**: ship one good design. When configuration is needed, prefer presets over arbitrary values. Don't push design decisions to the user. Code must be written with the assumption that hardcoded values will become configurable later: access through abstractions (e.g., `theme.surface` not `Color.white.opacity(0.03)`), even when the backing store is a static singleton.
9. **Cleanup gates before major phases**: every major phase has a cleanup/refactor prerequisite that addresses tech debt which would make the phase harder or messier. Cleanup gates are not optional. They prevent debt from compounding across phases.

---

## Completed

### Phase 0: Quality Gate
All tests pass (271, 0 failures), zero compiler warnings, zero swiftlint violations. Cleanup shipped: test isolation, swift format, swiftlint config, CopyModeManager bug fixes, dead code removal.

### Phase 1a: Which-Key Overlay
Transient hierarchical keybinding overlay (Ctrl+Space). Categorized actions (w=windows, p=panes, s=sessions). Fades after selection or timeout. Hardcoded keybindings until config system lands.

---

## Phase 1b: Daily Driver Polish

**Why first:** the app works but looks like a prototype. Every user's first impression is visual. These items are the difference between "interesting project" and "I could use this."

- [x] Cmd+/- beep fix: add no-op menu commands so AppKit stops alerting (ghostty handles font size internally)
- [x] Sidebar/terminal divider: 1px separator or subtle shadow between panels
- [x] Tab active/inactive contrast: increase highlight difference
- [x] Typography hierarchy: lighter weight or smaller size for sidebar labels vs terminal text
- [x] Inactive pane dimming: black overlay on inactive split panes
- [x] Muted inactive sidebar text
- [x] Sidebar truncation: tooltips on hover for truncated session names
### Cleanup gate (before remaining 1b work)
- [ ] **Theme file extraction**: create `MisttyTheme.swift` with semantic color tokens. Migrate all hardcoded `Color.white.opacity(X)` / `Color.black.opacity(X)` calls across views to use theme tokens. Pure refactor, no visual change. This is the abstraction boundary that principle #8 demands.

### Remaining 1b features (require theme file)
- [ ] Sidebar visual rework: session cards, spacing, accent borders, pane count indicators. Spec required: `/tmp/ai-research-sidebar-patterns.md` has prior art, needs a concrete spec before implementation.
- [ ] Tab drag-and-drop reordering. Spec required.
- [ ] Dropdown / Quake mode. Spec required: NSPanel, global hotkey, animation, interaction patterns.

- Complexity: 3 (visual polish items are individually small, but dropdown mode is a real feature)

**Done when:** no system alert sounds on standard shortcuts, clear visual boundaries between all UI regions, tabs are reorderable by drag, global hotkey summons dropdown terminal.

---

### Cleanup gate (before Phase 1c)
- [ ] **@FocusedValue migration** (moved from Phase 3a): replace NotificationCenter menu commands with @FocusedValue. Currently 45 NotificationCenter usages across MisttyApp.swift and ContentView.swift. Every new feature adds more. Fix now before auto-hide panels add more notification-based toggles. Fixes multi-window menu targeting bug.
- [ ] **ContentView extraction**: split ContentView.swift (472 lines, growing) into focused components. Extract notification routing, overlay management, and keyboard monitor setup into separate files. Pure refactor.

## Phase 1c: Auto-Hide Panels

**Why here:** screen real estate is everything for a terminal. Without this, the sidebar and tab bar eat space permanently.

Sidebar and tab bar support Pinned / Auto-hide / Hidden modes. Auto-hide: overlay slides in on edge hover (150ms dwell, 20px trigger zone), out on mouse leave (300ms delay). Panels overlay terminal content (no resize/reflow). Keyboard shortcuts always work regardless of mode.

- Complexity: 2
- Spec: /tmp/ai-design-autohide-panels.md (exists, review before implementation)

**Done when:** sidebar and tab bar can be set to auto-hide, panels overlay without reflowing terminal content, keyboard shortcuts work in all modes.

---

### Cleanup gate (before Phase 2)
- [ ] **Swiftlint + swift format pass**: ensure zero violations before adding OSC parser and sidebar metadata code.
- [ ] **Test coverage audit**: review test gaps for sidebar, tab bar, and pane management. Add tests for any untested code paths that Phase 2 will build on.
- [ ] **Manager pattern review**: the 4 manager classes (WindowMode, CopyMode, WhichKey, PaneNavigation) use similar activate/deactivate + NSEvent monitor patterns. Extract shared protocol or base if 3+ share identical structure. If not, document the pattern for Phase 2's attention coordinator.

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
- Spec required: OSC parser architecture, notification ring visual design, sidebar metadata layout. Prior art: `/tmp/ai-research-sidebar-patterns.md`, `/tmp/ai-research-terminal-ui-ux-patterns.md`.

**Done when:** sidebar shows git branch, working directory, and port info per session. Unfocused panes with output show notification badges. Cmd+Shift+U jumps to the next unread pane. Cmd+Up/Down jumps between prompts.

---

### Cleanup gate (before Phase 3)
- [ ] **IPC audit**: review existing IPCService.swift (549 lines) and IPCListener.swift (318 lines). Understand current IPC mechanism before designing socket API replacement. Document what works, what's fragile, what the socket API replaces vs extends.

## Phase 3: Platform

**Why this phase:** the socket API is the foundation for neovim navigation (personal pain point), CLI scripting, Raycast/Hammerspoon integration, and future automation. Phase 2 and Phase 3 are independent; choose one to complete first. Recommend Phase 2 first (daily-driver value, unblocks 6b).

### 3a. Socket API + CLI
Unix domain socket (`/tmp/mistty-$UID.sock`). JSON-RPC protocol. Extends the existing `MisttyCLI` binary (currently uses direct IPC) to use the socket as transport. Access control via file permissions.

- Complexity: 3
- Spec required: protocol design (JSON-RPC methods, error codes), migration plan from current IPC.
- Enables: 3b, Raycast/Hammerspoon integration, scripting

### 3b. Neovim Split Navigation
smart-splits.nvim integration via socket API. Bidirectional Ctrl+h/j/k/l between neovim splits and Mistty panes.

- Complexity: 2 (once 3a exists)
- Spec required: smart-splits.nvim integration protocol, edge cases (nested neovim, multiple neovim instances).
- Depends on: 3a
- Why unsolved in Ghostty: deliberate design choice (no IPC). Mistty can solve it.
- Personal pain point.

**Done when:** menu commands work correctly in multi-window, `mistty pane list` returns JSON, Ctrl+h/j/k/l crosses neovim/Mistty boundary.

---

### Cleanup gate (before Phase 4)
- [ ] **Config audit**: catalog every hardcoded value that users have wanted to change during daily driving (keybindings, colors, panel modes, hotkeys). This becomes the requirements list for the config system spec.
- [ ] **MisttyTheme review**: by this point the theme file has been in use for several phases. Review whether the token set is complete, whether any tokens are unused, and whether the abstraction is right for supporting multiple preset themes.

## Phase 4: Configuration + Persistence

**Why deferred to here:** by this point you've used the app daily for weeks and know what actually needs configuring. The investigation is grounded in real usage, not speculation.

### 4a. Configuration System
Research and build Mistty's configuration system. Keybindings, appearance, behavior, panel modes.

- Spec required: full design doc. Investigation scope, format decision, what's configurable vs opinionated, preset themes vs arbitrary values. Prior art research exists; needs a decision spec.
- Investigation scope (research prior art, then decide):
- TOML (Ghostty, Alacritty): static, simple, well-understood
- Lua (WezTerm, Neovim): dynamic, scriptable, event hooks
- Hybrid (TOML for static + Lua for hooks)

Key questions to answer from real usage:
1. What have you actually wanted to configure in the past weeks?
2. Does Mistty need runtime scripting or just static config?
3. What's the migration story from Ghostty config?
4. Hot-reload strategy: live (file watcher), on-save, or restart-only? Affects architecture (file watcher, diffing, partial apply).

- Complexity: 3 (investigation) + 2-3 (implementation)
- Retroactively enhances: which-key (1a reads keybindings from config), auto-hide (1c modes configurable)
- Enables: 5a (project layouts), 5c (Ghostty config compat)

### 4b. Session Resurrection
Auto-save (layout, working directories, scrollback) on quit. Auto-restore on launch.

- Spec required: what state is saved, serialization format, built-in vs shpool/zmx integration decision.
- Consider the unbundled alternative: integrate with shpool or zmx for session persistence instead of building from scratch. Trade external dependency for reduced complexity.

- Complexity: 3 (built-in) or 2 (shpool/zmx integration)

**Done when:** config file controls keybindings and appearance, quit+relaunch restores layout.

---

### Cleanup gate (before Phase 5)
- [ ] **Integration test coverage**: ensure socket API (3a) and config system (4a) have tests covering the interfaces that Phase 5 features build on. 5a and 5c depend directly on these.
- [ ] **API stability review**: review socket API method signatures and config file format for breaking changes before building features on top of them.

## Phase 5: Differentiators

### 5a. Declarative Project Layouts
`.mistty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects. `start_suspended` option for panes that show the command but don't execute until Enter.

Includes Layout Manager UI: "Save current layout" command that generates `.mistty.toml` from the live workspace.

- Complexity: 2
- Spec required: file format, trust model, layout manager UI design.
- Depends on: 4a (config format), 4b (serialization format)

### 5b. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden. Drag to reposition.

- Complexity: 3
- Spec required: z-ordering, resize behavior, keyboard navigation between floating and tiled panes.
- 201 votes on Ghostty. Mistty's SwiftUI architecture makes this easier than Ghostty's renderer-level splits.

### 5c. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

- Complexity: 2
- Spec required: which Ghostty config keys to support, conflict resolution with Mistty config.

### 5d. Hints Mode
Press a trigger key, all visible URLs/paths/hashes get short letter labels. Type the label to act (open, copy, insert). Keyboard-driven alternative to clicking links.

- Complexity: 2
- Spec required: label assignment algorithm, action menu, visual overlay design. Prior art: Kitty hints kitten.
- Kitty ships this ("hints kitten"). Ghostty has ~180 combined votes across related discussions.
- Pairs with 6c (inline preview panes): hints selects targets, previews displays them.

### 5e. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts. Lower priority because which-key (1a) covers discoverability.

- Complexity: 2
- Spec required: action registry, search ranking, visual design. Prior art: Raycast, Nova, Linear.

### 5f. Enhanced Session Manager
Enhance existing Cmd+J session manager: frecency-ranked directories (zoxide integration already exists), Nerd Font icons, preview pane showing recent output. Cmd+\` for instant last-workspace toggle.

- Complexity: 2
- Spec required: preview pane content, icon mapping, frecency algorithm tuning.

### 5g. Sidebar Position
Sidebar configurable to appear on left or right side of the window.

- Complexity: 1
- Depends on: 4a (config system for persistence)

**Done when:** project layouts load from `.mistty.toml` with save-current-layout command, floating panes work, Ghostty themes import, hints mode selects visible targets, command palette searches all actions, session manager shows frecency-ranked results with icons.

---

## Phase 6: Moonshots

### 6a. Native tmux Control Mode
Render tmux panes as native Mistty splits via `tmux -CC`. The headline feature. Only iTerm2 has this.

- Complexity: 5
- Spec required: full design doc. Protocol analysis, sync model, edge case catalog. Study iTerm2's implementation.
- Defensible moat: hard to copy.

### 6b. Block-Based Output
Command+output as selectable blocks. Metadata: exit code, duration, cwd. Click to select entire block. Cmd+Up/Down to navigate.

- Complexity: 4
- Spec required: block detection from OSC 133, visual design, selection model, keyboard navigation.
- Depends on: Phase 2 (shell integration / OSC 133)
- Only Warp has this.

### 6c. Inline Preview Panes
Hover file paths in terminal output for Quick Look preview. Click to open in split pane.

- Complexity: 4
- Spec required: path detection, Quick Look integration, split-pane creation flow.
- No terminal does this. Novel.
- Pairs with 5d (hints mode provides keyboard-driven target selection).

### 6d. Terminal Automation API
Expose surface state (cells, colors, cursor position) via the socket API for scripting and testing. The "Playwright for terminals" gap: AI agents can write TUI code but can't see the rendered result.

- Complexity: 3
- Spec required: API surface, read vs write operations, security model.
- Depends on: 3a (socket API)
- Only ghostty-automator exists in this space, and it's Ghostty-specific.

### 6e. SSH Workspace Creation
`mistty ssh user@host` creates a dedicated workspace with port detection, sidebar metadata, and proper cleanup on disconnect. Optional Eternal Terminal (`et`) integration for connection persistence.

- Complexity: 4
- Spec required: workspace lifecycle, port detection mechanism, et integration model.

---

## Dependency Graph

```
Completed:
  Phase 0 (cleanup) ✓
  Phase 1a (which-key) ✓
  Phase 1b partial (beep fix, divider, tab contrast, typography, pane dim, sidebar mute) ✓

Sequential path (solo developer, no parallel phases):
  cleanup: theme extraction
    ──> 1b remaining (sidebar rework, drag-drop, dropdown)
      ──> cleanup: FocusedValue migration + ContentView extraction
        ──> 1c (auto-hide)
          ──> cleanup: lint/test/manager review
            ──> Phase 2 (contextual sidebar + OSC + shell integration)
              ──> cleanup: IPC audit
                ──> Phase 3 (socket API + neovim nav)
                  ──> cleanup: config audit + theme review
                    ──> Phase 4 (config + persist)
                      ──> cleanup: integration tests + API stability
                        ──> Phase 5 (differentiators)
                          ──> Phase 6 (moonshots)

Late dependencies:
  Phase 2 ──> 6b (block-based output)
  Phase 3a ──> 6d (automation API)
  Phase 4a ──> 5a (layouts), 5c (Ghostty compat), 5g (sidebar position)
  Phase 4b ──> 5a (layouts)
  5d (hints) ──> 6c (inline previews)
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
