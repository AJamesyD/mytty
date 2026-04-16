# Mistty Roadmap

Created: 2026-04-14
Last updated: 2026-04-15
Iteration: 21

## Working Agreements

Design tenets and architecture constraints: see [docs/DESIGN.md](DESIGN.md).

These are process and scope rules that govern the roadmap:

0. **macOS-only**: no Windows, ever. Linux is a distant stretch goal. Lean fully into SwiftUI and AppKit, use macOS system APIs directly (NSPanel, NSUserActivity, CGEvent taps), no cross-platform abstraction layers.
1. **Time to daily driver**: optimize for the shortest path to replacing your current terminal setup.
2. **Personal-first, generalizable**: solve your own workflow pain, design interfaces that generalize.
3. **Infrastructure ships with features**: build plumbing when a feature needs it, not before.
4. **Dependency-ordered**: phases are sequenced by what unblocks what. No fake timelines.
5. **Opinionated defaults, constrained configuration**: ship one good design. When configuration is needed, prefer presets over arbitrary values. Don't push design decisions to the user. Code must be written with the assumption that hardcoded values will become configurable later: access through abstractions (e.g., `theme.surface` not `Color.white.opacity(0.03)`), even when the backing store is a static singleton.
6. **Principle of Least Astonishment**: follow macOS conventions wherever possible. Standard shortcuts (Cmd+S, Cmd+X, Cmd+C/V, Cmd+Q, Cmd+H, Cmd+Shift+]/[) must not be overridden for non-standard purposes. When Mistty needs a shortcut, pick one that doesn't conflict with universal macOS muscle memory. Custom behaviors (modes, which-key, split panes) are fine where macOS has no convention, but defaults should never surprise a user coming from another macOS app. Research: `/tmp/ai-research-macos-native-divergence-framework.md`.

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
- ~~Dropdown / Quake mode~~: moved to Phase 5 as 5a (not blocking daily driver use).

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

## Phase 2a: OSC Foundation

**Why this phase:** the sidebar is Mistty's most visible differentiator from Ghostty. Right now it's a list of names. This phase and 2b make it the "you never leave your flow" feature. The action callback handlers are shared infrastructure that Phase 2b, Phase 4c, and Phase 6b depend on.

- Handle libghostty OSC action callbacks (PWD, SET_TAB_TITLE, DESKTOP_NOTIFICATION, COMMAND_FINISHED, PROGRESS_REPORT)
- Working directory tracking per pane (from OSC 7 via PWD action)
- Title priority chain: customTitle > tabTitle > processTitle > "Shell"
- 75ms title debounce, 15s progress auto-expiry
- Desktop notifications via UNUserNotificationCenter (suppressed when pane is focused)

Key finding: libghostty already parses all OSC sequences internally. Phase 2a handles the typed action callbacks, not raw escape sequences.

- Complexity: 2
- [x] `/spec`: `/tmp/ai-design-phase2a-osc-foundation.md`
- [x] `48c15ac` feat(terminal): handle libghostty OSC action callbacks

**Done when:** ~~OSC parser handles all listed sequences, sidebar shows working directory per session, OSC title sequences update tab names.~~ Done 2026-04-14. All six acceptance criteria met.

## Phase 2b: Contextual Sidebar ✅

The consumer features that build on Phase 2a's action callbacks. Spec: `/tmp/ai-design-phase2b-contextual-sidebar.md`.

### Notification Badges
Leading glow dots on tab rows (6px Circle with color-matched shadow: red for bell, orange for command failure). Session-level rollup as count pill (Mail-style) on collapsed sessions. Command-boundary notifications only (COMMAND_FINISHED), not output-based. Bell stays immediate. Identity (accent bar) and status (dots) are independent visual channels.

### ~~Rich Sidebar Metadata~~ (reverted)
~~Session-level only for v1: git branch + dirty indicator and working directory on the session row.~~
Reverted: git branch and working directory are per-pane data. Sessions are units of work that can span multiple repos. Even tabs can have split panes in different directories. The sidebar is an awareness channel for background activity, not a metadata display for the active pane. The shell prompt already shows branch and directory. Git detection infrastructure will return when a real consumer exists (status bar, project layouts).

### Shell Integration (OSC 133)
Tab row shows process title (left, running indicator) + last command result (right-aligned: checkmark/X + duration). Process title from SET_TITLE serves as the running-state indicator ("cargo" = running, "zsh" = idle). Prompt navigation via `jump_to_prompt` binding action (confirmed in Ghostty source). Cmd+Shift+Up/Down to jump between prompts.

Design decisions (8 total, each with presupposition and revisit condition) documented in spec. Key decisions:
- D1: Process title as running indicator (revisit when libghostty exposes OSC 133 C)
- D2: ~~macOS-native SF Symbols, not colored dots~~ Reversed: glow dots (pre-attentive) over SF Symbols (cognitive). Identity and status are independent channels.
- D3: ~~Session-level metadata only~~ Reverted: per-pane data doesn't belong at session level. Sessions span repos.
- D5: No "unread output" for v1 (revisit when socket API provides output events)
- D6: Success is quiet, failure is loud (revisit if users want long-command success notifications)
- D7: jump_to_prompt confirmed feasible via ghostty_surface_binding_action
- D9 (from review): 200ms debounce on git detection triggers (coalesces rapid COMMAND_FINISHED)

Port detection (lsof integration) removed from Phase 2b scope. Standalone item, no dependency on 2b. Candidate for Phase 5 polish.

- Complexity: 2
- Gap analysis: cmux has notification rings. No one else combines notifications + git + ports + working directory in a sidebar.
- [x] `/spec`: `/tmp/ai-design-phase2b-contextual-sidebar.md` (with decision log D1-D8)
- Depends on: 2a (done)

### Clipboard Paste (Cmd+V)
`readClipboardCallback` in `GhosttyApp.swift` is a stub: reads `NSPasteboard.general` but never calls `ghostty_surface_complete_clipboard_request` to deliver text back to Ghostty. Returns `false` unconditionally. Copy (Cmd+C) works because `writeClipboardCallback` is complete. Fix: complete the callback following the pattern in `vendor/ghostty/macos/Sources/Ghostty/Ghostty.App.swift` (`readClipboard`). Also complete `confirmReadClipboardCallback` for unsafe-paste confirmation.

- Complexity: 1
- Standalone fix, no spec needed.

**Done when:** ~~background tab failures show orange glow dot, collapsed sessions show count pill, tab row shows process title + last command result, Cmd+Shift+Up/Down jumps between prompts, Cmd+V pastes clipboard content into terminal.~~ Done 2026-04-14.

## Phase 2c: Basic Session Persistence

Save session/tab/pane tree to disk on quit. Restore layout on launch (shells restart fresh). Codable JSON to `~/.config/mistty/sessions.json`.

- Saves on willTerminate (immediate) and didResignActive (2s debounce)
- Restores with fresh IDs, missing directories fall back to home
- Prefers workingDirectory (OSC 7, Phase 2a) over initial directory
- Graceful fallback on corrupt, missing, or version-mismatched JSON

- Complexity: 2
- [x] `/spec`: `/tmp/ai-design-phase2c-session-persistence.md`
- [x] `9f2fbf8` feat(persistence): save and restore session tree across app restarts
- Does not depend on 2a or 2b. Built in parallel.

**Done when:** ~~quit+relaunch restores session layout with correct names and working directories.~~ Done 2026-04-14. All five acceptance criteria met.

---

### Cleanup gate (before Phase 3)
- [x] `/refactor` **Event handler extraction**: extract NSEvent monitor closure bodies into testable `handleKeyDown(_ event: NSEvent) -> NSEvent?` methods on each manager (WindowMode, CopyMode, WhichKey, PaneNavigation, and Phase 2's attention coordinator). Monitor becomes a one-liner that delegates. Tests call the method directly with `NSEvent.keyEvent(with:...)`. Research: `/tmp/ai-research-nsevent-testing.md`. Done: `d8e7336`.
- [x] `/refactor` **IPC audit**: review existing IPCService.swift and IPCListener.swift. Use `/refactor` to evaluate: understand current IPC mechanism before designing socket API replacement. Document what works, what's fragile, what the socket API replaces vs extends. Done: `/tmp/ai-research-ipc-audit.md`.
- [x] `/cleanup` **OSC action handler test coverage**: ensure Phase 2a action handlers and Phase 2b notification/git logic have tests covering all supported actions before building socket API on top. Done: `5a51875`.
- [x] `/cleanup` **IPC parity check**: verify all stable noun+verb operations from Phases 1b, 2a, and 2b have IPC methods per the IPC parity commitment (see DESIGN.md). Backfill any gaps (session rename, tab move, etc.). Done: `c071d82` (added `renameSession`, `moveTab`).

## Phase 3: Platform

**Why this phase:** the socket API is the foundation for neovim navigation (personal pain point), CLI scripting, Raycast/Hammerspoon integration, and future automation. Recommend completing Phase 2 first (daily-driver value, unblocks 6b).

**Contingency:** Ghostty is actively designing a text protocol for runtime control (Discussion #2353). If Ghostty ships IPC before Mistty reaches Phase 3, evaluate adopting Ghostty's protocol as transport instead of building a custom socket API. This could reduce 3a scope and accelerate 3b (neovim nav).

### 3a. Socket API + CLI ✅
JSON-RPC 2.0 over persistent Unix domain socket connections with Content-Length framing. All 31 service methods migrated to `noun.verb` naming. Structured error codes (1001-1004). Event subscription via `subscribe`/`unsubscribe`. MisttyServiceProtocol migrated to async/await, semaphore bridges eliminated. EventBroker actor ready for model integration.

- Spec: `docs/specs/phase3a-socket-api.md`
- Research: `/tmp/ai-research-jsonrpc-terminal-ipc.md`

### 3b. Neovim Split Navigation ✅
Bidirectional Ctrl+h/j/k/l between neovim splits and Mistty panes via smart-splits.nvim backend. IPC-based pane variables for vim detection (OSC 1337 SetUserVar not available in libghostty). Process detection kept as fallback.

- Spec: `docs/specs/phase3b-neovim-navigation.md`
- Backend: `extras/neovim/lua/smart-splits/mux/mistty.lua`
- New IPC methods: `pane.atEdge`, `pane.setVar`, `pane.getVar`
- Env vars: `MISTTY_SOCKET`, `TERM_PROGRAM=mistty`

---

### Cleanup gate (before Phase 4)
- [x] `/cleanup` **Config audit**: catalog every hardcoded value that users have wanted to change during daily driving (keybindings, colors, panel modes, hotkeys, tab bar visibility mode). Done 2026-04-15: `/tmp/ai-research-config-audit.md`. ~50 keybindings, 7 raw colors (fixed), ~15 behavior values.
- [x] `/refactor` **MisttyTheme review**: 29 tokens, all raw colors in views extracted. 5 new tokens added (bellGlow, commandSuccessIndicator, sessionManagerShadow, windowModeHUD, copyModeKeyBadge). Zero raw Color literals remain in view files.

## Phase 4: Configuration + Persistence

**Why deferred to here:** by this point you've used the app daily for weeks and know what actually needs configuring. The investigation is grounded in real usage, not speculation.

### 4a. Configuration System

Config file (`~/.config/mistty/config.toml`) is the single source of truth. Settings GUI is read-only (shows current values + "Open Config File" button). See ADR-006.

- Spec: `docs/specs/phase4a-config-keybindings.md`
- Config audit: `/tmp/ai-research-config-audit.md`
- Complexity: 3
- Retroactively enhances: which-key (1a reads keybindings from config), auto-hide (1c modes configurable)
- Enables: 4b (live reload), 5d (Ghostty config compat), 5e (project layouts)

#### 4a-1: Config parsing infrastructure ✅
TriggerParser, KeybindingStore, TOML `[keybindings]` section parsing. Per-mode sections (global, window-mode, copy-mode), action-as-key format, `unconsumed:` prefix, merge/override/unbind/reset semantics.

- `d94b10f` docs: Phase 4a configurable keybindings spec
- `3ee6e13` feat: TriggerParser, KeybindingStore, keybindings parsing

#### 4a-2: Wire global keybindings ✅
Menu shortcuts (MisttyApp), pane navigation (PaneNavigationManager), and passthrough process list (MisttyPane) read from KeybindingStore. `unconsumed:` triggers call `ghostty_surface_key_is_binding()` to let ghostty claim keys before Mistty intercepts. Settings GUI replaced with read-only config viewer.

- `22af138` feat: wire global keybindings from KeybindingStore
- `d37a787` refactor: rename vimLikeProcesses to passthroughProcesses
- `e1167bc` fix: replace writable Settings GUI with read-only config viewer

#### Doc maintenance (between 4a-2 and 4a-3)
- [x] Fix stale facts in steering docs (GhosttyKit import list)
- [x] Update README (project structure, architecture link)
- [x] Add config system rules to steering docs
- [x] ADR-006: config-file-only approach
- [x] Archive old plan/implementation transcripts to docs/archive/

#### Hardening gate (4a-2) ✅
- [x] Tests for `toKeyboardShortcut()` conversion (7 tests)
- [x] Tests for `isPassthroughProcess(processes:)` with custom lists (1 test)
- [x] Tests for PaneNavigationManager key matching logic (5 tests)
- [x] Fix special key matching (arrow keys, escape) via keycode-to-name mapping

#### Bug fix: Ctrl+hjkl navigation unreliable ✅
PaneNavigationManager uses `event.charactersIgnoringModifiers` to extract the key character. On macOS, this returns control characters when Ctrl is held (Ctrl+H = `\u{08}`, Ctrl+J = `\n`, Ctrl+K = `\u{0B}`, Ctrl+L = `\u{0C}`) instead of the letter. Ghostty's own code explicitly avoids this (see `NSEvent+Extension.swift` comment: "We have to use `byApplyingModifiers` instead of `charactersIgnoringModifiers` because the latter changes behavior with ctrl pressed"). Fix: use `event.characters(byApplyingModifiers: [])?.lowercased()` instead. Standalone fix, no spec needed.

- Complexity: 1
- [x] Fix `PaneNavigationManager.handleKeyDown` to use `characters(byApplyingModifiers: [])` instead of `charactersIgnoringModifiers`

#### 4a-2b: Native keybinding defaults ✅
Apply Principle of Least Astonishment to default keybindings. All changes are to `KeybindingStore.defaultBindings` only; existing user configs are unaffected.

- [x] Change `toggle-sidebar` default from `Cmd+S` to `Cmd+\` (Cmd+S is "Save" in every macOS app)
- [x] Change `window-mode` default from `Cmd+X` to `Ctrl+W` (Cmd+X is "Cut" universally; Ctrl+W is the tmux prefix convention. Conflicts with shell word-delete, but configurable.)
- [x] Change `next-tab` default from `Cmd+]` to `Cmd+Shift+]` (matches Safari, Chrome, Finder)
- [x] Change `previous-tab` default from `Cmd+[` to `Cmd+Shift+[` (matches Safari, Chrome, Finder)
- [ ] Add `Cmd+W` behavior config option: "multiplexer" (Cmd+W closes pane, default) vs "macos" (Cmd+W closes tab). Deferred: current default is correct for multiplexer identity. Revisit if users request.
- [ ] Document Ctrl+Space conflict with macOS input source switcher in config spec

Research: `/tmp/ai-research-macos-native-divergence-framework.md`

- Complexity: 1
- Depends on: 4a-2

#### 4a-3: Wire modal keybindings ✅
Replace hardcoded keybindings in WindowModeManager and WhichKeyManager with store lookups. CopyModeState deferred: no terminal emulator (Ghostty, kitty, WezTerm) makes vim copy-mode keys configurable, and the 622-line state machine would need a full rewrite to become data-driven. Vim users expect vim keys.

- Depends on: 4a-2b
- Research: `/tmp/ai-research-phase4a3-modal-keybindings.md`
- WindowModeManager: convert keyCode dispatch to action-name lookup from store
- WhichKeyManager: read `whichKeyGroups` from store, map action names to closures

### 4b. Live Config Reload ✅
Watch config file with `DispatchSource.makeFileSystemObjectSource`. Reload on change. Panel modes, fonts, colors, and keybindings apply immediately. Terminal-affecting options (scrollback size) apply to new panes only.

- Complexity: 1
- `/spec` not needed (straightforward file watcher + partial apply).
- Depends on: 4a
- `6670121` feat(config): live config reload via file watcher

### 4c. Advanced Session Persistence
Extends 2c with scrollback persistence, running command restoration, and optional shpool/zmx integration for shell survival across app restarts.

- `/spec` required: scrollback serialization format, shpool/zmx integration decision, migration from basic persistence (2c).
- Complexity: 3 (built-in) or 2 (shpool/zmx integration)
- Depends on: 2c

### 4d. Sidebar Configuration ✅
- Sidebar position: configurable left or right (`sidebar.position = "left" | "right"`)
- Sidebar tree depth: configurable whether tabs/panes show under sessions or sessions only (`sidebar.show-tree = true | false`)
- Spec: `/tmp/ai-design-phase4d-sidebar-config.md`
- Complexity: 2
- Depends on: 4a (config system)
- `b928716` feat(sidebar): add position and show-tree config

### 4e. Auto-Hide UX Polish
Revisit auto-hide panel behavior with better animations and tuning. Studied Zen Browser, macOS Dock, Arc Browser, and Apple HIG for prior art.

- [x] Spring animation (critically damped, interruptible) replacing bezier curves
- [x] Reduce Motion: opacity fade instead of slide (accessibility correctness)
- [x] Hint bar: 3x28px at 0.2 opacity (was 2x24px at 0.15)
- Complexity: 1
- Depends on: 4a (config system for tuning values), 1c (auto-hide panels)

Deferred (tracked for future work):
- [ ] Dismiss-while-browsing fix: add hover tracking to revealed panel body. Currently EdgeTriggerView only tracks the 20px trigger strip; cursor in the panel body starts the dismiss timer. The 300ms dismiss delay masks this.
- [ ] Popup/context menu suppression: keep panel open while context menus are active (SidebarView has context menus at 2 sites, TabBarView at 1). Pattern from Zen Browser.
- [ ] Asymmetric show/hide animation: faster show (response: 0.2), slower hide (response: 0.3)
- [ ] Flash sidebar on background session events (bell, exit): briefly reveal for ~800ms. Pattern from Zen Browser.
- [ ] Escape-to-dismiss auto-hide panel (conflicts with terminal Escape key; needs design)

Research: /tmp/ai-research-autohide-ux-prior-art.md

**Done when:** config file controls keybindings (global + window mode + which-key), sidebar position and tree depth are configurable, auto-hide panels feel polished, config changes apply without restart.

---

### Cleanup gate (before Phase 5)
- [x] **Scene body perf fix**: cache MisttyConfig in MisttyApp @State (eliminates 26x disk reads per focus change) and stabilize TerminalCommands identity (reduces unnecessary scene re-evaluations). Also fixed PersistenceService actor isolation warnings.
- [ ] `/cleanup` **Integration test coverage**: ensure socket API (3a) and config system (4a) have tests covering the interfaces that Phase 5 features build on. 5d and 5e depend directly on these.
- [ ] `/refactor` **API stability review**: review socket API method signatures and config file format for breaking changes before building features on top of them. Socket API reviewed 2026-04-15: `/tmp/ai-review-api-stability.md`. Config format review deferred to Phase 4a.
- [x] `/cleanup` **Dead code sweep**: codebase is clean. Removed 1 dead function (`notImplemented` in IPCService) and 2 redundant imports. Systematic scan found no other dead code.

### 4f. Keybinding System Upgrade
Bring keybinding configurability to Ghostty parity, then exceed it. Current system only supports single key combos with `unconsumed:` prefix.

**4f-1. Key sequences** (priority: high, blocks daily use)
Parse `ctrl+a>h` syntax in TriggerParser. Add sequence state machine to PaneNavigationManager and WhichKeyManager. Timeout after 1s (configurable). This alone unblocks tmux-style `ctrl+a>h/j/k/l` navigation.
- Complexity: 2

**4f-2. Global hotkeys** (priority: high, needed for 5a)
System-wide hotkey registration via `CGEvent` tap or `NSEvent.addGlobalMonitorForEvents`. Requires accessibility permissions. Needed for dropdown terminal (5a), though 5a can ship with a hardcoded hotkey first.
- Complexity: 2

**4f-3. Key tables and modal bindings** (priority: medium)
Named binding sets activated/deactivated at runtime. Generalizes which-key into a single mechanism; copy mode adopts key tables for top-level dispatch but retains its internal state machine. `performable:` prefix (only consume if action can execute). `all:` prefix (broadcast to all surfaces). Chained actions.
- Complexity: 3
- Ghostty features: `activate_key_table:<name>`, one-shot mode, `performable:`, `all:`, chained actions, `keybind=clear`

**4f-4. Beyond Ghostty** (stretch, no timeline)
Ideas for future consideration, not planned work:
- Conditional bindings (bind differently based on running process, pane count, or mode)
- tmux-style `bind-key -r` (repeatable prefix within a timeout)
- Zellij-style named modes with visual indicators
- User-defined key tables loadable from separate files

Current gap: `ctrl+a>h/j/k/l` navigation (Ghostty default) doesn't work in Mistty.

## Phase 5: Differentiators

### Essential

### 5a. Dropdown / Quake / Float Mode
Global hotkey summons a dropdown terminal (NSPanel). Also support floating terminal windows that overlay other apps.

- Complexity: 3
- `/spec` before implementation: NSPanel, global hotkey, animation, multi-monitor behavior, interaction with auto-hide panels. Also design float variant (persistent overlay window, not just dropdown).
- Prior art: Guake, Yakuake, iTerm2 hotkey window, Ghostty QuickTerminal (study for edge cases: screen switching, activation policy, window level, animation timing).
- Does not depend on other Phase 5 items. Hardcoded hotkey works without config, like Phase 1a keybindings.

### 5b. Hints Mode
Press a trigger key, all visible URLs/paths/hashes get short letter labels. Type the label to act (open, copy, insert). Keyboard-driven alternative to clicking links.

- Complexity: 2
- `/spec` required: label assignment algorithm, action menu, visual overlay design. Prior art: Kitty hints kitten.
- Kitty ships this ("hints kitten"). Ghostty has ~180 combined votes across related discussions.
- Pairs with 6c (inline preview panes): hints selects targets, previews displays them.

### 5c. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden. Drag to reposition.

- Complexity: 3
- `/spec` required: z-ordering, resize behavior, keyboard navigation between floating and tiled panes.
- 201 votes on Ghostty. Mistty's SwiftUI architecture makes this easier than Ghostty's renderer-level splits.

### Polish

### Cleanup gate (before Phase 5 Polish)

**VoiceOver Accessibility Audit**: audit all custom controls for VoiceOver coverage. SidebarView has a start (bell notification, command failed, pane count labels). Other custom views likely lack labels: tab bar, which-key overlay, copy mode overlay, session manager, window mode hints, auto-hide edge triggers.

- Complexity: 2
- Required for App Store submission
- Research: `/tmp/ai-research-macos-native-divergence-framework.md`

### 5d. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

- Complexity: 2
- `/spec` required: which Ghostty config keys to support, conflict resolution with Mistty config.
- Depends on: 4a

### 5e. Declarative Project Layouts
`.mistty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects. `start_suspended` option for panes that show the command but don't execute until Enter.

Includes Layout Manager UI: "Save current layout" command that generates `.mistty.toml` from the live workspace.

- Complexity: 2
- `/spec` required: file format, trust model, layout manager UI design.
- Depends on: 4a (config format), 2c (layout serialization format)

### 5f. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts. Lower priority because which-key (1a) covers discoverability.

- Complexity: 2
- `/spec` required: action registry, search ranking, visual design. Prior art: Raycast, Nova, Linear.

### 5g. Enhanced Session Manager
Enhance existing Cmd+J session manager: frecency-ranked directories (zoxide integration already exists), Nerd Font icons, preview pane showing recent output. Cmd+\` for instant last-workspace toggle.

- Complexity: 2
- `/spec` required: preview pane content, icon mapping, frecency algorithm tuning.

### 5h. System Notifications for Background Events
Optional macOS Notification Center integration (via UserNotifications) for events when Mistty is not the frontmost app. Bell and command-failure glow dots remain the primary in-app signal. System notifications supplement them for the "I'm in another app" case.

- Complexity: 2
- `/spec` required: which events trigger notifications, grouping, action buttons, user preference toggle.
- Depends on: 2b (notification infrastructure)

**Essential done when:** dropdown terminal works via global hotkey, hints mode selects visible targets, floating panes work.

**Polish done when:** Ghostty themes import, project layouts load from `.mistty.toml` with save-current-layout command, command palette searches all actions, session manager shows frecency-ranked results with icons, system notifications fire for background events when Mistty is not frontmost.

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
- Depends on: Phase 2a (shell integration / OSC 133)
- Extends Phase 2a/2b shell integration: upgrades line-level prompt navigation to visual block selection with metadata.
- Only Warp has this.

### 6c. Inline Preview Panes
Hover file paths in terminal output for Quick Look preview. Click to open in split pane.

- Complexity: 4
- `/spec` required: path detection, Quick Look integration, split-pane creation flow.
- No terminal does this. Novel.
- Pairs with 5b (hints mode provides keyboard-driven target selection).

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
  Phase 1b (daily driver polish) ✓
  Phase 1c (auto-hide panels) ✓
  Phase 2a (OSC foundation) ✓
  Phase 2b (contextual sidebar) ✓
  Phase 2c (basic session persistence) ✓
  Phase 3a (socket API + CLI) ✓
  Phase 3b (neovim navigation) ✓
  Phase 4a-1 (config parsing) ✓
  Phase 4a-2 (wire global keybindings) ✓
  Phase 4a-2b (native keybinding defaults) ✓
  Phase 4a-3 (wire modal keybindings) ✓
  Phase 4b (live config reload) ✓
  Phase 4d (sidebar config) ✓

Current:
  Phase 4e (auto-hide UX polish) — next

After Phase 4:
  ──> cleanup gate (integration tests, API stability) [non-blocking for Phase 5]
  ──> 4f-1 (key sequences) ──> 4f-3 (key tables)
  ──> Phase 5 Essential:
      5a (dropdown, hardcoded hotkey first) ──> 4f-2 adds configurable global hotkey
      5b (hints mode) pairs with 4f-3 for one-shot key table
      5c (floating panes) no keybinding dependency
    ──> VoiceOver audit gate
      ──> Phase 5 Polish (Ghostty compat, layouts, palette, session manager, notifications)
      ──> Phase 6 (moonshots)

Late dependencies:
  2a ──> 6b (block-based output)
  3a ──> 6d (automation API)
  4a ──> 5d (Ghostty compat), 5e (layouts)
  4f-3 ──> 5b (hints mode uses one-shot key table for label selection)
  4f-2 ──> 5a configurable global hotkey (5a can ship with hardcoded hotkey first)
  2c ──> 5e (layouts), 4c (advanced persistence)
  4a ──> 4b (live reload)
  5b (hints) ──> 6c (inline previews)
```

## What's NOT on this roadmap

- **Daemon architecture**: evaluated and deferred. A headless process owning sessions (like tmux's server) would give CLI/GUI parity and attach/detach, but the daemon-to-surface rendering bridge is unsolved for native GUI terminals. The IPC protocol boundary is the escape hatch if this becomes needed later.
- **Alternative terminal base**: evaluated WezTerm (stalled, last release 2024-02) and Kitty (strong IPC but no embeddable library). Neither is embeddable. libghostty is the only option for a native macOS app with custom UI chrome.
- **Explicit multi-window support**: multi-window works implicitly (SwiftUI WindowGroup, FocusedValue menu targeting). No plans for cross-window features (drag tabs between windows, window-specific config). If needed, it's a Phase 5 candidate.
- CI/CD (GitHub Actions): deferred until contributors exist
- IPC service refactoring as standalone effort: works, not broken. Phase 3 cleanup gate audits it as input to socket API design.
- C callback notification replacement: works, low priority
- Cursor trail: likely ships upstream in Ghostty. Track, don't build.
- Smooth/pixel scrolling: depends on libghostty upstream. Track, don't build.
- RTL/BiDi text: renderer-level, lives in libghostty. Track, don't build.
- AI-assisted command generation: premature. Phase 6d (terminal automation API) provides the infrastructure if revisited.
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
- OSC 133 C (command output start) as apprt action: would enable explicit running-state detection in sidebar (Phase 2b D1 revisit condition)
- Native git branch OSC sequence: would replace event-driven git rev-parse (Phase 2b D4 revisit condition)

## Findings (iteration 16)

- `readClipboardCallback` in `GhosttyApp.swift` is a stub that never completes the clipboard request. Cmd+V (paste) does not work. Cmd+C (copy) works because `writeClipboardCallback` is complete. Fix pattern exists in `vendor/ghostty/macos/Sources/Ghostty/Ghostty.App.swift`.
- `jump_to_prompt` exists as a Ghostty binding action (found in `vendor/ghostty/src/input/Binding.zig`). Takes signed integer: negative = previous, positive = next. Callable via `ghostty_surface_binding_action`. Confirmed for Phase 2b prompt navigation.
- libghostty parses all OSC sequences internally and delivers typed actions via the apprt callback. Mistty does not need its own OSC parser. Phase 2a was action callback handling, not parser construction.
- Ghostty uses 75ms title debounce and 15s progress auto-expiry. Mistty adopted both patterns.
- No terminal shows a persistent "running" indicator in sidebar/tab chrome. Process title (SET_TITLE) is the universal running-state signal. Phase 2b uses this pattern.

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
- /tmp/ai-research-nsevent-testing.md (NSEvent monitor testing strategies, 2026-04-14)
- /tmp/ai-research-terminal-tab-bar-config.md (tab bar visibility config comparison, 2026-04-14)
- /tmp/ai-research-ghostty-osc-handling.md (Ghostty OSC action handling patterns, 2026-04-14)
- /tmp/ai-design-phase2a-osc-foundation.md (Phase 2a spec, 2026-04-14)
- /tmp/ai-design-phase2c-session-persistence.md (Phase 2c spec, 2026-04-14)
- /tmp/ai-design-phase2b-contextual-sidebar.md (Phase 2b spec with decision log D1-D8, 2026-04-14)
- /tmp/ai-research-phase2b-inputs.md (consolidated Phase 2b prior research, 2026-04-14)
- /tmp/ai-research-phase2b-notification-patterns.md (notification patterns across terminals/IDEs, 2026-04-14)
- /tmp/ai-research-command-state-indicators.md (command running/idle/done state patterns, 2026-04-14)
- /tmp/ai-brainstorm-phase2b-sidebar.md (Phase 2b brainstorm, 2026-04-14)
- /tmp/ai-debate-phase2b-sidebar.md (Phase 2b debate transcript, 2026-04-14)
- /tmp/ai-research-macos-native-divergence-framework.md (native vs custom decision framework, 2026-04-15)
- /tmp/ai-research-macos-native-ui-tradeoffs.md (terminal UI native patterns analysis, 2026-04-15)
- /tmp/ai-research-macos-native-apis-terminals.md (macOS native APIs for terminals, 2026-04-15)