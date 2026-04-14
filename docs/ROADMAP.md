# Mistty Roadmap

Created: 2026-04-14
Iteration: 13

## Principles

0. **macOS-only**: no Windows, ever. Linux is a distant stretch goal. This means: lean fully into SwiftUI and AppKit, use macOS system APIs directly (NSPanel, NSUserActivity, CGEvent taps), no cross-platform abstraction layers.
1. **Time to daily driver**: optimize for the shortest path to replacing your current terminal setup.
2. **Personal-first, generalizable**: solve your own workflow pain, design interfaces that generalize.
3. **Contextual awareness**: Mistty's identity is "you never leave your flow to check what's happening."
4. **Infrastructure ships with features**: build plumbing when a feature needs it, not before.
5. **Dependency-ordered**: phases are sequenced by what unblocks what. No fake timelines.
6. **Visual quality is not optional**: polish ships with features, not after them.
7. **Spec before code**: every feature gets a written spec (prior art, what's opinionated vs configurable, interaction patterns, edge cases) before implementation begins. Spec can be brief (20 lines for small features) or a full design doc. Approved before coding starts.
8. **Opinionated defaults, constrained configuration**: ship one good design. When configuration is needed, prefer presets over arbitrary values. Don't push design decisions to the user. Code must be written with the assumption that hardcoded values will become configurable later: access through abstractions (e.g., `theme.surface` not `Color.white.opacity(0.03)`), even when the backing store is a static singleton.
9. **Cleanup gates before major phases**: every major phase has a cleanup/refactor prerequisite that addresses tech debt which would make the phase harder or messier. Cleanup gates are not optional. They prevent debt from compounding across phases.
10. **IPC parity for stable operations**: operations that map to a noun+verb CLI command (session rename, tab move, pane split) get their IPC method in the same commit as the GUI. Exploratory features (UI modes, visual behaviors) get IPC when the interface stabilizes. This builds a consistent API surface incrementally rather than bolting it on in Phase 3. Adopted in iteration 13; pre-existing gaps (session rename IPC, tab move IPC) are tracked in Phase 3a.

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
- [x] Tab-completion beep fix: add `doCommand(by:)` override to TerminalSurfaceView so `interpretKeyEvents` selectors don't fall through to NSBeep (matches Ghostty's approach)
- [x] Sidebar/terminal divider: 1px separator or subtle shadow between panels
- [x] Tab active/inactive contrast: increase highlight difference
- [x] Typography hierarchy: lighter weight or smaller size for sidebar labels vs terminal text
- [x] Inactive pane dimming: black overlay on inactive split panes
- [x] Muted inactive sidebar text
- [x] Sidebar truncation: tooltips on hover for truncated session names
### Cleanup gate (before remaining 1b work)
- [x] **Theme file extraction**: `MisttyTheme.swift` with 25 semantic color tokens. All hardcoded color values migrated across 12 view files. Spec: `/tmp/ai-design-sidebar-visual-rework.md`.

### Remaining 1b features
- [x] Sidebar visual rework: accent bar on active session (via `listRowBackground`), tab count badge, pane count indicator, active tab highlight, increased indentation, session spacing. Spec: `/tmp/ai-design-sidebar-visual-rework.md`. Future work: per-session colors (needs config system), hover close buttons, pane sub-rows.
- [x] Session/tab renaming (sidebar + tab bar only). `/spec` before implementation. Scope: double-click to rename in sidebar and tab bar. Right-click context menu with "Rename" option. CLI rename and OSC 0/1/2 title integration deferred to Phase 2/3. Prior art: Kitty `tab_title_template`, iTerm2 session naming. Spec: /tmp/ai-design-session-tab-renaming.md.
- [x] Tab bar visibility mode: "always", "never", "if-multiple" (hide when only 1 tab). Small enough to implement directly (no `/spec` needed). Prior art: Kitty `tab_bar_min_tabs`, WezTerm `hide_tab_bar_if_only_one_tab`, neovim bufferline. Hardcode "if-multiple" as default, expose via config in Phase 4.
- [x] Tab drag-and-drop reordering. `/spec` before implementation. Prior art: iTerm2, Kitty, browser tab bars. Spec: /tmp/ai-design-tab-drag-drop.md.
- ~~Dropdown / Quake mode~~: moved to Phase 5 as 5h (not blocking daily driver use).

- Complexity: 2 (visual polish items are individually small; dropdown moved to Phase 5)

**Done when (core):** no system alert sounds on standard shortcuts, clear visual boundaries between all UI regions, sessions and tabs renameable, tab bar hides with single tab, tabs reorderable by drag.

---

### Cleanup gate (before Phase 1c)
- [x] `/refactor` **@FocusedValue migration** (moved from Phase 3a): replace NotificationCenter menu commands with @FocusedValue. Currently 45 NotificationCenter usages across MisttyApp.swift and ContentView.swift. Every new feature adds more. Fix now before auto-hide panels add more notification-based toggles. Fixes multi-window menu targeting bug. Done: TerminalCommands struct with closures, .focusedSceneValue. 15 notification names removed.
- [x] `/refactor` **ContentView extraction**: split ContentView.swift (472 lines, growing) into focused components. Extract notification routing, overlay management, and keyboard monitor setup into separate files. Pure refactor. Done: split into ContentView.swift (layout) and ContentView+Handlers.swift (event routing).
- [x] `/cleanup` **Sidebar interaction audit**: review sidebar tap targets, hover states, and accessibility traits after the visual rework. Ensure VoiceOver reads session/tab hierarchy correctly. Done: tap targets correct, accessibility labels added for bell, pane count, tab count.

## Phase 1c: Auto-Hide Panels

**Why here:** screen real estate is everything for a terminal. Without this, the sidebar and tab bar eat space permanently.

Sidebar and tab bar support Pinned / Auto-hide / Hidden modes. Auto-hide: overlay slides in on edge hover (150ms dwell, 20px trigger zone), out on mouse leave (300ms delay). Panels overlay terminal content (no resize/reflow). Keyboard shortcuts always work regardless of mode.

- Complexity: 2
- [x] `/spec` review: spec updated with Iteration 4 (hide-when-single-tab interaction, WezTerm-style config shape).
- [x] `d088f29` feat(ui): add auto-hide panels for sidebar and tab bar. Three modes (pinned/auto-hide/hidden), EdgeTriggerView with NSTrackingArea, modal suppression, Reduce Motion support, Settings UI pickers.

**Future opportunity:** live config reload (watch config file with DispatchSource, push changes to PanelState without restart). Panel modes are good candidates since they don't require terminal reflow.

**Done when:** ~~sidebar and tab bar can be set to auto-hide, panels overlay without reflowing terminal content, keyboard shortcuts work in all modes. Menu commands target the correct window in multi-window (verified by @FocusedValue migration in cleanup gate).~~ Done 2026-04-14. Visually verified all six acceptance criteria.

---

### Cleanup gate (before Phase 2)
- [x] `/cleanup` **Swiftlint + swift format pass**: `2d4522c` style: swift format pass. Zero violations.
- [x] `/cleanup` **Test coverage audit**: `c6e79ee` test: PanelStateTests, MisttyConfigTests additions, MisttySessionTests. 275 → 304 tests. Remaining gaps: manager classes (NSEvent-dependent), view files (need UI tests).
- [x] `/refactor` **Manager pattern review**: evaluated. The 4 managers share ~8 lines of boilerplate (monitor field, isActive guard, deactivate cleanup) but differ in activate signatures, state shape, and event handling. CopyMode has exit/deactivate split. Extraction not warranted (shared code is trivial, managers won't change together). Pattern for Phase 2's attention coordinator: `@Observable` class, `@ObservationIgnored nonisolated(unsafe) var monitor: Any?`, `isActive` flag, `activate(...)` installs `NSEvent.addLocalMonitorForEvents(.keyDown)`, `deactivate()` removes monitor and nils state.
- [x] `/cleanup` **MisttyTheme token audit**: all existing tokens in use. Added `panelOverlayShadow` and `autoHideHint` tokens for Phase 1c hardcoded colors.

## Phase 2: Contextual Sidebar

**Why this phase:** the sidebar is Mistty's most visible differentiator from Ghostty. Right now it's a list of names. This phase makes it the "you never leave your flow" feature.

Merges OSC foundation and rich sidebar metadata into one coherent feature.

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
Command boundary detection from the OSC parser. Cmd+Up/Down to jump between prompts, per-command exit code and duration display. Line-level navigation; 6b upgrades this to visual block selection. Enables 6b (block-based output).

- Complexity: 3 (largest phase; the OSC parser is shared infrastructure, consumers are incremental)
- Gap analysis: cmux has notification rings. No one else combines notifications + git + ports + working directory in a sidebar.
- `/spec` required: OSC parser architecture, notification ring visual design, sidebar metadata layout, OSC title sequence handling (OSC 0/1/2 for session/tab renaming). Prior art: `/tmp/ai-research-sidebar-patterns.md`, `/tmp/ai-research-terminal-ui-ux-patterns.md`.

**Done when:** sidebar shows git branch, working directory, and port info per session. Unfocused panes with output show notification badges. Cmd+Shift+U jumps to the next unread pane. Cmd+Up/Down jumps between prompts. OSC 0/1/2 title sequences update tab names dynamically.

---

### Cleanup gate (before Phase 3)
- [ ] `/refactor` **IPC audit**: review existing IPCService.swift and IPCListener.swift. Use `/refactor` to evaluate: understand current IPC mechanism before designing socket API replacement. Document what works, what's fragile, what the socket API replaces vs extends.
- [ ] `/cleanup` **OSC parser test coverage**: ensure OSC parser from Phase 2 has tests covering all supported sequences before building socket API on top.
- [ ] `/cleanup` **IPC parity check**: verify all stable noun+verb operations from Phases 1b and 2 have IPC methods per Principle 10. Backfill any gaps (session rename, tab move, etc.).

## Phase 3: Platform

**Why this phase:** the socket API is the foundation for neovim navigation (personal pain point), CLI scripting, Raycast/Hammerspoon integration, and future automation. Phase 2 and Phase 3 are independent; choose one to complete first. Recommend Phase 2 first (daily-driver value, unblocks 6b).

### 3a. Socket API + CLI
Unix domain socket (`/tmp/mistty-$UID.sock`). JSON-RPC protocol. Extends the existing `MisttyCLI` binary (currently uses direct IPC) to use the socket as transport. Access control via file permissions.

- Complexity: 3
- `/spec` required: protocol design (JSON-RPC methods, error codes), migration plan from current IPC. Include session/tab rename methods for CLI integration.
- Enables: 3b, Raycast/Hammerspoon integration, scripting, CLI rename commands

### 3b. Neovim Split Navigation
smart-splits.nvim integration via socket API. Bidirectional Ctrl+h/j/k/l between neovim splits and Mistty panes.

- Complexity: 2 (once 3a exists)
- `/spec` required: smart-splits.nvim integration protocol, edge cases (nested neovim, multiple neovim instances).
- Depends on: 3a
- Why unsolved in Ghostty: deliberate design choice (no IPC). Mistty can solve it.
- Personal pain point.

### 3c. Basic Session Persistence
Save session/tab/pane tree to disk on quit. Restore layout on launch (shells restart fresh). Uses `Codable` serialization of the session tree + `NSApplicationDelegate.applicationShouldTerminate`.

- Complexity: 2
- `/spec` required: what state is saved (session names, tab names, pane layout, working directories), serialization format, restore behavior when shells can't restart.
- Does not depend on 3a (socket API) or config system.
- Advanced version (scrollback persistence, shpool/zmx integration) stays in Phase 4b.

**Done when:** `mistty pane list` returns JSON, Ctrl+h/j/k/l crosses neovim/Mistty boundary, quit+relaunch restores session layout.

---

### Cleanup gate (before Phase 4)
- [ ] `/cleanup` **Config audit**: catalog every hardcoded value that users have wanted to change during daily driving (keybindings, colors, panel modes, hotkeys, tab bar visibility mode). This becomes the requirements list for the config system spec.
- [ ] `/refactor` **MisttyTheme review**: by this point the theme file has been in use for several phases. Use `/refactor` to evaluate: is the token set complete? Are any tokens unused? Is the abstraction right for supporting multiple preset themes and the generative color system from the research?

## Phase 4: Configuration + Persistence

**Why deferred to here:** by this point you've used the app daily for weeks and know what actually needs configuring. The investigation is grounded in real usage, not speculation.

### 4a. Configuration System
Research and build Mistty's configuration system. Keybindings, appearance, behavior, panel modes.

- `/spec` required: full design doc. Investigation scope, format decision, what's configurable vs opinionated, preset themes vs arbitrary values, tab title templates (Kitty-style `{title}`, `{index}`). Prior art research exists; needs a decision spec.
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

### 4b. Advanced Session Persistence
Extends 3c with scrollback persistence, running command restoration, and optional shpool/zmx integration for shell survival across app restarts.

- `/spec` required: scrollback serialization format, shpool/zmx integration decision, migration from basic persistence (3c).
- Complexity: 3 (built-in) or 2 (shpool/zmx integration)
- Depends on: 3c

**Done when:** config file controls keybindings and appearance, advanced persistence restores scrollback and running commands.

---

### Cleanup gate (before Phase 5)
- [ ] `/cleanup` **Integration test coverage**: ensure socket API (3a) and config system (4a) have tests covering the interfaces that Phase 5 features build on. 5a and 5c depend directly on these.
- [ ] `/refactor` **API stability review**: review socket API method signatures and config file format for breaking changes before building features on top of them.
- [ ] `/cleanup` **Dead code sweep**: remove any unused code, stale feature flags, or temporary workarounds accumulated during Phases 2-4.

## Phase 5: Differentiators

### 5a. Declarative Project Layouts
`.mistty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects. `start_suspended` option for panes that show the command but don't execute until Enter.

Includes Layout Manager UI: "Save current layout" command that generates `.mistty.toml` from the live workspace.

- Complexity: 2
- `/spec` required: file format, trust model, layout manager UI design.
- Depends on: 4a (config format), 3c (layout serialization format)

### 5b. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden. Drag to reposition.

- Complexity: 3
- `/spec` required: z-ordering, resize behavior, keyboard navigation between floating and tiled panes.
- 201 votes on Ghostty. Mistty's SwiftUI architecture makes this easier than Ghostty's renderer-level splits.

### 5c. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

- Complexity: 2
- `/spec` required: which Ghostty config keys to support, conflict resolution with Mistty config.

### 5d. Hints Mode
Press a trigger key, all visible URLs/paths/hashes get short letter labels. Type the label to act (open, copy, insert). Keyboard-driven alternative to clicking links.

- Complexity: 2
- `/spec` required: label assignment algorithm, action menu, visual overlay design. Prior art: Kitty hints kitten.
- Kitty ships this ("hints kitten"). Ghostty has ~180 combined votes across related discussions.
- Pairs with 6c (inline preview panes): hints selects targets, previews displays them.

### 5e. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts. Lower priority because which-key (1a) covers discoverability.

- Complexity: 2
- `/spec` required: action registry, search ranking, visual design. Prior art: Raycast, Nova, Linear.

### 5f. Enhanced Session Manager
Enhance existing Cmd+J session manager: frecency-ranked directories (zoxide integration already exists), Nerd Font icons, preview pane showing recent output. Cmd+\` for instant last-workspace toggle.

- Complexity: 2
- `/spec` required: preview pane content, icon mapping, frecency algorithm tuning.

### 5g. Sidebar Position
Sidebar configurable to appear on left or right side of the window.

- Complexity: 1
- `/spec` not needed (straightforward layout flip).
- Depends on: 4a (config system for persistence)

### 5h. Dropdown / Quake / Float Mode
Global hotkey summons a dropdown terminal (NSPanel). Also support floating terminal windows that overlay other apps.

- Complexity: 3
- `/spec` before implementation: NSPanel, global hotkey, animation, multi-monitor behavior, interaction with auto-hide panels. Also design float variant (persistent overlay window, not just dropdown).
- Prior art: Guake, Yakuake, iTerm2 hotkey window, Ghostty QuickTerminal (study for edge cases: screen switching, activation policy, window level, animation timing).
- Does not depend on other Phase 5 items.

**Done when:** project layouts load from `.mistty.toml` with save-current-layout command, floating panes work, Ghostty themes import, hints mode selects visible targets, command palette searches all actions, session manager shows frecency-ranked results with icons, global hotkey summons dropdown terminal, floating terminal windows overlay other apps, panel animations feel polished.

### 5i. Panel Animation Polish
Refine sidebar and tab bar reveal/dismiss animations to feel more satisfying. Current implementation uses basic easeOut/easeIn curves. Investigate spring animations, velocity-matched transitions, and subtle scale/opacity effects. Reference: Zen Browser's sidebar animations.

- Complexity: 1
- `/spec` not needed (iterative visual tuning).
- Depends on: 1c (auto-hide panels, done)

---

## Phase 6: Moonshots

### 6a. Native tmux Control Mode
Render tmux panes as native Mistty splits via `tmux -CC`. The headline feature. Only iTerm2 has this.

- Complexity: 5
- `/spec` required: full design doc. Protocol analysis, sync model, edge case catalog. Study iTerm2's implementation.
- Defensible moat: hard to copy.
- Ghostty's tmux control mode is in progress (DCS parser landed as of 2026-04-14). If it ships, Mistty could use libghostty's tmux support to render tmux panes as native splits, reducing the implementation effort here.

### 6b. Block-Based Output
Command+output as selectable blocks. Metadata: exit code, duration, cwd. Click to select entire block. Cmd+Up/Down to navigate.

- Complexity: 4
- `/spec` required: block detection from OSC 133, visual design, selection model, keyboard navigation.
- Depends on: Phase 2 (shell integration / OSC 133)
- Extends Phase 2 shell integration: upgrades line-level prompt navigation to visual block selection with metadata.
- Only Warp has this.

### 6c. Inline Preview Panes
Hover file paths in terminal output for Quick Look preview. Click to open in split pane.

- Complexity: 4
- `/spec` required: path detection, Quick Look integration, split-pane creation flow.
- No terminal does this. Novel.
- Pairs with 5d (hints mode provides keyboard-driven target selection).

### 6d. Terminal Automation API
Expose surface state (cells, colors, cursor position) via the socket API for scripting and testing. The "Playwright for terminals" gap: AI agents can write TUI code but can't see the rendered result.

- Complexity: 3
- `/spec` required: API surface, read vs write operations, security model.
- Depends on: 3a (socket API)
- Only ghostty-automator exists in this space, and it's Ghostty-specific.

### 6e. SSH Workspace Creation
`mistty ssh user@host` creates a dedicated workspace with port detection, sidebar metadata, and proper cleanup on disconnect. Optional Eternal Terminal (`et`) integration for connection persistence.

- Complexity: 4
- `/spec` required: workspace lifecycle, port detection mechanism, et integration model.

---

## Dependency Graph

```
Completed:
  Phase 0 (cleanup) ✓
  Phase 1a (which-key) ✓
  Phase 1b partial (beep fix, divider, tab contrast, typography, pane dim, sidebar mute) ✓
  Phase 1b cleanup gate: theme extraction ✓
  Phase 1b: sidebar visual rework ✓
  Phase 1b: tab-completion beep fix (doCommand override) ✓

Sequential path (solo developer, no parallel phases):
  1b remaining (rename, tab-bar-visibility, drag-drop) ✓
    ──> /refactor + /cleanup: FocusedValue migration, ContentView extraction, sidebar audit
      ──> /spec review: auto-hide panel spec update
        ──> 1c (auto-hide)
          ──> /cleanup + /refactor: lint, tests, manager review, theme audit
            ──> /spec: Phase 2 (OSC parser, notification rings, sidebar metadata, OSC titles)
              ──> Phase 2 (contextual sidebar + OSC + shell integration)
                ──> /refactor + /cleanup: IPC audit, OSC parser tests
                  ──> /spec: Phase 3 (socket API protocol, session persistence, CLI rename methods)
                    ──> Phase 3 (socket API + neovim nav + basic session persistence)
                      ──> /cleanup + /refactor: config audit, theme review
                        ──> /spec: Phase 4 (config format, tab title templates)
                          ──> Phase 4 (config + persist)
                            ──> /cleanup + /refactor: integration tests, API stability, dead code
                              ──> Phase 5 (differentiators incl. dropdown/float, each with /spec)
                                ──> Phase 6 (moonshots, each with /spec)

Late dependencies:
  Phase 2 ──> 6b (block-based output)
  Phase 3a ──> 6d (automation API)
  Phase 4a ──> 5a (layouts), 5c (Ghostty compat), 5g (sidebar position)
  Phase 3c ──> 5a (layouts)
  5d (hints) ──> 6c (inline previews)
  Phase 3c ──> 4b (advanced persistence)
  Phase 4a ──> 5h (dropdown hotkey config; hardcoded hotkey works without config, like Phase 1a keybindings)
```

## What's NOT on this roadmap

- **Daemon architecture**: evaluated and deferred. A headless process owning sessions (like tmux's server) would give CLI/GUI parity and attach/detach, but the daemon-to-surface rendering bridge is unsolved for native GUI terminals. The IPC protocol boundary is the escape hatch if this becomes needed later.
- **Alternative terminal base**: evaluated WezTerm (stalled, last release 2024-02) and Kitty (strong IPC but no embeddable library). Neither is embeddable. libghostty is the only option for a native macOS app with custom UI chrome.
- CI/CD (GitHub Actions): deferred until contributors exist
- IPC service refactoring as standalone effort: works, not broken. Phase 3 cleanup gate audits it as input to socket API design.
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
- Ghostty scripting API (planned, no timeline; 109+ comments on Discussion #2353)
- Ghostty tmux control mode (in progress; DCS parser landed, Issue #1935)

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
- /tmp/ai-design-sidebar-visual-rework.md (sidebar visual rework spec, 2026-04-14)
- /tmp/ai-research-ghostty-planned-features.md (Ghostty feature overlap analysis, 2026-04-14)
- /tmp/ai-research-ghostty-rejected-features.md (Ghostty rejected/out-of-scope features, 2026-04-14)
- /tmp/ai-research-wezterm-kitty-comparison.md (WezTerm and Kitty comparison, 2026-04-14)
- /tmp/ai-design-session-tab-renaming.md (session/tab renaming spec, 2026-04-14)
- /tmp/ai-design-tab-drag-drop.md (tab drag-and-drop spec, 2026-04-14)