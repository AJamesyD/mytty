# Mytty Roadmap

Created: 2026-04-14
Last updated: 2026-04-17
Iteration: 24

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

---

## Current

ADR-008 Phase 2 (modal key dispatch rework) is next. This moves CopyModeManager, WindowModeManager, WhichKeyManager, and session manager key handling from NSEvent monitors into the surface keyDown path, completing the key dispatch consolidation.

After that: Phase 4f-3 (key tables and modal bindings), which depends on the completed dispatch rework.

Other candidates: Phase 7a (Ghostty submodule upgrade), Phase 4f-2 (global hotkeys), Phase 5a-2 (dropdown polish).

## Phase 4f: Keybinding System Upgrade

Bring keybinding configurability to Ghostty parity, then exceed it.

### - [x] 4f-1: Key Sequences
Parses `ctrl+a>h` syntax. Sequence state machine with 1s configurable timeout. `SequenceIndicatorView` overlay shows pending leader keys with which-key integration after 500ms.

### - [ ] 4f-2: Global Hotkeys
System-wide hotkey registration via `CGEvent` tap or `NSEvent.addGlobalMonitorForEvents`. Requires accessibility permissions. Needed for dropdown terminal (5a) configurable hotkey, though 5a already ships with a hardcoded hotkey.
- Complexity: 2

### - [ ] 4f-3: Key Tables and Modal Bindings
Named binding sets activated/deactivated at runtime. Generalizes which-key into a single mechanism; copy mode adopts key tables for top-level dispatch but retains its internal state machine. Prefixes: `performable:` (only consume if action can execute), `all:` (broadcast to all surfaces). Chained actions.
- Complexity: 3
- Ghostty parity: `activate_key_table:<name>`, one-shot mode, `keybind=clear`

### - [ ] 4f-4: Beyond Ghostty (stretch, no timeline)
Ideas for future consideration, not planned work:
- Conditional bindings (bind differently based on running process, pane count, or mode)
- tmux-style `bind-key -r` (repeatable prefix within a timeout)
- Zellij-style named modes with visual indicators
- User-defined key tables loadable from separate files

## Phase 4c: Advanced Session Persistence

Extends 2c with scrollback persistence, running command restoration, and optional shpool/zmx integration for shell survival across app restarts.

- `/spec` required: scrollback serialization format, shpool/zmx integration decision, migration from basic persistence (2c).
- Complexity: 3 (built-in) or 2 (shpool/zmx integration)
- Depends on: 2c

## Phase 5: Differentiators

### Essential

### 5a. Dropdown / Quake / Float Mode
Global hotkey summons a dropdown terminal (NSPanel). Also support floating terminal windows that overlay other apps.

- Complexity: 3
- Spec: `docs/specs/phase5a-dropdown-terminal.md`
- Prior art: Guake, Yakuake, iTerm2 hotkey window, Ghostty QuickTerminal.
- Hardcoded hotkey works without config, like Phase 1a keybindings.

#### - [x] 5a-1: Core dropdown
NSPanel-based dropdown with Ctrl+` hotkey, slide animation, auto-hide on focus loss, persistent session.

#### - [ ] 5a-2: Dropdown polish
Configurable position (top/bottom/left/right), size (percentage of screen), per-monitor behavior. Not started.

### - [ ] 5b. Hints Mode
Press a trigger key, all visible URLs/paths/hashes get short letter labels. Type the label to act (open, copy, insert).

- Complexity: 2
- `/spec` required: label assignment algorithm, action menu, visual overlay design.
- Prior art: Kitty hints kitten. Ghostty has ~180 combined votes.
- Pairs with 6c (inline preview panes).

### - [ ] 5c. Floating Panes
Persistent overlay panes above the terminal grid. Cmd+F toggles floating layer. Panes keep running when hidden.

- Complexity: 3
- `/spec` required: z-ordering, resize behavior, keyboard navigation between floating and tiled panes.
- 201 votes on Ghostty. SwiftUI architecture makes this easier than renderer-level splits.

### Polish

### Cleanup gate (before Phase 5 Polish)

**VoiceOver Accessibility Audit**: audit all custom controls for VoiceOver coverage. SidebarView has a start; other custom views (tab bar, which-key, copy mode, session manager, auto-hide triggers) likely lack labels.

- Complexity: 2
- Required for App Store submission

### - [ ] 5d. Ghostty Config Compatibility
Read `~/.config/ghostty/config` for themes, fonts, colors. Zero-friction migration.

- Complexity: 2
- `/spec` required: which Ghostty config keys to support, conflict resolution with Mytty config.
- Depends on: 4a

### - [ ] 5e. Declarative Project Layouts
`.mytty.toml` in project root: pane arrangement, commands, working directories. Directory trust prompt for untrusted projects. `start_suspended` option. Includes Layout Manager UI: "Save current layout" generates `.mytty.toml` from the live workspace.

- Complexity: 2
- `/spec` required: file format, trust model, layout manager UI design.
- Depends on: 4a (config format), 2c (layout serialization format)

### - [ ] 5f. Command Palette (Cmd+K)
Fuzzy-searchable floating panel. All actions with shortcuts. Lower priority because which-key (1a) covers discoverability.

- Complexity: 2
- `/spec` required: action registry, search ranking, visual design. Prior art: Raycast, Nova, Linear.

### - [ ] 5g. Enhanced Session Manager
Enhance existing Cmd+J session manager: frecency-ranked directories (zoxide integration exists), Nerd Font icons, preview pane showing recent output. Cmd+\` for instant last-workspace toggle.

- Complexity: 2
- `/spec` required: preview pane content, icon mapping, frecency algorithm tuning.

### - [ ] 5h. System Notifications
Optional macOS Notification Center integration for events when Mytty is not frontmost. Glow dots remain the primary in-app signal; system notifications supplement for the background case.

- Complexity: 2
- `/spec` required: which events trigger notifications, grouping, action buttons, user preference toggle.
- Depends on: 2b (notification infrastructure)

**Essential done when:** dropdown terminal works via global hotkey, hints mode selects visible targets, floating panes work.
**Polish done when:** Ghostty themes import, project layouts load from `.mytty.toml`, command palette searches all actions, session manager shows frecency-ranked results, system notifications fire for background events.

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

### - [ ] 7a. Ghostty Submodule Upgrade
Pin to a commit after the `ghostty_surface_free_text` memory leak fix (or v1.3.2 when tagged). Zero API changes between v1.3.1 and current main.

- Complexity: 1
- Upgrade procedure: ADR-007
- Trigger: v1.3.2 tag, or proactively before next Mytty release

### - [x] 7b. `just ci` Target
Single justfile recipe that CI and local dev both call. Runs: swift-format check, SwiftLint (strict), swift build, swift test, typos. Prerequisite for CI parity.

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
Periphery dead code detection on weekly cron. Pre-commit hooks for swift-format and SwiftLint locally.

- Complexity: 1
- Depends on: 7c

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
  Phase 7b-7d (CI, releases) ✓
  ADR-008 Phase 1 (surface-level key dispatch) ✓

Current:
  ADR-008 Phase 2 (modal key dispatch rework)
  Then: 4f-3 (key tables)

Future:
  4f-3 (key tables) depends on ADR-008 Phase 2
  Phase 5 Essential:
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
  5b (hints) ──> 6c (inline previews)

Infrastructure:
  7a (Ghostty upgrade) ──> independent
  7b-7d (CI, releases) ✓
  7c ──> 7e (Periphery)
  7f trigger: launch decision
  7g trigger: established user base
```

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

## Upstream Tracking (free wins if Ghostty ships them)

- Cursor trail (347 votes), smooth pixel scrolling (112 votes, Kitty shipped in 0.46), RTL/BiDi text
- Ghostty scripting API (planned, no timeline; 109+ comments on Discussion #2353)
- Ghostty tmux control mode (in progress; DCS parser landed, Issue #1935)
- OSC 133 C as apprt action: would enable explicit running-state detection in sidebar
- Native git branch OSC sequence: would replace event-driven git rev-parse
- Ghostty v1.3.2: fixes `ghostty_surface_free_text` memory leak (5 Mytty call sites). ADR-007 tracks upgrade policy.

---

## Findings

### Key interception architecture (affects Phase 4f-3)

Mytty uses five independent NSEvent keyDown monitors between AppKit and the terminal surface. No other terminal emulator does this. Ghostty, Kitty, Alacritty, and WezTerm all check bindings at a single point after the key reaches the terminal layer. Ghostty lets every key reach the surface view and uses `ghostty_surface_key_is_binding()` in the Zig core.

The fix: stop intercepting keyDown events with NSEvent monitors. Let every key reach `TerminalSurfaceView.keyDown`, then use `ghostty_surface_key_is_binding()` (already available) to decide whether to execute a Mytty action. This eliminates the entire class of "monitor eats a key it shouldn't" bugs.

Options:
1. **Incremental**: consolidate five monitors into one with an explicit dispatch chain. Lower risk, partial fix.
2. **Full rework**: move binding dispatch into the surface keyDown path (Ghostty model). Eliminates the bug class entirely but touches every manager.

ADR-008 accepted (Option 2, full rework). Phase 1 complete: pane navigation and key sequence dispatch moved to surface keyDown. Phase 2 (modal dispatch) is next.

Rework in progress (ADR-008). Phase 1 complete, Phase 2 next.

### Testing gap: synthetic NSEvents

Tests using synthetic NSEvents mask real keyboard behavior. Shifted printable characters (`:`, `A`, `!`) are an untested category. The `characters(byApplyingModifiers:)` fix for Ctrl+hjkl documented this gap.
