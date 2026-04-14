# Mistty Improvement Plan

Created: 2026-04-13
Updated: 2026-04-13 (iteration 5, post plan-review and cmux research)

## Context

Mistty is a macOS terminal emulator built on libghostty (SwiftUI + Zig). The build
works (262 tests pass), but the codebase has structural issues typical of AI-generated
code: a 1095-line god view, notification-based event routing instead of direct calls,
and a build system that needed macOS 26 fixes.

## Completed (Phase 1)

All Phase 1 items are done and committed on branch `chore/phase1-devshell-and-build`:

- 33ce169: Rewrote flake.nix with mkShellNoCC, added zls/swiftlint/xcodes/aria2,
  Xcode toolchain on PATH, alejandra formatter, .envrc watch_file, .kiro LSP config
- c245d86: Fixed build-libghostty with -Demit-xcframework=true and DEVELOPER_DIR
- 17d35a4: Updated README with macOS 26 build instructions, fixed project structure

Items from the original plan that turned out to be unnecessary:
- "Pin nixpkgs to a specific commit": flake.lock already pins. No action needed.
- "Add GitHub Actions CI": deferred to Phase 4 (future work).

## Phase 2: ContentView decomposition

ContentView.swift is 1095 lines. The decomposition uses @Observable state machine
classes with ViewModifier wrappers as the API surface.

### Architecture

Each mode (window mode, copy mode, pane nav) gets:
- An `@MainActor @Observable` class that owns the NSEvent monitor token and the
  mode's state machine. The class has explicit `activate()`/`deactivate()` methods
  (idempotent) and removes the monitor in `deinit` as a safety net.
- A `ViewModifier` that owns the @Observable via `@State` and manages its lifecycle.
  The modifier calls `deactivate()` in `onDisappear` as the primary deterministic
  cleanup path. `deinit` is the fallback only.

### Critical design constraints

1. **@MainActor on all @Observable classes.** NSEvent monitor callbacks run on the
   main thread, but making this compiler-enforced prevents future data races if
   async work is added.

2. **Deactivation guard flag.** Each @Observable must have an `isActive` flag that
   the monitor closure checks before acting. This prevents stale monitors from
   operating on a deactivated manager during the window between `onDisappear` and
   `deinit`.

3. **Tab identity via .id(tab.id).** When `.id()` changes, SwiftUI destroys the old
   view identity (triggering onDisappear, then eventually deinit) and creates a new
   one. @State is re-initialized. SwiftUI guarantees onDisappear fires before the
   new view's onAppear for same-position identity changes.

4. **C callback notifications above .id() boundary.** Notifications from ghostty C
   callbacks (ghosttyCloseSurface, ghosttySetTitle, ghosttyRingBell) must be handled
   on a parent view that is NOT affected by .id(tab.id). Otherwise, notifications
   could be missed during view recreation. These handlers should stay on the outer
   ContentView body, not on the inner modified view.

### Extractions

1. `WindowModeManager` (@Observable) + `WindowModeModifier` (ViewModifier)
   - Reads tab and session from the modifier's parameters
   - Owns: windowModeMonitor token, key handling, state transitions
   - ~120 lines

2. `CopyModeManager` (@Observable) + `CopyModeModifier` (ViewModifier)
   - Reads surface and scrollbar from tab.activePane?.surfaceView at each call site
     (not stored, since active pane can change within a tab)
   - Owns: copyModeMonitor token, search state, yank logic, terminal line reading
   - ~500-550 lines (includes all helper functions: performSearch, findMatchOnLine,
     countSearchMatches, readTerminalLine, readLineByScreenRow, readScreenLine,
     yankSelection, readGhosttyText, scrollViewport)

3. `PaneNavigationManager` (@Observable) + `PaneNavigationModifier` (ViewModifier)
   - Takes store: SessionStore (stable identity, no stale reference risk)
   - Always active (installed on appear, removed on disappear)
   - ~40 lines

4. Session manager overlay stays in ContentView (simple enough to not warrant extraction).

5. ContentView after Phase 2: ~500-550 lines (NOT ~250 as originally estimated).
   The ~15 .onReceive notification handlers and their associated helpers remain
   until Phase 3. The ~250 target is only reachable after both Phase 2 and Phase 3.

### Manual test checklist

- [ ] Open copy mode, search for text, yank selection
- [ ] Switch tabs while copy mode is active (monitor should deactivate)
- [ ] Open window mode, resize panes, swap panes, break pane to tab
- [ ] Switch tabs while window mode is active (monitor should deactivate)
- [ ] Ctrl-h/j/k/l navigation between panes
- [ ] Close last pane in a tab (tab should close, monitors should clean up)
- [ ] Cmd+N to open second window, verify all modes work independently
- [ ] Close a window, verify no leaked monitors (check Console.app for crashes)

Verification: All 262 tests pass + manual checklist above.

## Phase 3: Replace menu NotificationCenter with @FocusedValue

Mistty uses WindowGroup (supports Cmd+N), so @FocusedValue is correct.

### Critical fix from review

The original plan published `SessionStore` as the focused value. This is wrong:
MisttyApp creates one SessionStore with a single `activeSession` property, shared
across all WindowGroup windows. Publishing the store doesn't distinguish which
window's session is active.

**Fix:** Publish the specific `MisttySession` as the focused value, not SessionStore.
Each ContentView knows its own session (from the window's state). The focused value
tracks which window is key, so the correct session is always available to menu commands.

### Steps

1. Define `FocusedSessionKey` conforming to FocusedValueKey, type `MisttySession?`
2. ContentView publishes `.focusedValue(\.activeSession, session)` where `session`
   is the window's own session
3. MisttyApp `.commands {}` reads `@FocusedValue(\.activeSession)` and calls methods
   directly on the session/tab
4. Delete the ~16 Notification.Name extensions for menu commands
5. Keep notifications from non-SwiftUI contexts:
   - ghosttySetTitle, ghosttyCloseSurface, ghosttyRingBell (C callbacks)
   - IPCService-posted notifications
6. Document the boundary: SwiftUI menu commands use @FocusedValue, C callbacks and
   IPC use NotificationCenter.

### Edge cases

- Menu items that don't need a focused window (e.g., "New Window"): handled by
  WindowGroup itself, not custom commands. Future menu items that need to work
  without a focused window can't use @FocusedValue; note this boundary.
- Focus tracking lag: brief nil period during window transitions. Menu items may
  flicker to disabled. Cosmetic only.

Verification: All menu shortcuts work in multi-window. Cmd+N creates independent
window with working shortcuts. Menu items are disabled when no window is focused.

## Phase 4: Future work (not implemented)

1. Error handling: GhosttyAppManager.init silently fails
2. IPC service typed interface
3. C callback notification replacement (surface delegate protocol)
4. Test coverage for ViewModifier lifecycle
5. swiftlint config with `swift_version: 6.3` if rules depend on language version
6. GitHub Actions CI workflow for build + test

## Ideas from cmux research (2026-04-13)

Research file: /tmp/ai-research-cmux-patterns.md

Patterns worth considering for future phases:
- **Panel protocol**: typed variants (TerminalPanel, BrowserPanel) with focus intent
  enum. Good model if Mistty adds non-terminal pane types.
- **Unix socket API for CLI**: app as server, CLI as thin client. Better architecture
  than the current IPC approach for scriptability.
- **Notification rings**: OSC 9/99/777 escape sequences + CLI notify command for
  agent awareness. Per-pane visual ring, tab highlight, jump-to-unread.
- **Workspace-as-context**: sidebar entries that bundle terminal panes, git branch,
  PR status, listening ports. Richer than tmux's window concept.
- **Ghostty config compatibility**: reading ~/.config/ghostty/config for themes/fonts.

Antipatterns to avoid:
- **God object Workspace**: cmux's Workspace.swift contains panel lifecycle, focus
  reconciliation, session persistence, remote SSH, sidebar metadata, and more in one
  file. Decompose early.
- **Flat source directory**: no module boundaries means coupling accumulates silently.
- **Defensive pointer validation**: checking malloc_zone_from_ptr to detect freed
  surfaces. Design ownership so Swift wrappers can't outlive native surfaces.

## Risk assessment

- Phase 1: Done. Zero issues.
- Phase 2: Medium risk. NSEvent monitor lifecycle is the main concern. Mitigations:
  @MainActor, deactivation guard, .id(tab.id), onDisappear as primary cleanup.
- Phase 3: Low risk, but the SessionStore-as-FocusedValue bug would have caused
  wrong-window targeting in multi-window. Fixed in this iteration.

## Out of scope

- Feature work from PLAN.md (copy mode phase 1, save layouts, etc.)
- Refactoring models (SessionStore, MisttySession are reasonably clean)
- Changing the libghostty integration (GhosttyApp.swift callbacks)
- IPC service refactoring
- C callback notification replacement

## Sources

- ContentView.swift (1095 lines), MisttyApp.swift (189 lines), GhosttyApp.swift (205 lines)
- SessionStore.swift, MisttyTab.swift, MisttySession.swift
- PLAN.md, docs/plans/2026-03-06-mistty-design.md
- Ghostty CI (release-tip.yml), Ghostty nix/devShell.nix
- nixpkgs: zls 0.15.1, swiftlint 0.62.1, sourcekit-lsp 5.10.1 (incompatible)
- Xcode 26.4 bundled sourcekit-lsp (Swift 6.3 compatible)
- /tmp/ai-review-mistty-plan.md (plan review, 2026-04-13)
- /tmp/ai-research-cmux-patterns.md (cmux architecture research, 2026-04-13)
