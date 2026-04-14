# Mistty Improvement Plan Review

Reviewed: 2026-04-13
Plan: /tmp/ai-plan-mistty-improvements.md (iteration 4)

## 1. Phase 1a accuracy

### 1.1 `-Demit-xcframework=true` flag: CORRECT

Verified in `vendor/ghostty/src/build/Config.zig` (line 400-402): the option is
declared as `"emit-xcframework"` with a bool type. The plan's flag is accurate.

Risk: the plan does not specify what `-Demit-xcframework=true` actually produces
or where the output lands. If the xcframework output path changed between Ghostty
versions, the `swift build` step that links against it would break silently. The
plan should specify the expected output path and add a post-build check
(e.g., `test -d vendor/ghostty/zig-out/lib/GhosttyKit.xcframework`).

### 1.2 `sudo xcode-select -s` in justfile: BAD IDEA

Requiring `sudo` in a build recipe is a footgun:
- It mutates global system state (affects all users and processes).
- If the recipe fails mid-way (after switching to 16.3, before switching back),
  the system is left pointing at the wrong Xcode.
- CI runners may not have sudo, or may have a different Xcode layout.

Alternatives:
1. **`DEVELOPER_DIR` env var**: set per-command, no sudo, no global mutation.
   `DEVELOPER_DIR=/Applications/Xcode-16.3.app/Contents/Developer zig build ...`
   This is the standard approach for per-invocation Xcode selection.
2. **`xcrun --toolchain`**: for selecting specific toolchains without switching.
3. **Document the requirement** instead of automating it. A recipe that silently
   runs sudo is worse than a recipe that fails with a clear error message.

Recommendation: use `DEVELOPER_DIR` for the zig build step. No sudo, no global
state mutation, no cleanup needed on failure.

### 1.3 Several Phase 1a/1b items are already done

The current `flake.nix` already has:
- `mkShellNoCC` (plan item 2)
- `flake-utils.follows` removed from zig input (plan item 3, only `nixpkgs.follows` remains)
- `alejandra` formatter output (plan item 5)
- `zls` and `swiftlint` in packages (plan items 9-10)
- Xcode toolchain PATH in shellHook (plan item 12)

The plan was written before these were done but not updated. This creates
confusion about what work remains. The plan should mark completed items or
remove them entirely.

### 1.4 Nixpkgs pin

The plan says to "pin nixpkgs to a specific commit" but `flake.lock` already pins
nixpkgs to commit `608d0cadfed...` via the lock file. Every flake with a lock file
has pinned inputs. The plan likely means pinning in `flake.nix` itself (e.g.,
`github:NixOS/nixpkgs/608d0cad...` instead of `nixpkgs-unstable`), but this is
unusual and counterproductive: it prevents `nix flake update` from working
normally. The lock file is the correct pinning mechanism.

Verdict: this is noise. The project context rule says "pin nixpkgs to a specific
commit," but the lock file already does this. No action needed unless there's a
specific reproducibility problem.

## 2. Phase 2 architecture

### 2.1 `.id(tab.id)` and @State re-initialization: CORRECT but with caveats

When `.id()` changes, SwiftUI treats the view as a new identity. This means:
- `@State` properties ARE re-initialized (new view identity = new state).
- The old view's `onDisappear` fires, then the new view's `onAppear` fires.
- `deinit` on the old @Observable will fire, but timing is not guaranteed by
  SwiftUI. It depends on ARC, which may defer if there are retain cycles or
  captures in closures.

Risks:
- **In-flight async work**: if the @Observable has any `Task` instances or
  completion handlers that capture `self`, `deinit` may be delayed. The
  NSEvent monitor removal in `deinit` would also be delayed, creating a window
  where two monitors coexist. The plan's mitigation (deactivate in
  `onDisappear`) is correct, but only if `onDisappear` reliably fires before
  the new view's `onAppear`. SwiftUI does guarantee this ordering for `.id()`
  transitions on the same view hierarchy position.
- **Closure captures in NSEvent monitors**: the current copy mode monitor
  captures `self` (the ContentView struct) and reads `store.activeSession`
  at event time. After extraction, the @Observable's monitor closure would
  capture the @Observable instance. If the old monitor fires between
  `onDisappear` and `deinit`, it would operate on a deactivated manager.
  The plan should specify that `deactivate()` sets a flag that the monitor
  closure checks before acting.
- **NotificationCenter observers**: `.onReceive` modifiers on the old view
  identity will stop receiving after the view is removed. But if the
  @Observable registers its own NotificationCenter observers (not via
  `.onReceive`), those must be explicitly removed in `deactivate()`.

### 2.2 ~250 line target for ContentView: OPTIMISTIC

Current ContentView is 1095 lines. The plan extracts:
- WindowModeManager: ~120 lines
- CopyModeManager: ~400 lines
- PaneNavigationManager: ~40 lines

That's ~560 lines extracted, leaving ~535 lines. The plan claims ~250 lines
remain. The gap (~285 lines) would need to come from:
- Removing the notification handler boilerplate (replaced by direct calls in
  Phase 3, not Phase 2)
- Removing monitor install/remove methods (moved to managers)
- Removing helper functions like `yankSelection`, `performSearch`, etc.

But Phase 2 does NOT replace the notification handlers. Those stay until Phase 3.
So after Phase 2, ContentView would still have all the `.onReceive` handlers
(~15 of them), the `handleSetTitle`, `handleRingBell`, `handleCloseSurface`
handlers, the `splitPane`, `closePane`, `closePaneInTab` helpers, and the full
layout code.

Realistic estimate after Phase 2: ~500-550 lines, not ~250. The ~250 target
is only achievable after both Phase 2 AND Phase 3.

### 2.3 CopyModeManager at ~400 lines

The copy mode code in ContentView includes `enterCopyMode`, `exitCopyMode`,
`installCopyModeMonitor` (with the large key handler), `performSearch`,
`findMatchOnLine`, `countSearchMatches`, `readTerminalLine`,
`readLineByScreenRow`, `readScreenLine`, `yankSelection`, `readGhosttyText`,
and `scrollViewport`. This is closer to 500-550 lines. The ~400 estimate is
low, which means either some helpers stay in ContentView (creating unclear
ownership) or the manager is larger than planned.

## 3. Phase 3: @FocusedValue

### 3.1 @FocusedValue reliability in WindowGroup: GENERALLY RELIABLE

@FocusedValue works with WindowGroup. SwiftUI tracks which window is key and
propagates focused values from the key window's view hierarchy to the menu
commands. When no window is focused (app is in background, or all windows
closed), focused values become nil, and menu items using them are automatically
disabled.

Known issues:
- **Focus tracking lag**: there can be a brief period during window transitions
  where the focused value is nil (between one window resigning key and another
  becoming key). Menu items may flicker to disabled state. This is cosmetic
  and brief.
- **Sheet/popover focus**: when a sheet or popover is presented, the focused
  value may not propagate correctly if the sheet's view hierarchy doesn't
  publish it. The session manager overlay in ContentView is not a sheet (it's
  a ZStack overlay), so this should not be an issue.
- **Multiple focused values**: if you need different focused values for
  different menu items, each needs its own FocusedValueKey. The plan only
  exposes SessionStore, which is sufficient since all menu commands operate
  on the store or its active session/tab.

### 3.2 Menu items that don't need a focused window

The plan doesn't address this. "New Window" (Cmd+N) is handled by WindowGroup
itself, not by custom commands, so it's fine. But if any future menu items
need to work without a focused window (e.g., "Open Session from File"), they
can't use @FocusedValue. The plan should note this boundary.

### 3.3 Notification removal scope

The plan says to delete ~16 Notification.Name extensions. The actual count in
MisttyApp.swift is 16 notification names (misttyNewTab through
misttyPrevSession). But the plan also says to keep ghosttySetTitle,
ghosttyCloseSurface, ghosttyRingBell (C callbacks) and IPC notifications.
These are defined elsewhere (likely in a GhosttyKit bridging file or another
extension). The plan should verify where ALL notification names are defined
to avoid accidentally deleting ones that are still needed.

## 4. Missing risks

### 4.1 NSEvent monitor cleanup timing

The plan acknowledges deinit as a "safety net" but doesn't address a specific
scenario: if the @Observable is captured in the NSEvent monitor closure (which
it will be, since the monitor reads the manager's state), ARC cannot deallocate
the @Observable until the monitor is removed. This creates a circular dependency:
deinit removes the monitor, but deinit can't fire until the monitor is removed.

The `onDisappear` -> `deactivate()` path breaks this cycle. But if `onDisappear`
doesn't fire (e.g., app termination, force quit), the monitor leaks. This is
acceptable for app termination but should be documented.

### 4.2 Thread safety of @Observable

@Observable is not thread-safe. All property mutations must happen on the main
actor. The NSEvent monitor callback runs on the main thread (local monitors
always do), so this is fine for the current design. But if any future code
mutates the @Observable from a background thread (e.g., an async search
operation), it would cause data races. The plan should specify `@MainActor`
on the @Observable classes to make this constraint explicit and compiler-enforced.

### 4.3 Interaction between .id() recreation and NotificationCenter observers

After Phase 2 but before Phase 3, ContentView still uses `.onReceive` for
notification handlers. When `.id(tab.id)` causes view recreation, the old
view's `.onReceive` subscriptions are torn down and new ones are created.
During the brief gap, a notification could be missed. For menu commands this
is harmless (user can press the shortcut again). For C callback notifications
(ghosttyCloseSurface, ghosttySetTitle), a missed notification could leave
stale state. The plan should note that C callback notifications should NOT
be on views affected by `.id(tab.id)`, or should be handled at a higher
level (e.g., on the WindowGroup or on a parent view without .id()).

### 4.4 SessionStore reference in @FocusedValue

The plan publishes `SessionStore` as the focused value. SessionStore is a
reference type (@Observable). If two windows share the same SessionStore
instance (which they do, since MisttyApp passes the same `store` to all
ContentView instances via WindowGroup), then @FocusedValue doesn't actually
distinguish which window's session is active. The menu command would call
`store.activeSession`, which is a single property on the shared store.

This means the architecture assumes `store.activeSession` is always the
session for the key window. If window focus changes but `store.activeSession`
isn't updated synchronously, menu commands could target the wrong session.
The plan should verify that `store.activeSession` is updated on window focus
change, or publish the specific `MisttySession` as the focused value instead.

## 5. Phase ordering

### Should Phase 3 come before Phase 2?

Arguments for Phase 3 first:
- Replacing notifications with @FocusedValue simplifies ContentView before
  decomposition. Fewer `.onReceive` modifiers means less code to move around.
- The notification handlers in ContentView are mostly one-liners that call
  store/session/tab methods. Converting them to direct calls in menu commands
  is straightforward and low-risk.
- Phase 2's ViewModifier extraction is easier when the view is smaller.

Arguments for Phase 2 first (current order):
- Phase 2 is the higher-risk change. Doing it on the current (known-working)
  architecture means fewer variables.
- If Phase 3 changes how state flows, Phase 2's design assumptions might need
  revision.
- The notification handlers are orthogonal to the monitor extraction. They
  don't interact with the code being moved in Phase 2.

Recommendation: the current order (Phase 2 then Phase 3) is fine. The
notification handlers are genuinely orthogonal to the monitor/mode extraction.
Doing Phase 3 first would save maybe 50 lines of `.onReceive` boilerplate
during Phase 2, but wouldn't change the decomposition design. The risk
reduction of doing the harder change first on stable code outweighs the
convenience of a slightly smaller file.

## 6. Summary of verdicts

| Item | Verdict |
|---|---|
| `-Demit-xcframework=true` flag | Correct, needs output path verification |
| `sudo xcode-select` in justfile | Bad idea, use DEVELOPER_DIR instead |
| Phase 1a/1b completion status | Plan is stale, many items already done |
| Nixpkgs pin | Noise, flake.lock already pins |
| .id(tab.id) recreation | Correct SwiftUI behavior, needs deactivation guard |
| ~250 line ContentView target | Unrealistic after Phase 2 alone (~500-550) |
| CopyModeManager ~400 lines | Underestimate (~500-550) |
| @FocusedValue reliability | Generally reliable, minor focus lag risk |
| NSEvent monitor circular ref | Real risk, onDisappear breaks cycle |
| @Observable thread safety | Needs @MainActor annotation |
| .id() + NotificationCenter gap | C callback notifications could be missed |
| SessionStore as focused value | May target wrong session in multi-window |
| Phase ordering | Current order is fine |

## Sources

- vendor/ghostty/src/build/Config.zig: `emit-xcframework` option declaration (2026-04-13)
- vendor/ghostty/build.zig: xcframework build logic (2026-04-13)
- flake.nix: current devShell configuration (2026-04-13)
- flake.lock: nixpkgs pinned to 608d0cad... (2026-04-13)
- justfile: current build-libghostty recipe (2026-04-13)
- Mistty/App/ContentView.swift: 1095 lines, god view (2026-04-13)
- Mistty/App/MisttyApp.swift: 189 lines, menu commands (2026-04-13)
