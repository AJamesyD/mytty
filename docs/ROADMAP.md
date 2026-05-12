# Mytty Roadmap

Created: 2026-04-14
Last updated: 2026-04-22
Iteration: 26

## Working Agreements

Design tenets and architecture constraints: see [DESIGN.md](DESIGN.md).

These are process and scope rules that govern the roadmap:

0. **Apple-first**: macOS (Apple Silicon) is the primary platform. Linux is a distant stretch goal (see Phase 6f). No Windows, ever. Lean fully into SwiftUI and AppKit for now; use macOS system APIs directly (NSPanel, NSUserActivity, CGEvent taps).
1. **Time to daily driver**: optimize for the shortest path to replacing your current terminal setup.
2. **Personal-first, generalizable**: solve your own workflow pain, design interfaces that generalize.
3. **Infrastructure ships with features**: build plumbing when a feature needs it, not before.
4. **Dependency-ordered**: phases are sequenced by what unblocks what. No fake timelines.
5. **Opinionated defaults, constrained configuration**: ship one good design. When configuration is needed, prefer presets over arbitrary values. Don't push design decisions to the user. Code must be written with the assumption that hardcoded values will become configurable later: access through abstractions (e.g., `theme.surface` not `Color.white.opacity(0.03)`), even when the backing store is a static singleton.
6. **Principle of Least Astonishment**: follow macOS conventions wherever possible. Standard shortcuts (Cmd+S, Cmd+X, Cmd+C/V, Cmd+Q, Cmd+H, Cmd+Shift+]/[) must not be overridden for non-standard purposes. When Mytty needs a shortcut, pick one that doesn't conflict with universal macOS muscle memory. Custom behaviors (modes, which-key, split panes) are fine where macOS has no convention, but defaults should never surprise a user coming from another macOS app.

---

## Completed

### Phase 0: Quality Gate
All tests passing, zero compiler warnings, zero swiftlint violations.

### Phase 1: UI Foundation (1a, 1b, 1c)
Which-key overlay (Ctrl+Space) with categorized actions. Visual polish across all UI regions: theme system (`MyttyTheme.swift` with semantic tokens), sidebar rework (accent bars, badges, indicators), session/tab renaming, tab bar "if-multiple" visibility, tab drag-and-drop. Auto-hide panels (Pinned / Auto-hide / Hidden modes, overlay without reflow). Cleanup gates completed: @FocusedValue migration, ContentView extraction, sidebar accessibility audit.

### Phase 2: Terminal Intelligence (2a, 2b, 2c)
OSC action callback handling (PWD, titles, notifications, command finished, progress). Contextual sidebar: notification badges (glow dots for bell/failure, count pills), shell integration (OSC 133) with process title and command result in tab rows, prompt navigation (Cmd+Shift+Up/Down), clipboard paste fix. Rich sidebar metadata (git branch) was built and reverted: per-pane data doesn't belong at session level. Basic session persistence: tree saved to disk on quit, restored on launch. Cleanup gates completed: event handler extraction, IPC audit, OSC test coverage, IPC parity check.

### Phase 3: Platform (3a, 3b)
JSON-RPC 2.0 socket API with `noun.verb` naming, structured error codes, and event subscription. Neovim split navigation (bidirectional Ctrl+h/j/k/l via smart-splits.nvim). Cleanup gates completed: config audit, MyttyTheme review.

### Phase 4: Configuration (4a, 4b, 4d, 4e)
Config file (`~/.config/mytty/config.toml`) as single source of truth (see ADR-006). TriggerParser, KeybindingStore, per-mode keybinding sections with `unconsumed:` prefix. Default keybindings aligned with macOS conventions. Modal keybindings wired for WindowModeManager and WhichKeyManager. Live config reload via `DispatchSource` file watcher. Sidebar position/tree-depth configurable. Auto-hide UX polish: spring animations, Reduce Motion support, improved hint bar. Deferred auto-hide items tracked: dismiss-while-browsing, popup suppression, asymmetric animation, flash-on-background-event, escape-to-dismiss.

### Phase 5a-1: Core Dropdown Terminal
NSPanel-based dropdown terminal with Ctrl+` hotkey, slide animation, auto-hide on focus loss, persistent session.

Cleanup gate (partial): scene body perf fix and dead code sweep completed. Integration test coverage and API stability review still pending.

### Phase 4f-1: Key Sequences
Sequence parser (`ctrl+a>h` syntax), state machine with configurable timeout, `SequenceIndicatorView` overlay with which-key integration after 500ms.

### Phase 7b-7d: CI/CD Pipeline
`just ci` target (typos + strict lint + build + test). GitHub Actions workflow on macos-latest with Nix. Tag-based release workflow with changelog (git-cliff) and DMG.

### ADR-008 Phase 1: Surface-Level Key Dispatch
Moved pane navigation and key sequence dispatch from NSEvent monitor into `TerminalSurfaceView.keyDown`. See `docs/decisions/008-surface-level-key-dispatch.md`.

### Rename: Mistty to Mytty
Project renamed across all source, config, docs, and CI files. Bundle ID: `com.mytty.app`, config path: `~/.config/mytty/`, CLI: `mytty-cli`.

### Architecture Cleanup
- Back-references on model hierarchy: `weak var tab` on MyttyPane, `weak var session` on MyttyTab. Replaced stored identity properties with computed ones, deleted `propagateIdentity()` and manual wiring across several files (ca4a653).
- SessionSourceRunner simplification: replaced 4 concurrency mechanisms (OnceResume + terminationHandler + DispatchWorkItem + withTaskCancellationHandler) with a 2-task race (6aa9a24).

### Popup Windows
Named floating terminal windows controllable via CLI and IPC (`popup.open`, `popup.close`, `popup.toggle`, `popup.list`). Config-defined popups with `--name` for toggle semantics.

---

## Current

ADR-008 complete (two-layer key dispatch). Ghostty config hot-reload
shipped (`GhosttyConfigWatcher` + `ghostty_app_update_config`). Phase 7
bridge stubs wired (resize, equalize, move-tab). CI green.

Bridge audit complete: action parity (6 trivial actions), right/middle
mouse forwarding, window title tracking, TerminalSurfaceView reconciliation,
mouse callbacks (shape, visibility, hover URL), split direction, fullscreen
return value, and display ID tracking all shipped. Remaining deferred:
SECURE_INPUT, RESET_WINDOW_SIZE, NEW_WINDOW, CLOSE_ALL_WINDOWS, CONFIG_CHANGE.

Ambient identity (Layer 1) and session source protocol (Layer 2) shipped.
Env vars in every pane, `[[session-source]]` config, runner, picker
integration, `source.list` IPC, `mytty-cli source list`.

Architecture backlog complete: back-references refactor (ca4a653) and
SessionSourceRunner simplification (6aa9a24) both shipped.

Hints mode 5b-1 shipped: core types, label algorithm, terminal provider
(5 regex patterns), HintsModeManager state machine, HintsOverlayView,
config parsing, ContentView/PaneView wiring, keybinding defaults. Three
review rounds hardened: weak-capture lineReader, tab-switch deactivation,
incremental backspace, IME first-char extraction, scroll/resize
deactivation, file path open action. Hint bar shipped (persistent keybinding discovery bar, `show-hint-bar`
config toggle; PanelMode upgrade tracked as opportunistic item).

Hints mode 5b-2 shipped (c9bee44): chrome hints provider labels visible
sessions, tabs, and panes. ChromeFrameStore (@Observable + Environment)
for frame collection, ChromeHintTargetProvider for target generation.
Spatial ordering, skips focused/renaming elements, panes-only when sidebar
hidden. Shift+label closes element. Parameterized HintsOverlayView action
bar. Known limitation: same tab in sidebar and tab bar gets different labels
(TODO tracked in provider).

Ghostty submodule upgraded to 563b085a4 (0d43cc3): memory leak fix,
grapheme rendering fix, libc++ removal. Full clean rebuild verified.

Overlay unification shipped (0aaecf1): shared KeyBadge view, unified
transient modal styling (white labels, no border, standard badge opacity,
centered over terminal content). HintBarView dynamic font. 4 dead theme
tokens removed. Spec: `/tmp/ai-spec-overlay-visual-unification.md`.

Hints mode 5b-3 shipped (4cad3ae): IPC methods (`hints.activate`,
`hints.activate-chrome`) and CLI commands. Activation-only semantics for
cross-app trigger use case. `--label` and `--query` flags deferred to 5b-4.

Which-key discoverability shipped: ghost shortcuts (c1da6ea) show direct
keybinding next to entries; context filtering (e531dbf) hides actions that
can't execute. Command palette shipped (ded9823).

Opportunistic (no dependencies, land alongside any of the above):
- R14: dock badge (`NSApp.dockTile.badgeLabel` from aggregate notification count, ~15 LOC). Needs a spike to validate the `.onChange(of: computed-expression)` observation pattern with nested @Observable. The spike is a risk to investigate during implementation, not a blocker: if the pattern doesn't work, a manual `withObservationTracking` fallback exists.


### Bridge audit cleanup gate (before new features)

Mytty replaced Ghostty's window chrome but didn't rebuild all bridges between libghostty and the OS.

**Meta-problem:** When Mytty calls a libghostty API, it must pass the same information Ghostty does. When libghostty fires an action callback, Mytty must route it to the correct target (see Ghostty Concept Mapping in DESIGN.md). Several bugs trace to missing parameters, skipped callbacks, or no-op'd actions that have natural Mytty equivalents.

**Correctness (class a):**
- [x] `CELL_SIZE`: font zoom works (Cmd+/Cmd-/Cmd+0). On-demand read via `ghostty_surface_size()` is sufficient.
- [x] `COLOR_CHANGE`: handled (8acc25e), notification + handler + tests
- [ ] `CONFIG_CHANGE`: runtime config changes from escape sequences are dropped (acknowledged, deferred to Phase 6)
- [x] Scroll mods: precision + momentum flags now passed to libghostty (ec67fd3).

**OS integration:**
- [x] Window title: active tab's `displayTitle` pushed to NSWindow (1ddce86)
- [x] Display ID tracking: `ghostty_surface_set_display_id` called on screen change for multi-monitor vsync

**Mouse contract (tenet 1: mouse-unsurprising):**
- [x] `isMovableByWindowBackground`: removed (a2c6700). Was vestigial since 3956dfa1.
- [x] Right/middle mouse: forwarded to libghostty (6d35dea). Right-click fallthrough to system context menu working.
- [x] `MOUSE_OVER_LINK`: URL stored on pane model, cursor change on hover
- [x] `MOUSE_SHAPE`: cursor shape changes from terminal state
- [x] `MOUSE_VISIBILITY`: cursor hide-while-typing

Note: MOUSE_SHAPE, MOUSE_VISIBILITY, and MOUSE_OVER_LINK were implemented earlier but the roadmap incorrectly listed them as no-ops. The RFC (v6) classification was wrong; the implementations are functional.

Reference: `/tmp/ai-research-action-gap-audit.md` (full audit from 2026-04-18)
Handler nil-safety tests: completed for all 24 notification-driven handlers (74b7d4b).

**Action parity (Ghostty Concept Mapping in DESIGN.md):**

Trivial (one-liner handler, no design needed):
- [x] `CLOSE_WINDOW` -> close session containing the triggering pane (1ddce86)
- [x] `TOGGLE_FULLSCREEN` -> `window.toggleFullScreen(nil)` (1ddce86)
- [x] `QUIT` -> `NSApp.terminate(nil)` (1ddce86)
- [x] `TOGGLE_MAXIMIZE` -> `window.zoom(nil)` (1ddce86)
- [x] `OPEN_CONFIG` -> open `~/.config/mytty/config.toml` (1ddce86)
- [x] `COPY_TITLE_TO_CLIPBOARD` -> copy pane title to pasteboard (1ddce86)

Bridge divergence fixes:
- [x] `CLOSE_TAB` modes: dispatch by mode (this/other/right) instead of always closing current (5108270)
- [x] `OPEN_URL` kind handling: dispatch by kind (text/html/unknown), tilde expansion, Data+len parsing (57c6730)
- [x] `NEW_SPLIT` direction: preserve UP/DOWN/LEFT/RIGHT placement via `before` parameter
- [x] `TOGGLE_FULLSCREEN` non-native: returns false (unperformed) instead of true

Deferred (needs design or has side effects):
- [ ] `SECURE_INPUT` -> `EnableSecureEventInput()`/`DisableSecureEventInput()` (system-wide, needs toggle state)
- [ ] `RESET_WINDOW_SIZE` -> reset to initial size (no initial-size config value yet)
- [ ] `NEW_WINDOW` -> new session (semantic stretch in single-window model, revisit with multi-window)
- [ ] `CLOSE_ALL_WINDOWS` -> close all sessions (destructive, needs confirmation UX)

IPC parity: window mode operations now scriptable via CLI and socket API
(`pane.swap`, `pane.zoom`, `pane.break-tab`, `pane.join`, `tab.rotate`,
`tab.layout`). Shipped in 2e7240b.

Enforcement infrastructure (7i, 7k) shipped: SwiftLint custom rules for
layer isolation and theme tokens, plus a naming convention test that
validates all IPC methods at test time.

Key table tracking (4f-3a) shipped: Ghostty key tables pass through to
libghostty without Mytty intercepting navigation keys.

Other candidates: Phase 5d (inherit Ghostty theme colors into UI), Phase 7a (Ghostty submodule upgrade to v1.3.2), Phase 4f-2 (global hotkeys for configurable dropdown).

### Deferred from platform defaults (2026-04-17)

- **Terminal search (Cmd+F)**: copy mode has `/` search with full-scrollback, match count, and highlighting. Missing: a Cmd+F overlay accessible outside copy mode.
- ~~Config error UI~~ and ~~config key validation~~: moved to Backlog (UX polish and Config and CLI, respectively).
- **AppKit window migration (Track B)**: Track A (NSWindowDelegate enforcement) shipped in 7645cee/3956dfa1 and works. 4 known bugs have workarounds (menu shortcut interception, window registration timing, async first responder, chrome enforcement loop). Track B (~500 lines, NSWindowController + NSHostingView) carries disproportionate regression risk. Triggers for Track B: macOS 26 breaks enforcement loop, or a feature requires NSMenu beyond `CommandGroup`. Plan: `/tmp/ai-plan-appkit-window-migration.md`.
- **Sidebar active session indicator**: when sidebar is on the right, the accent bar is on the wrong side. Consider a background pill instead of a side-anchored bar so the indicator works regardless of sidebar position.

## Phase 4f: Keybinding System Upgrade

Bring keybinding configurability to Ghostty parity, then exceed it.

### - [x] 4f-1: Key Sequences
Parses `ctrl+a>h` syntax. Sequence state machine with 1s configurable timeout. `SequenceIndicatorView` overlay shows pending leader keys with which-key integration after 500ms.

### - [ ] 4f-2: Global Hotkeys
System-wide hotkey registration via `CGEvent` tap or `NSEvent.addGlobalMonitorForEvents`. Requires accessibility permissions. Needed for dropdown terminal (5a) configurable hotkey, though 5a already ships with a hardcoded hotkey.
- Complexity: 2

### - [ ] 4f-3: Key Tables and Modal Bindings (4f-3a shipped)
Named binding sets activated/deactivated at runtime. Generalizes which-key into a single mechanism; copy mode adopts key tables for top-level dispatch but retains its internal state machine. Prefixes: `performable:` (only consume if action can execute), `all:` (broadcast to all surfaces). Chained actions.
- Complexity: 3
- Ghostty parity: `activate_key_table:<name>`, one-shot mode, `keybind=clear`
- Phase A (key table tracking) shipped in 504816c. Phases B (copy mode remapping) and C (hints mode) remain.

### - [ ] 4f-4: Beyond Ghostty (stretch, no timeline)
Ideas for future consideration, not planned work:
- Conditional bindings (bind differently based on running process, pane count, or mode)
- tmux-style `bind-key -r` (repeatable prefix within a timeout)
- Zellij-style named modes with visual indicators
- User-defined key tables loadable from separate files

## Phase 4g: Font Configuration

Expand font config beyond `font_family` and `font_size` to support Ghostty's full font model: per-style families (`font-family-bold`, `font-family-italic`, `font-family-bold-italic`), font style overrides, `font-thicken` for non-Retina, and `font-codepoint-map` for symbol fallback. Goal: port a Ghostty font config to Mytty's `config.toml` with no loss.

- Complexity: 1
- Depends on: 4a (config format)

## Phase 4c: Advanced Session Persistence

Extends 2c with scrollback persistence, running command restoration, and optional shpool/zmx integration for shell survival across app restarts.

- `/spec` required: scrollback serialization format, shpool/zmx integration decision, migration from basic persistence (2c).
- Complexity: 3 (built-in) or 2 (shpool/zmx integration)
- Depends on: 2c

## Phase 5: Differentiators

### Essential

### 5a. Dropdown / Quake / Float Mode
Global hotkey summons a dropdown terminal (NSPanel).

- Complexity: 3
- Spec: `docs/specs/phase5a-dropdown-terminal.md`
- Prior art: Guake, Yakuake, iTerm2 hotkey window, Ghostty QuickTerminal.
- Hardcoded hotkey works without config, like Phase 1a keybindings.

#### - [x] 5a-1: Core dropdown
NSPanel-based dropdown with Ctrl+` hotkey, slide animation, auto-hide on focus loss, persistent session.

#### - [ ] 5a-2: Dropdown polish
Configurable position (top/bottom/left/right), size (percentage of screen). Per-monitor detection exists (follows mouse cursor). Position (top-only) and size (40% height, full width) are hardcoded.

### - [x] 5b. Hints Mode (5b-1, 5b-2, 5b-3 shipped; 5b-4 deferred)
A general "label things, type to jump" system with pluggable target providers. Press a trigger key, visible targets get short letter labels. Type the label to act (open, copy, insert).

Target providers:
- **Terminal provider**: scans visible text for URLs, paths, hashes. Prior art: Kitty hints kitten.
- **Chrome provider**: labels sidebar sessions, tabs, and panes for vimium-style keyboard navigation. Same label algorithm, same overlay, same key handling as the terminal provider.

The pluggable provider design should be decided during the spec phase (types-as-spec workflow), not retrofitted after the terminal provider ships.

- Complexity: 2
- `/spec` required: label assignment algorithm, action menu, visual overlay design, provider protocol, chrome target types.
- Prior art: Kitty hints kitten. Ghostty has ~180 combined votes (as of 2026-04-18).
- Pairs with 6c (inline preview panes).
- Soft dependency on 4f-3: key tables would be architecturally cleaner, but hints can use KeybindingStore like window mode and copy mode do today.

### - [ ] 5c. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden.

- Complexity: 3
- `/spec` required: z-ordering, resize behavior, keyboard navigation between floating and tiled panes.
- 201 votes on Ghostty (as of 2026-04-18). SwiftUI architecture makes this easier than renderer-level splits.

### Polish

### Cleanup gate (before Phase 5 Polish)

**VoiceOver Accessibility Audit**: audit all custom controls for VoiceOver coverage. SidebarView has a start; other custom views (tab bar, which-key, copy mode, session manager, auto-hide triggers) likely lack labels.

- Complexity: 2
- Required for App Store submission

### - [ ] 5d. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

Base config loading and override file (`ghostty.conf`) shipped in Phase 4. Remaining:

- [x] Inherit Mytty UI element colors (sidebar, tab bar, overlays) from the active Ghostty theme (2591335: 14 tokens derive from bg/fg; 21 accent tokens stay fixed; no hot-reload yet)
- [ ] Audit which of the 44 window/macos Ghostty keys Mytty should honor vs. ignore
- [ ] Handle `macos-window-shadow` from Ghostty config

- Complexity: 2
- `/spec` required: which Ghostty config keys to support, conflict resolution with Mytty config.
- Depends on: 4a

### - [ ] 5e. Declarative Project Layouts
`.mytty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects. `start_suspended` option. Includes Layout Manager UI: "Save current layout" generates `.mytty.toml` from the live workspace.

- Complexity: 2
- `/spec` required: file format, trust model, layout manager UI design.
- Depends on: 4a (config format), 2c (layout serialization format)

### - [x] 5f. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts displayed. Shipped in 583a80a.

Implementation: CommandPaletteView + CommandPaletteViewModel in Views/CommandPalette/. Reuses FocusableTextField (extracted to Views/Shared/), FuzzyMatcher for filtering, KeybindingStore for shortcut display. MenuSyncTests enforces menu item registration for all global-bound actions.

### - [x] 5g. Pluggable Session Sources

User-defined sources via `[[session-source]]` in config.toml. External commands produce session candidates for the picker. Sources run as child processes when the picker opens, output JSON or plain text, and merge into the existing picker with dedup and priority ordering.

Shipped in 543e924 (Layer 2 of ambient identity + session sources spec).

- Spec: `docs/specs/ambient-identity-and-session-sources.md`
- Config: `[[session-source]]` tables with name, command, action, priority, timeout-ms, max-items
- Runner: `/bin/sh -c`, timeout with SIGTERM/SIGKILL, 1MB stdout cap, JSON/text parsing
- Picker: `.sourceItem` case, concurrent loading via TaskGroup, dedup by dedupKey
- IPC: `source.list` returns configured sources with last status
- CLI: `mytty-cli source list` with `--json` flag

Known v1 limitations:
- `last_status` always returns "not-run" from IPC (needs SessionSourceRegistry, tracked in backlog)
- Await-all loading (progressive loading deferred)
- No on-query re-execution (MYTTY_QUERY is set but static per picker open)

Independent enhancements (can ship separately):
- Frecency tuning and scoring refinements
- Process icons in sidebar
- Preview pane showing recent output

### - [ ] 5h. System Notifications
Optional macOS Notification Center integration for events when Mytty is not frontmost. Glow dots remain the primary in-app signal; system notifications supplement for the background case.

- Complexity: 2
- `/spec` required: which events trigger notifications, grouping, action buttons, user preference toggle.
- Depends on: 2b (notification infrastructure)

**Essential done when:** ~~dropdown terminal works via global hotkey~~ ✓, ~~hints mode selects visible targets~~ ✓, floating panes work.
**Polish done when:** Ghostty themes import, project layouts load from `.mytty.toml`, system notifications fire for background events. Session sources: shipped. Command palette: shipped (583a80a).

---

## Phase 6: Moonshots

### - [ ] 6a. Native tmux Control Mode
Render tmux panes as native Mytty splits via `tmux -CC`. Only iTerm2 has this.

- Complexity: 5
- `/spec` required: protocol analysis, sync model, edge case catalog.
- Defensible moat: hard to copy.
- Ghostty's tmux control mode is in progress (DCS parser landed). If it ships, Mytty could use libghostty's tmux support, reducing the effort here.

### - [ ] 6b. Block-Based Output
Command+output as selectable blocks. Metadata: exit code, duration, cwd. Click to select entire block. Cmd+Up/Down to navigate. Only Warp has this.

- Complexity: 4
- `/spec` required: block detection from OSC 133, visual design, selection model, keyboard navigation.
- Depends on: Phase 2a (shell integration / OSC 133)

### - [ ] 6c. Inline Preview Panes
Hover file paths in terminal output for Quick Look preview. Click to open in split pane. No terminal does this.

- Complexity: 4
- `/spec` required: path detection, Quick Look integration, split-pane creation flow.
- Pairs with 5b (hints mode provides keyboard-driven target selection).

### - [ ] 6d. Terminal Automation API
Expose surface state (cells, colors, cursor position) via the socket API for scripting and testing. The "Playwright for terminals" gap.

- Complexity: 3
- `/spec` required: API surface, read vs write operations, security model.
- Depends on: 3a (socket API)

### - [ ] 6e. SSH Workspace Creation
`mytty ssh user@host` creates a dedicated workspace with port detection, sidebar metadata, and cleanup on disconnect. Optional Eternal Terminal (`et`) integration.

- Complexity: 4
- `/spec` required: workspace lifecycle, port detection, et integration model.

### - [ ] 6f. Cross-Platform (Apple Silicon + Linux)
Explore porting to Linux while keeping Apple Silicon macOS as the primary platform. Requires replacing SwiftUI/AppKit with a cross-platform UI layer. libghostty already supports Linux. No Windows support planned.

- Complexity: 5
- `/spec` required: UI framework evaluation (GTK4, platform-native split), build system, feature parity scope.
- Depends on: stable macOS feature set

---

## Phase 7: Infrastructure and Distribution

**Why here:** AI collapses implementation effort, so the ranking axis is maintenance burden and commitment timing, not hours. Low-maintenance two-way doors first, high-maintenance one-way doors deferred to launch triggers. Phase 7 is independent of Phases 5 and 6; items can be done in parallel or earlier.

ADR: `docs/decisions/007-ghostty-upgrade-policy.md`

### - [x] 7a. Ghostty Submodule Upgrade
Pinned to 563b085a4 (0d43cc3), which includes the `ghostty_surface_free_text` memory leak fix. Upgrade to v1.3.2 tag when available (no API changes expected).

- Complexity: 1
- Upgrade procedure: ADR-007

### - [x] 7b. `just ci` Target
Single justfile recipe that CI and local dev both call. Runs: swift format check, SwiftLint (strict), swift build, swift test, typos. Prerequisite for CI parity.

- Complexity: 1
- Depends on: nothing

### - [x] 7c. Nix CI Workflow
GitHub Actions workflow on `macos-15`. `DeterminateSystems/nix-installer-action` + `magic-nix-cache-action`. Runs `nix develop -c just ci`. Concurrency control (cancel stale PR runs). Path filtering (skip for docs-only changes).

- Complexity: 1
- Depends on: 7b
- Reference: Ghostty's CI pattern (DeterminateSystems on macOS due to NixOS/nix#13342)

### - [x] 7d. Tag-Based Releases + Changelog
`v*.*.*` tag triggers: build, bundle .app, create DMG (via `create-dmg`), generate changelog (via `git-cliff` from conventional commits), publish GitHub Release. Unsigned initially.

- Complexity: 2
- Depends on: 7c
- Conventional commits already in use (verified via git log)
- Produces a release from whatever is on main. No feature-phase dependency.

### - [ ] 7e. Periphery + Pre-Commit Hooks
Periphery dead code detection on weekly cron. Pre-commit hooks for swift format and SwiftLint locally.

- Complexity: 1
- Depends on: 7c

### - [x] 7i. Architecture Enforcement (SwiftLint Custom Rules)
Custom SwiftLint rules that mechanically enforce steering doc constraints:
- Ban `GHOSTTY_*` and `ghostty_*` symbols outside the 9 allowed bridge files
- Ban `.opacity()` on `MyttyTheme.*` expressions (create a token instead)

Without this: layer violations enter silently (5 found in one review session), C constants leak into UI handlers, theme system erodes. Each violation is cheap to fix individually but expensive to find. The review session that caught these took hours; the lint rule takes minutes to add and catches violations instantly in the editor.

- Complexity: 1
- Depends on: nothing
- Cost of not doing: ~5 layer violations per major feature addition, discovered only during manual review

### - [ ] 7j. CLI Golden File Tests
Run `mytty-cli <command> --help` for every subcommand, diff against committed golden files. Fails CI if help text changes without updating the reference. Optionally generate CLI.md from ArgumentParser's `--experimental-dump-help`.

Without this: documented CLI examples become phantom commands after renames or removals (7 found in one review session). Users following README/CONTRIBUTING hit immediate errors. The drift is invisible until someone manually tries every documented example.

- Complexity: 1
- Depends on: 7b
- Cost of not doing: ~3-7 phantom command references per CLI refactor, discovered only by users or manual audit

### - [x] 7k. IPC Naming Convention Test
Unit test that reads IPCListener's dispatch table and asserts every method name matches `^[a-z]+\.[a-z]+(-[a-z]+)?$`. Catches camelCase violations at test time.

Without this: new IPC methods default to Swift naming conventions (camelCase) instead of the wire protocol convention (noun.verb). 7 violations accumulated before this session's rename.

- Complexity: 1
- Depends on: nothing
- Cost of not doing: naming drift accumulates until a breaking rename is needed pre-1.0

### - [ ] 7h. App Icon
Design and add a custom app icon. Currently uses the default macOS app icon.

- Complexity: 1
- Depends on: nothing

### - [ ] 7f. Code Signing + Notarization
Developer ID certificate in GitHub secrets (keychain pattern from CodeEdit). Hardened runtime codesign. `notarytool submit` + `stapler staple`. Annual cert renewal.

- Complexity: 2
- Depends on: 7d
- **Trigger: launch decision.** One-way door ($99/year, cert rotation). Do not start until a public release date exists.

### - [ ] 7g. Sparkle Auto-Updates
Embed Sparkle framework, EdDSA signing, appcast generation in release workflow.

- Complexity: 2
- Depends on: 7f
- **Trigger: established user base.** Premature until there are users to update.

**Done when:** CI runs on every push, tag-based releases produce unsigned DMGs, changelog generates automatically. Signing and auto-updates activate when launch is decided.

---

## Dependency Graph

```
Completed:
  Phases 0-3 (quality gate, UI, OSC, sidebar, persistence, socket API, neovim nav) ✓
  Phase 4a-4e (config, live reload, sidebar config, auto-hide polish) ✓
  Phase 4f-1 (key sequences) ✓
  Phase 5a-1 (core dropdown) ✓
  Phase 5g (session sources) ✓
  Phase 7b-7d (CI, releases) ✓
  ADR-008 (surface-level key dispatch) ✓
  Bridge audit: action parity (6 trivial), mouse forwarding, window title ✓
  Ambient identity (Layer 1): env vars in every pane ✓
  Architecture cleanup: back-references (ca4a653), runner simplification (6aa9a24) ✓
  Phase 5b (hints mode): 5b-1 + 5b-2 + 5b-3 shipped ✓
  Phase 7a (Ghostty submodule upgrade to 563b085a4) ✓
  Which-key discoverability: ghost shortcuts (c1da6ea), context filtering (e531dbf) ✓
  Command palette (583a80a) ✓

Current (parallelizable):
  ┌─ 4f-3b (copy mode key remapping)      ← unblocked by 4f-3a ✓
  ├─ IPC gaps (session.focus, tab.focus)  ← trivial, completes CRUD
  └─ 5g known limitations                 ← SessionSourceRegistry for lastStatus

Opportunistic (no dependencies, land anytime):
  ├─ ~~R20 (window frame persistence)~~: shipped (17be2d9)
  ├─ R14 (dock badge)
  ├─ ~~Dynamic overlay font scaling~~: shipped (6a68326). `MyttyTheme.overlayFont`
     and `overlayFontSize` centralize the `max(cellHeight * 0.8, 12)` pattern.
     Fixed HintsOverlayView Canvas missing the min-size guard.
  └─ ~~Hint bar PanelMode~~: shipped. `hint-bar-mode` config with
     pinned/auto-hide/hidden tri-state.

Near-term (unblocked after current):
  ├─ 7e (Periphery + pre-commit)          ← depends on 7c ✓
  └─ 7h (app icon)                        ← independent

Feature phases (sequential gates):
  4f-3a ✓ ──> 4f-3b (copy mode remapping)
  IPC parity ✓ ──> 6d (automation API, future)

  Phase 5 Essential (parallelizable within):
    ├─ 5a (dropdown) ──> 4f-2 (configurable global hotkey)
    ├─ 5b (hints mode) ← 5b-1 + 5b-2 + 5b-3 shipped; 5b-4 deferred
    └─ 5c (floating panes) ← independent
  ──> VoiceOver audit gate
  ──> Phase 5 Polish:
    ├─ 5d (Ghostty compat) ← depends on 4a ✓
    ├─ 5e (layouts) ← depends on 4a ✓, 2c ✓
    ├─ 5f (command palette) ✓
    ├─ 5g ✓ (session sources)             ← shipped 543e924
    └─ 5h (notifications) ← independent
  ──> Phase 6 (moonshots)

Late dependencies:
  4f-3 ~~> 5b (soft: hints can use KeybindingStore, key tables are nicer)
  5b ──> 6c (inline previews)
  3a ──> 6d (automation API)
  2a ──> 6b (block-based output)

Infrastructure (trigger-gated, not dependency-gated):
  7f (code signing) ← trigger: launch decision
  7g (Sparkle) ← trigger: established user base, depends on 7f
```

### Parallelization opportunities (after bridge audit gate)

These items have zero dependencies on each other and can be done in any
order or simultaneously:

- 4f-3b (copy mode remapping): unblocked by 4f-3a
- 7e (Periphery + pre-commit): tooling, low effort

---

## What's NOT on this roadmap

- **Daemon architecture**: evaluated and deferred. The daemon-to-surface rendering bridge is unsolved for native GUI terminals. The IPC protocol boundary is the escape hatch if needed later.
- **Alternative terminal base**: WezTerm (stalled) and Kitty (no embeddable library) evaluated. libghostty is the only option for a native macOS app with custom UI chrome.
- **Explicit multi-window**: works implicitly (SwiftUI WindowGroup, FocusedValue). No cross-window features planned.
- Cursor trail, smooth scrolling, RTL/BiDi: renderer-level, track upstream Ghostty.
- AI command generation: premature. Phase 6d provides the infrastructure if revisited.
- Input broadcasting: scriptable via socket API (3a), doesn't need to be built-in.
- Multi-client shared sessions: niche for a personal-first terminal.

---

## Backlog (unsorted, unprioritized)

Items identified but not yet assigned to a phase. Promote to a phase when scoped.

**Discoverability:**
- Generate menu items from AppAction registry: replace hand-written menu Buttons in MyttyApp.swift with a loop over the registry, grouped by `category`. Eliminates the sync problem between registry and menu (currently enforced by `MenuSyncTests`). Trigger: when the menu system needs changes for another reason (hot-reload keybindings, dynamic "Recent Sessions" menu). Approach: add optional `menuGroup: MenuGroup?` enum to AppAction, filter per `CommandGroup` section. Prior art: VS Code's `menus` contribution point maps command IDs to menu locations declaratively. Constraint: SwiftUI `CommandGroup` requires static grouping; may need one `ForEach` per section, or drop to NSMenu (see AppKit window migration track).
- Post-action shortcut toast: after completing an action via which-key or palette, show "Tip: ⌘T" briefly. Self-limits to 3 appearances per action (persisted counter). Config: `show-shortcut-hints = true`. Prior art: JetBrains IDEs.
- Contextual mode hints (Zellij-style): when entering window/copy mode, replace the hint bar with mode-specific bindings. Prior art: Zellij status bar.
- `mytty show-keys` CLI: print all keybindings grouped by category, showing both direct shortcut and which-key path. Supports `--format json` and `--conflicts`.
- Cheat sheet overlay (hold Cmd): full-screen shortcut reference after holding Cmd for 1.5s. Prior art: macOS CheatSheet app, iPadOS keyboard overlay. Medium-high complexity.
- Modifier-hold shortcut reveal: hold Cmd to show ⌘1-9 on tabs, hold Ctrl to show pane nav hints. Needs NSEvent `flagsChanged` monitor.
- Richer hover tooltips: directory, shortcut key, running process (beyond current `.help()`)
- Tab bar scroll edge gradients (fade indicating overflow)

**Text display:**
- Middle truncation for path-like names in sidebar and tab bar

**Session manager** (independent of 5g source redesign):
- Scoring refinements: subtitle penalty, running-session boost, recency sort

**Config and CLI:**
- Config reference: `docs/config-example.toml` with all options and defaults
- Config CLI: `config show`, `config set`, `config path` subcommands
- Config key validation: warn on unrecognized keys (R32)

**IPC gaps:**
- `session.focus`: focus a session by ID. Completes the session CRUD set. Trivial: `store.activeSession = session`.
- `tab.focus`: focus a tab by ID. Completes the tab CRUD set. Trivial: `session.activeTab = tab`.

**Quick fixes** (do when convenient, no spec needed):
- Move `rename-tab` dispatch to `TerminalSurfaceView.keyDown`: Cmd+Shift+R is intercepted by libghostty before the menu system sees it. Handle it at the surface level like other shortcuts (Cmd+T, Cmd+W). Posts `.myttyRenameTab` notification.
- Worktree recipes in justfile (`setup-worktree`, dev-variant bundle name)

**Documentation:**
- ADR-009: AppKit migration decision (Track A sufficient, Track B triggers)

**Architecture improvements** (from 2026-04-21 debate, `/tmp/ai-debate-mytty-improvements.md`):
- Types-as-spec workflow: for future features, write Swift types/protocols first (compilable stubs), review the shape, then implement. Short prose section for non-obvious behavior only (error handling, security, edge cases). Skip the full spec format for features under ~500 lines. Zero tooling cost. Debate verdict: adopt for hints mode.
- SessionSourceRegistry: `source.list` IPC always returns `last_status: "not-run"` because status is tracked on a local copy during picker load. Add a `@MainActor` registry (dictionary or small class) that persists status across picker opens. `IPCService.listSources` reads from the registry instead of `MyttyConfig.load()`. Complexity: 1.
- Protocol-based picker items (deferred): SessionManagerItem enum has 5 cases with 8+ exhaustive switches (43 case-match lines). Adding `.sourceItem` required touching every switch. However, session sources are the extensibility mechanism for external item types, so the enum may not grow further. Revisit if a 6th built-in case is needed. Complexity: 2.

**Sidebar enrichment (from cmux RFC analysis, `/tmp/ai-rfc-mytty-cmux-lessons-v6.md`):**
- Tenet 2 revision: three-layer framework (signals / identity text / detail on demand). Update DESIGN.md. Unblocks git branch and working directory display.
- Git branch + dirty on tab rows: fresh GitDetectionService (subprocess, `git rev-parse`), display at tab level not session level. Config: `sidebar.show-branch`. Addresses D3 revert (ef9301c) at correct aggregation level.
- Notification read/unread lifecycle: `UnreadNotification` on MyttyTab, jump-to-unread shortcut. Dock badge upgrade to count unread notifications.
- Progress state display in sidebar tab rows (data already on MyttyPane.ProgressState, just needs rendering).
- Steering doc performance rules: no @Observable mutation from view body, no allocations on per-keystroke paths.

**UX polish (from cmux RFC analysis):**
- Config parse error dismissible banner (R70): MyttyConfig.parseError exists, needs UI.
- Empty state views for sidebar and session manager (R69).
- Sidebar toggle button (chevron at top of SidebarView).

---

## Deferred (with revisit triggers)

- **Config version field**: when first breaking config change ships.
- **Working directory display in sidebar**: after git branch ships.
- **Notification severity on UnreadNotification**: if/when hasBell/hasFailedCommand are removed.
- **Sidebar snapshot pattern refactor**: if Instruments shows >2ms/row after sidebar enrichment.

---

## Upstream Tracking (free wins if Ghostty ships them)

- Cursor trail (347 votes as of 2026-04-18), smooth pixel scrolling (112 votes, Kitty shipped in 0.46), RTL/BiDi text
- Ghostty scripting API (planned, no timeline; 109+ comments on Discussion #2353 as of 2026-04-18)
- Ghostty tmux control mode (in progress; DCS parser landed, Issue #1935)
- OSC 133 C as apprt action: would enable explicit running-state detection in sidebar
- Native git branch OSC sequence: would replace event-driven git rev-parse
- Ghostty v1.3.2: move from commit pin to tagged release (memory leak fix already included in current pin). ADR-007 tracks upgrade policy.

---

## Findings

### Key interception architecture (affects Phase 4f-3)

Mytty uses five independent NSEvent keyDown monitors between AppKit and the terminal surface. No other terminal emulator does this. Ghostty, Kitty, Alacritty, and WezTerm all check bindings at a single point after the key reaches the terminal layer. Ghostty lets every key reach the surface view and uses `ghostty_surface_key_is_binding()` in the Zig core.

The fix: stop intercepting keyDown events with NSEvent monitors. Let every key reach `TerminalSurfaceView.keyDown`, then use `ghostty_surface_key_is_binding()` (already available) to decide whether to execute a Mytty action. This eliminates the entire class of "monitor eats a key it shouldn't" bugs.

Options:
1. **Incremental**: consolidate five monitors into one with an explicit dispatch chain. Lower risk, partial fix.
2. **Full rework**: move binding dispatch into the surface keyDown path (Ghostty model). Eliminates the bug class entirely but touches every manager.

ADR-008 complete. Two-layer key dispatch in TerminalSurfaceView.keyDown; ModalKeyDispatcher deleted in Phase 2.

### Testing gap: synthetic NSEvents

Tests using synthetic NSEvents mask real keyboard behavior. Shifted printable characters (`:`, `A`, `!`) are an untested category. The `characters(byApplyingModifiers:)` fix for Ctrl+hjkl documented this gap.
