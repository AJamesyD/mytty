# RFC: Lessons from Mistty for Mytty

Date: 2026-04-18
Status: Draft (iteration 4)
Author: Cross-project review
Audience: Mytty AI agents and maintainer

## Context

Mistty (github.com/milch/mistty) is a sibling project built on the same
libghostty foundation. Both projects forked from a common ancestor. This RFC
documents what Mistty does differently, what Mytty should adopt, what Mytty
should explicitly reject, and why.

More importantly, this RFC articulates a delegation philosophy: Mytty should
be the thinnest possible layer between the user and libghostty, adding value
only where Ghostty has no opinion (multiplexing, session management, modal
interaction, scriptability). Everywhere else, delegate.

This RFC does NOT propose changes to Mytty's architecture (the ideal-state
spec v3 covers that). It proposes feature-level adoptions and a sharpened
delegation stance.

### The delegation hierarchy

When adding a feature, check these sources in order:

1. **libghostty C API** - if the API exists, call it. Don't reimplement.
   (Example: color scheme sync is one `ghostty_surface_set_color_scheme` call.)
2. **Ghostty macOS app Swift code** (vendor/ghostty/macos/Sources/) - if
   Ghostty's macOS app solves the same problem, study the pattern and adapt.
   The Swift files aren't linkable (they're part of Ghostty's own module, not
   GhosttyKit), but the patterns are directly applicable.
   (Example: NSEvent+Extension.swift for key translation, AppDelegate for
   window chrome, Ghostty.Config for config key reading.)
3. **Mistty's implementation** - if Mistty solved a problem Mytty hasn't,
   evaluate the code for portability.
   (Example: HintDetector for copy-mode hints.)
4. **Build from scratch** - only when 1-3 don't apply. This is where Mytty's
   original value lives: copy-mode, IPC, session manager, keybinding system.

The audit (/tmp/ai-audit-mytty-delegation.md) found that Mytty's bridge code
is ~830 LOC (7% of app). The target is ~750 LOC. Every new feature should
check whether it can be a bridge call before becoming new code.

### Prior art reviewed

- /tmp/ai-spec-mytty-ideal-state-v3.md (architecture spec)
- /tmp/ai-impl-plan-mytty-ideal-state-v3.md (implementation plan)
- /tmp/ai-audit-mytty-delegation.md (delegation audit)
- /tmp/ai-audit-mytty-architecture.md (architecture audit)
- /tmp/ai-research-mytty-vs-mistty-comparison.md (cross-project comparison)
- ~/Code/mistty/docs/DESIGN.md (design tenets)
- ~/Code/mistty/docs/ROADMAP.md (roadmap, iteration 24)

### Guiding principle

From DESIGN.md: "libghostty parses all escape sequences internally. Mytty
handles typed action callbacks. Do not parse raw escape sequences. Do not
duplicate Ghostty's terminal logic."

The generalization: **delegate everything that isn't Mytty-original to
something else.** libghostty for terminal logic. Ghostty's config for terminal
settings. Mistty's proven patterns for features Mytty hasn't built yet.

---

## Part 1: What to adopt from Mistty

### 1A. Hint-based navigation (maps to Roadmap Phase 5b)

**What Mistty has:** HintDetector (regex pipeline detecting URLs, emails,
UUIDs, paths, IPs, env vars, numbers, quoted strings, code spans) +
HintLabels (single/double-char label generator) + CopyModeHintOverlay
(positioned badge rendering with filter-by-kind cycling).

**Why adopt:** Phase 5b ("Hints Mode") is already on the roadmap with
complexity 2 and a `/spec` required tag. Mistty has a working, tested
implementation. The detection pipeline is ~300 LOC of pure functions (text
in, hints out) with no libghostty dependency. The label generator is ~100
LOC. Both are independently testable.

**Why not reimplement:** Mytty's design tenets say "infrastructure ships
with features, not before." Mistty's hint code IS the infrastructure. The
detection regexes cover edge cases (trailing punctuation stripping,
overlapping match resolution, bottom-to-top ordering) that would take
multiple iterations to rediscover.

**How it fits:** The roadmap says 5b "pairs with 4f-3 for one-shot key
table." Mistty's hint mode enters via a copy-mode sub-state. Mytty's
approach (key tables) is architecturally better because it generalizes, but
the detection and labeling layers are orthogonal to the activation mechanism.
Port HintDetector and HintLabels as-is. Wire activation through Mytty's key
table system instead of Mistty's copy-mode sub-state.

**Adaptation needed:**
- HintDetector and HintLabels: port directly, rename to match Mytty
  conventions
- CopyModeHintOverlay: rewrite to use MyttyTheme tokens instead of
  hardcoded colors
- Activation: wire through key tables (4f-3), not copy-mode sub-state
- Action dispatch: use Mytty's action system, not Mistty's inline handlers

**Estimated LOC:** ~450 (detection + labels + overlay + tests). Net new,
not replacing anything.

**Decision: ADOPT.** The detection pipeline is the hard part. The wiring is
Mytty-specific and should be Mytty-specific.

---

### 1B. Process icons in sidebar

**What Mistty has:** ProcessIcon.swift, a lookup table mapping process names
to Nerd Font glyphs (~50 LOC). Used in sidebar rows to show what's running
in each pane.

**Why adopt:** DESIGN.md tenet 3 says "pre-attentive signals over cognitive
ones." A glyph for `nvim` vs `python` vs `node` registers faster than
reading the process name text. The sidebar already shows process names; icons
add a pre-attentive channel.

**Why not adopt:** Tenet 2 says "show signals, not data." Process icons are
data (what's running), not signals (what needs attention). The sidebar's
glow dots and count pills are signals. Icons could add visual noise.

**Counterargument:** Icons don't compete with glow dots. They occupy
different visual channels (shape vs. color). A glow dot on a `node` icon
tells you "your Node server needs attention" faster than a glow dot on a
text label.

**How it fits:** Roadmap Phase 5g ("Enhanced Session Manager") mentions
"Nerd Font icons" as a planned feature. This is a subset that can ship
independently.

**Adaptation needed:**
- Port ProcessIcon.swift, rename to match conventions
- Requires a Nerd Font bundled or assumed installed
- Add to sidebar row views

**Estimated LOC:** ~60 (lookup table + view integration).

**Decision: ADOPT, but gate on font availability.** If the user's terminal
font doesn't include Nerd Font glyphs, the icons render as tofu. Either
bundle a Nerd Font fallback or detect availability and hide icons when
missing. Mistty doesn't handle this; Mytty should.

---

### 1C. Snapshot testing for visual regression

**What Mistty has:** ChromePolishSnapshotTests.swift using
swift-snapshot-testing to render sidebar, tab bar, and settings views at
fixed sizes, comparing pixel output against reference images.

**Why adopt:** Mytty's design tenets emphasize "visual quality ships with
features." Snapshot tests catch visual regressions (padding, alignment,
color drift) that unit tests structurally cannot. The MyttyTheme system
(semantic color tokens) is a good foundation, but nothing verifies that
views using those tokens look correct.

**Why not adopt:** Snapshot tests are brittle across OS versions (font
rendering changes, system appearance tweaks). They require manual baseline
updates on every intentional visual change. They add swift-snapshot-testing
as a dependency.

**Counterargument:** The brittleness is manageable. Pin snapshots to a
specific macOS version in CI. Run snapshot tests only on release branches,
not every PR. The dependency is test-only and well-maintained.

**How it fits:** Not on the roadmap. This is infrastructure, and tenet 3
says "infrastructure ships with features." Add snapshot tests when the next
visual feature ships (e.g., 5b hint overlay, 5g session manager polish).

**Estimated LOC:** ~200 per test file (boilerplate + assertions).

**Decision: ADOPT INCREMENTALLY.** Don't add a snapshot test suite
retroactively. Add snapshot tests alongside new visual features. Start with
the hint overlay (1A above) as the first snapshot-tested view.

---

### 1D. SSH host display name extraction

**What Mistty has:** SSHHostParser.swift (~60 LOC) that extracts the
hostname from SSH command strings, skipping flags that take values. Handles
`user@host` format.

**Why adopt:** Mytty already has SSHConfigService (reads ~/.ssh/config for
host aliases). SSHHostParser complements it by extracting the display name
from the running SSH command when the host isn't in ssh_config.

**How it fits:** Roadmap Phase 5g mentions SSH in the session manager
context. Small, self-contained.

**Decision: ADOPT.** Tiny, useful, no architectural impact.

---

## Part 2: What to explicitly NOT adopt from Mistty

### 2A. GUI settings panel

**What Mistty has:** SettingsView.swift, a full SwiftUI form for all config
options.

**Why reject:** ADR-006 ("Config file only") is an explicit architectural
decision. From DESIGN.md: Mytty is "config-file-only by design." The
rationale: a GUI settings panel creates a second source of truth. Either it
writes to the TOML file (round-trip fidelity issues, comment stripping) or
it maintains separate state (drift). The config watcher + which-key popup
provide discoverability without a GUI.

**What Mistty does better here:** Mistty's config has a `save()` method
that writes back to TOML. This is the seed of a round-trip-safe GUI. If
Mytty ever revisits ADR-006, the approach would be: parse TOML preserving
comments (TOMLKit supports this), GUI writes back through the same parser.
But this is not planned.

**Decision: REJECT.** ADR-006 stands. The config watcher + which-key +
config error UI (deferred item in roadmap) cover the discoverability gap.

---

### 2B. Mistty's IPC protocol (ad-hoc binary framing)

**What Mistty has:** 4-byte big-endian length prefix + status byte + JSON
payload. No request IDs, no version negotiation.

**Why reject:** Mytty already has JSON-RPC 2.0 with Content-Length framing,
request IDs for multiplexing, and typed error codes. This is strictly
better. JSON-RPC is a standard protocol; Mistty's is ad-hoc.

**Decision: REJECT.** Mytty's IPC is already ahead.

---

### 2C. Mistty's ContentView monolith pattern

**What Mistty has:** A single 41KB ContentView.swift containing layout,
event handlers, copy mode logic, search, hint scanning, yank, and terminal
line reading.

**Why reject:** Mytty already split this into ContentView.swift (layout) +
ContentView+Handlers.swift (event handling) + extracted @Observable managers.
The ideal-state spec (v3, Section 3) further consolidates key dispatch into
TerminalSurfaceView.keyDown. Going backward to a monolith would undo
completed work.

**Decision: REJECT.** The split is a completed architectural improvement.

---

### 2D. Mistty's HexColor parser

**What Mistty has:** HexColor.swift (~50 LOC) parsing #rrggbb/#rrggbbaa
strings to SwiftUI Color.

**Why not adopt:** Mytty uses MyttyTheme for all color tokens. User-facing
color config goes through Ghostty's config system (which has its own color
parsing). Adding a second color parser creates two paths for the same
concept.

**Decision: REJECT.** Ghostty's color parsing handles this. If Mytty needs
hex color parsing for config.toml values, use Ghostty's parser via the C
API or add a minimal parser at that time.

---

## Part 3: What Mistty validates about Mytty's direction

These are areas where Mistty's experience confirms Mytty is on the right
track.

### 3A. Extracted state managers

Mistty's ContentView stores NSEvent monitors as @State properties. This
makes the event handling untestable and the file unnavigable. Mytty's
extracted managers (PanelState, WindowModeManager, PaneNavigationManager,
CopyModeManager, WhichKeyManager, KeySequenceManager) are independently
testable and the test suite proves it. The ideal-state spec goes further
by eliminating NSEvent monitors entirely (ADR-008). Mistty's codebase is
evidence that the monolith approach doesn't scale.

### 3B. JSON-RPC IPC

Mistty's ad-hoc binary protocol has no request correlation. If two CLI
commands fire simultaneously, responses can't be matched to requests.
Mytty's JSON-RPC with request IDs handles this correctly. Mistty's
approach would need to be replaced if the CLI gains concurrent commands.

### 3C. Full Ghostty action coverage

Mistty implements 4 of ~30 Ghostty action callbacks (set_title, ring_bell,
scrollbar, close_surface). Clipboard is stubbed. Mytty (after Phase 1
completion, commit 10b5bd5) handles all 48 action cases. This means Mytty
users get working clipboard, fullscreen toggle, URL opening, desktop
notifications, and config reload. Mistty users get silent no-ops for these.

### 3D. Keybinding configurability

Mistty has no keybinding configuration. All bindings are hardcoded. Mytty's
KeybindingStore + TriggerParser + KeySequenceManager provide per-mode
bindings, multi-key sequences, conflict detection, and live reload. This is
a fundamental product differentiator.

---

## Part 4: The "Ghostty users should have things just work" principle

This is the overarching theme. Mytty should feel like a natural extension
of Ghostty, not a separate app that happens to use the same renderer.

### What "just work" means concretely

1. **Config carries over.** `~/.config/ghostty/config` is loaded as the
   base config. Fonts, colors, themes, keybindings for terminal actions
   all work without re-specifying. (Status: implemented in Phase 4.)

2. **Keybindings don't conflict.** Ghostty's default bindings work unless
   Mytty's config.toml explicitly overrides them. The dispatch priority
   (Modal > config.toml > Ghostty > unconsumed config.toml) ensures this.
   (Status: spec'd in ideal-state v3 Section 3, implementation in Phase 2.)

3. **Hot-reload works.** Changing `font-family` in Ghostty config updates
   the terminal within 1 second. (Status: Phase 3 of impl plan.)

4. **Dark/light mode syncs.** macOS appearance change updates terminal
   colors via `ghostty_surface_set_color_scheme`. (Status: Phase 4 of
   impl plan.)

5. **Option-as-alt works.** `macos-option-as-alt = true` in Ghostty config
   makes Option+key send Alt+key. (Status: Phase 5 of impl plan.)

6. **IME works.** CJK input via macOS input methods produces correct text.
   (Status: Phase 6 of impl plan.)

7. **New Ghostty features arrive automatically.** Submodule bump + action
   conformance checklist (spec v3 Section 10) ensures new libghostty
   capabilities are surfaced, not silently ignored.

### What "just work" does NOT mean

- It does NOT mean Mytty is a Ghostty skin. DESIGN.md: "What Mytty is not:
  a Ghostty fork or skin (we use their renderer, we own the chrome)."
- It does NOT mean every Ghostty config key is honored. Some are meaningless
  in Mytty (`macos-titlebar-style = tabs` when Mytty doesn't use native
  tabs). The audit of 44 window/macos keys (Roadmap 5d) will document which
  are honored, which are ignored, and why.
- It does NOT mean Mytty tracks Ghostty's UI decisions. Ghostty's tab bar,
  sidebar, and split management are completely different from Mytty's. The
  delegation boundary is the C API, not the Swift UI layer.

---


## Part 5: Ghostty macOS app patterns to study and adapt

The Ghostty macOS app (vendor/ghostty/macos/Sources/) is ~31K LOC of Swift
that solves many of the same problems Mytty faces. These files aren't
linkable (they're compiled into Ghostty.app, not GhosttyKit.xcframework),
but the patterns are directly applicable. This is level 2 of the delegation
hierarchy.

### 5A. Window chrome and titlebar management

**Ghostty's approach:** AppDelegate owns the NSWindow directly. No SwiftUI
WindowGroup. Window chrome (titlebar visibility, style mask, traffic light
position) is set at window creation time, not patched after the fact.

**Mytty's current approach:** SwiftUI WindowGroup creates the window, then
MyttyAppDelegate patches it via `windowDidUpdate`. This causes the
"DispatchQueue.main.async to modify styleMask" hack noted in the roadmap's
deferred items.

**What to study:** Ghostty's `Ghostty.TerminalController` (NSWindowController
subclass) + `NSHostingView` pattern. The roadmap already identifies this as
the fallback if Liquid Glass breaks the current approach. When that migration
happens, Ghostty's implementation is the reference, not a from-scratch design.

**Decision: STUDY, don't act yet.** The current approach works. When it
breaks (Liquid Glass, or the next macOS release), adapt Ghostty's pattern.
The deferred item in the roadmap already tracks this.

### 5B. Config key reading via ghostty_config_get

**Ghostty's approach:** The macOS app reads ~44 window/macos-specific config
keys from ghostty_config_t using type-safe wrappers. Each key has a Swift
property that calls the C API.

**Mytty's current approach:** Reads 3 of those 44 keys. The rest are either
handled by libghostty at the surface level or silently ignored.

**What to study:** The full list of 44 keys and which ones affect Mytty's
behavior. Roadmap Phase 5d ("Ghostty Config Compatibility") tracks this
audit. The Ghostty macOS app's config reading code is the definitive
reference for which keys matter and how to read them.

**Decision: STUDY during Phase 5d.** Don't read keys speculatively. Read
them when a feature needs them. But use Ghostty's reading patterns (type
wrappers, default handling) as the template.

### 5C. Clipboard handling

**Ghostty's approach:** Full clipboard read/write/confirm cycle. The confirm
callback shows a paste confirmation dialog for large or potentially dangerous
pastes. The clipboard request callback handles OSC 52.

**Mytty's current approach:** Working clipboard read/write (implemented in
Phase 1, commit 10b5bd5). No paste confirmation.

**What to study:** Ghostty's paste confirmation UI and the heuristics for
when to show it (large paste, control characters, bracketed paste mode).
This is a security feature that Mytty should eventually match.

**Decision: ADOPT the confirmation heuristic when adding paste safety.**
Not urgent, but when it's time, copy Ghostty's logic rather than inventing
new heuristics.

### 5D. Appearance and theme sync

**Ghostty's approach:** Observes `NSApplication.effectiveAppearance` changes,
calls `ghostty_surface_set_color_scheme` on all surfaces, and reads the
`window-theme` config key to determine whether to follow system, force light,
or force dark.

**Mytty's current approach:** Does nothing. Phase 4 of the impl plan adds
this.

**What to study:** Ghostty's `AppDelegate.appearanceDidChange` handler. It's
~10 lines. The `window-theme` config key reading is the part Mytty should
also adopt (it's one of the 44 keys from 5B).

**Decision: ADAPT during Phase 4.** This is a direct port of Ghostty's
pattern, not a Mytty invention.

### 5E. Surface lifecycle (creation, resize, close)

**Ghostty's approach:** Surface creation uses a builder pattern with
`ghostty_surface_config_s`. Resize uses `ghostty_surface_set_size` in
`viewDidLayout`. Close uses `ghostty_surface_free` with proper cleanup
ordering.

**Mytty's current approach:** Surface creation uses nested `withCString`
closures (~60 LOC of nesting). Phase 8 of the impl plan cleans this up.

**What to study:** Ghostty's `Ghostty.SurfaceView` for the creation and
lifecycle patterns. The impl plan already identifies this cleanup; Ghostty's
code is the reference for what "clean" looks like.

**Decision: ADAPT during Phase 8.** Use Ghostty's pattern as the target.

### 5F. Key event translation

**Ghostty's approach:** NSEvent+Extension.swift translates NSEvent to
ghostty_input_key_s. Handles dead keys, IME, option-as-alt, and function
keys.

**Mytty's current approach:** NSEvent+GhosttyKey.swift does the same
translation. The audit confirmed this is a near-copy of upstream and cannot
be eliminated (the upstream Swift files aren't in GhosttyKit). But it should
stay in sync.

**What to study:** On every Ghostty submodule bump, diff
`vendor/ghostty/macos/Sources/Ghostty/NSEvent+Extension.swift` against
`Mytty/App/NSEvent+GhosttyKey.swift`. The conformance checklist (spec v3
Section 10) should include this diff.

**Decision: TRACK.** Add to the bump-ghostty checklist. Don't diverge
without documenting why.

### The meta-principle

For every feature Mytty builds, ask: "How does Ghostty's macOS app handle
this?" If the answer is "it doesn't" (copy-mode, IPC, session manager),
build from scratch. If the answer is "it does, and here's how," adapt the
pattern. If the answer is "libghostty has a C API for this," call the API.

This is not about copying code. It's about not reinventing solutions to
problems that Ghostty's team (who wrote libghostty) has already solved for
the same platform.

---

## Summary of decisions

| Item | Decision | Rationale | When |
|------|----------|-----------|------|
| Hint navigation (1A) | ADOPT | Proven detection pipeline, maps to roadmap 5b | Phase 5b (after 4f-3) |
| Process icons (1B) | ADOPT (gated) | Pre-attentive signal, gate on font availability | Phase 5g or standalone |
| Snapshot testing (1C) | ADOPT incrementally | Add with new visual features, not retroactively | With first new visual feature |
| SSH host parser (1D) | ADOPT | Small, complements existing SSHConfigService | Anytime, no dependencies |
| GUI settings (2A) | REJECT | ADR-006 (config file only) stands | N/A |
| Binary IPC (2B) | REJECT | JSON-RPC is strictly better | N/A |
| ContentView monolith (2C) | REJECT | Extracted managers are a completed improvement | N/A |
| HexColor parser (2D) | REJECT | Ghostty's color parsing handles this | N/A |
| Window chrome (5A) | STUDY | Adapt Ghostty's pattern when current approach breaks | When Liquid Glass forces it |
| Config key audit (5B) | STUDY | Read keys when features need them | Phase 5d |
| Paste confirmation (5C) | ADOPT later | Security feature, copy Ghostty's heuristics | After core phases |
| Appearance sync (5D) | ADAPT | Direct port of Ghostty's pattern | Phase 4 of impl plan |
| Surface cleanup (5E) | ADAPT | Use Ghostty's pattern as target | Phase 8 of impl plan |
| Key translation sync (5F) | TRACK | Diff on every submodule bump | Ongoing |
| Port hint tests (7R1) | ADOPT | Edge case coverage too valuable to rewrite | With 1A (Phase 5b) |
| Snapshot test pattern (7R2) | ADOPT | Fix Mistty's shared-state bug in the port | With 1C |
| IPC socket integration test (7R5) | ADOPT | Highest-value untested path in both projects | Standalone, anytime |

### Priority relative to existing impl plan

The impl plan (v3) has 9 phases. The adoptions from this RFC slot in as:

1. Phases 1-3 (action callbacks, key dispatch, hot-reload): **do first, no RFC items needed**
2. Phase 4 (dark/light mode): **use Ghostty's pattern (5D above)**
3. Phase 5 (option-as-alt): **no RFC items needed**
4. Phase 6 (IME): **no RFC items needed**
5. **After Phase 6**: SSH host parser (1D) can land anytime as a small standalone PR
6. **Phase 5b (hints mode)**: port Mistty's HintDetector + HintLabels (1A)
7. **Phase 5g (session manager)**: process icons (1B)
8. Phase 7-9 (typed payloads, surface cleanup, dead code): **use Ghostty patterns (5E)**

Don't let RFC adoptions delay the impl plan. The impl plan phases are
higher priority because they fix architectural issues. RFC adoptions are
additive features.

---

## Part 6: Anti-patterns to avoid (lessons from Mistty's mistakes)

These aren't "reject Mistty's approach" items (Part 2 covers those). These
are patterns where Mistty's experience reveals a trap that Mytty could also
fall into.

### 6A. Silent config error swallowing

Mistty's config parser uses `(try? parse(contents)) ?? .default`. If the
TOML is malformed, the user gets default config with no indication anything
went wrong. They edit their config, restart, and nothing changes.

Mytty's current approach is better (captures parse errors into
`config.parseError`), but the roadmap notes that unknown keys (typos) are
still silently ignored. This is the same trap at a different level.

**Lesson:** Every config path should either succeed visibly or fail visibly.
The deferred "config error UI" and "config key validation" items in the
roadmap are not polish; they're correctness. Prioritize them before adding
more config surface area (4f-3 key tables, 5d Ghostty compat).

### 6B. Clipboard stubs that silently fail

Mistty's clipboard read/confirm callbacks are no-ops that return without
doing anything. This means OSC 52 (clipboard access from terminal programs)
silently fails. The user's `pbcopy` works (that's the shell, not the
terminal), but programs that use OSC 52 (like some vim clipboard plugins)
silently lose data.

Mytty fixed this in Phase 1 (commit 10b5bd5). The lesson is broader:
**never stub a libghostty callback as a no-op without logging.** If a
callback can't be implemented yet, log a warning so the user (or developer)
knows the feature is missing. The spec v3 Section 6 categorizes stubs as
"Category C (acknowledged stubs, return true)" which is correct, but the
implementation should log on first invocation.

### 6C. Hardcoded keybindings with no escape hatch

Mistty hardcodes all keybindings. If a binding conflicts with the user's
workflow, there's no way to change it. This is the single most common
complaint category for terminal emulators.

Mytty already solved this (KeybindingStore + TriggerParser). The lesson:
**when adding a new action, always add a default keybinding through the
config system, never hardcode it.** Even for "obvious" bindings like
Cmd+W = close pane. The config system exists; use it.

### 6D. Growing a monolith instead of extracting early

Mistty's ContentView grew to 41KB because each feature added "just a few
more lines" to the same file. No single addition was unreasonable. The
monolith emerged from accumulation, not design.

Mytty's ContentView is already split, but the same pattern can recur in
other files. Watch for: GhosttyApp.swift (currently ~323 LOC of bridge
code, could grow with each new action), ContentView+Handlers.swift
(currently ~23KB, could grow with each new notification handler).

**Lesson:** When a file crosses ~500 LOC, check whether it has multiple
responsibilities. If it does, extract before the next feature lands. Don't
wait for it to become painful.

---

## Part 7: Test infrastructure comparison (deep dive)

Both projects share the same test style (XCTest, `@MainActor`, inline
`make*` factories, no shared test utilities). The differences reveal
design choices worth examining.

### Shared patterns (identical in both)

- **No mocks, fakes, or stubs.** Both test against real model objects.
  `SessionStore`, `MyttySession`/`MisttySession`, `MyttyTab`/`MisttyTab`,
  `MyttyPane`/`MisttyPane` are created directly in tests. This works
  because the model layer is pure Swift with no libghostty dependency.
- **Per-file factory methods.** Each test file defines its own `makePane()`,
  `makeState()`, `makeSession()`. No shared test utility module.
- **libghostty is avoided entirely.** Tests never create a live terminal
  surface. `MyttyPane.surfaceView` exists but tests don't access it.
  Mistty's IPC tests that hit `sendKeys`/`getText` assert `operationFailed`
  because `pane.surfaceView.surface` is nil in test context.
- **IPCListener untested in both.** The Unix socket accept/dispatch loop
  (~14KB in Mytty) has zero test coverage. Both test the service layer
  directly (call protocol methods, check responses).
- **No CLI tests in either.** The `MyttyCLI`/`MisttyCLI` targets have no
  test coverage.

### Where Mytty is stronger

**Notification handler testing.** `ContentViewHandlerTests` calls handler
methods directly with hand-built `Notification` objects containing `userInfo`
dictionaries. This tests the handler logic without subscribing to real
notifications. Mistty has no equivalent; its handlers are inline closures
in ContentView with no test path.

**Key event testing.** Two patterns: `KeyEventEncodingTests` uses
`CGEvent(keyboardEventSource:virtualKey:keyDown:)` for realistic events.
`KeySequenceManagerTests` uses `NSEvent.keyEvent(with:...)` factory for
simpler cases. Mistty has no key event tests at all.

**Manager isolation.** Each extracted manager (PanelState, WindowModeManager,
PaneNavigationManager, CopyModeManager, WhichKeyManager, KeySequenceManager)
has its own test file with proper setUp/tearDown (including `deactivate()`
calls). Mistty can't test these because they don't exist as separate classes.

**Swift Testing adoption.** `KeyEventEncodingTests` uses Swift Testing
(`@Test`, `#expect`, struct-based) instead of XCTest. This is a newer
pattern that Mistty hasn't adopted.

### Where Mistty is stronger

**Snapshot testing.** `ChromePolishSnapshotTests` renders views offscreen
via `NSHostingView` in an `NSWindow`, comparing pixel output against
baseline PNGs. Covers: `TabBarView`, `SidebarView`, `SessionManagerView`,
`ContentView`, plus a 5x3 matrix of `TabBarMode` x `TitleBarStyle`
combinations. Registers a Nerd Font via `CTFontManagerRegisterFontsForURL`
for consistent rendering. Mytty has no visual regression testing.

**Caveat:** Mistty's snapshot tests have a shared-state risk:
`ChromePolishSnapshotTests` mutates `UserDefaults.standard` (the
`sidebarVisible` key) without cleanup in `tearDown`. This could cause
flaky failures if test ordering changes.

**Hint detection testing.** `HintDetectorTests` is thorough: trailing
punctuation stripping, emoji in URLs, UUID detection, path detection,
hash detection, code spans, quoted strings, env vars, bottom-to-top
ordering, longest-match-wins deduplication. `CopyModeHintIntegrationTests`
tests the full pipeline including label entry, action dispatch, and
two-char label routing. When porting hints (RFC item 1A), port these
tests too.

**Config edge cases.** `UIConfigTests` tests `TabBarMode.shouldShow` for
all 5 enum variants, `TitleBarStyle` properties, and
`TabBarVisibilityOverride` toggle logic. Mytty's config tests cover
parsing but not the behavioral implications of config values.

### Shared gaps (neither project tests these)

- GhosttyApp / ghostty integration layer
- App lifecycle (MyttyApp/MisttyApp, AppDelegate)
- View interaction (only Mistty has snapshot tests, neither has interaction tests)
- IPCListener socket layer
- ConfigWatcher / file-system reload
- ZoxideService
- CLI targets

### Recommendations for Mytty

**7R1. Port Mistty's hint tests alongside hint code (1A).** The detection
tests are the most valuable part. They encode edge cases (trailing
punctuation, overlapping matches) that would otherwise be rediscovered
through bugs.

**7R2. Add snapshot testing with the hint overlay (1C).** Use Mistty's
`host(_:size:)` pattern for offscreen rendering. Fix the shared-state
issue: add `tearDown` that resets `UserDefaults` keys.

**7R3. Extract shared test factories.** Both projects duplicate `makePane()`,
`makeState()`, etc. across files. This isn't urgent (Rule of Three is
barely met), but when the next test file needs `makePane()`, extract to a
shared `TestHelpers.swift` in the test target.

**7R4. Don't test the bridge.** Both projects correctly avoid testing
libghostty bridge code. The C API calls are thin (<20 LOC each) and
mechanical. Bugs surface immediately as visual glitches. Integration tests
requiring a live terminal surface are fragile and slow. The spec v3
Section 9 already documents this decision.

**7R5. Test the IPC socket path.** Neither project tests `IPCListener`.
This is the highest-value gap. A test that creates a real Unix socket,
sends a JSON-RPC request, and verifies the response would catch framing
bugs, connection lifecycle issues, and concurrent request handling. This
is more valuable than adding more unit tests for already-tested model code.

---

## Appendix: Ghostty macOS app file index

Key files in `vendor/ghostty/macos/Sources/` that Mytty agents should
consult before building features:

**Core bridge (level 2 delegation targets):**
- `Ghostty/Ghostty.App.swift` - app lifecycle, config loading
- `Ghostty/Ghostty.Action.swift` - action callback dispatch
- `Ghostty/Ghostty.Config.swift` - config key reading (type-safe wrappers)
- `Ghostty/Ghostty.Surface.swift` - surface lifecycle
- `Ghostty/Ghostty.Input.swift` - input event handling
- `Ghostty/NSEvent+Extension.swift` - NSEvent to ghostty key translation
- `Ghostty/Surface View/SurfaceView_AppKit.swift` - NSView surface impl

**Window management:**
- `App/macOS/AppDelegate.swift` - window creation, appearance sync
- `Features/Terminal/TerminalController.swift` - NSWindowController pattern
- `Features/Terminal/Window Styles/` - titlebar style implementations

**Features to study when building equivalents:**
- `Features/QuickTerminal/` - dropdown/quake terminal (compare to Mytty's)
- `Features/ClipboardConfirmation/` - paste safety heuristics
- `Features/Splits/SplitTree.swift` - split management (Mytty's is different)
- `Features/Global Keybinds/GlobalEventTap.swift` - CGEvent tap pattern
- `Features/Command Palette/` - command palette (roadmap 5f)
- `Features/Secure Input/` - secure input indicator

**Not relevant to Mytty (Ghostty-specific features):**
- `Features/AppleScript/` - Mytty uses JSON-RPC IPC instead
- `Features/App Intents/` - Shortcuts integration (future consideration)
- `Features/Custom App Icon/` - Ghostty-specific
- `Features/Update/` - Sparkle auto-update (Mytty roadmap 7g)
- `Features/About/` - Ghostty-specific

---

## Open questions (resolved)


1. **Hint detection scope:** Port all 9 pattern kinds. The regexes are
   already written and tested. Shipping a subset saves no meaningful time
   (the wiring is the same regardless of pattern count) and creates a
   "why doesn't it detect emails?" support burden. The spec for 5b should
   note that individual kinds can be disabled via config if users find
   false positives noisy.

2. **Nerd Font dependency:** Detect availability at runtime. If the user's
   configured font includes the Nerd Font glyphs, show icons. If not, fall
   back to the current text-only sidebar. Don't bundle a fallback font (adds
   ~2MB to the app bundle for a cosmetic feature). Document the recommendation
   in config-example.toml. This matches tenet 5: "opinionated defaults,
   constrained configuration."

3. **Snapshot test scope:** Start with the hint overlay (new visual feature,
   clear rendering contract). Add sidebar and tab bar snapshots only after
   the visual design stabilizes (post-Phase 5 polish). Don't snapshot views
   that are actively being redesigned.

---

## Delegation checklist for agents

Before writing new code for any feature, run through this checklist:

```
1. Does libghostty have a C API for this?
   → Yes: call it. Write ≤20 LOC of bridge code.
   → Check: grep vendor/ghostty/include/ghostty.h for relevant symbols.

2. Does Ghostty's macOS app (vendor/ghostty/macos/Sources/) solve this?
   → Yes: study the pattern. Adapt, don't copy (the code isn't linkable).
   → Check: find vendor/ghostty/macos/Sources -name '*.swift' | xargs grep <keyword>

3. Does Mistty (~/Code/mistty-orig/) have a working implementation?
   → Yes: evaluate for portability. Port if it's pure Swift with no
     architectural coupling. Rewrite if it's coupled to Mistty's patterns.
   → Check: find ~/Code/mistty-orig -name '*.swift' | xargs grep <keyword>

4. None of the above apply?
   → Build from scratch. This is Mytty-original value.
   → Document why levels 1-3 don't apply in the spec or commit message.
```

The goal: Mytty's original code should be exclusively in the "what Mytty
owns" category (spec v3 Section 11): copy-mode, IPC, session manager,
keybinding system, sidebar/tab bar, pane layout, config system, dropdown,
which-key, window-mode, popup system, theme system. Everything else should
be a thin bridge to something that already exists.

---

## Sources

- [2026-04-18] ~/Code/mistty-orig/ (Mistty source, milch/mistty@332b2ae)
- [2026-04-18] ~/Code/mistty/ (Mytty source, AJamesyD/mytty@0bbb454)
- [2026-04-18] /tmp/ai-spec-mytty-ideal-state-v3.md
- [2026-04-18] /tmp/ai-audit-mytty-delegation.md
- [2026-04-18] /tmp/ai-research-mytty-vs-mistty-comparison.md
- [2026-04-18] ~/Code/mistty/docs/DESIGN.md
- [2026-04-18] ~/Code/mistty/docs/ROADMAP.md (iteration 24)
