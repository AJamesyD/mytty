# Mytty Design

## Identity

Mytty is a macOS terminal emulator that eliminates the need for a separate
multiplexer. The thesis: you never leave your flow to check what's happening.

What Mytty is:
- A native macOS app that embeds libghostty for terminal rendering
- A session manager that replaces tmux for local workflows
- A platform for terminal automation via its socket API and CLI

What Mytty is not:
- A cross-platform terminal (macOS only, by design; see [ROADMAP.md](ROADMAP.md) for scope)
- A Ghostty fork or skin (we use their renderer, we own the chrome)
- A tmux replacement for remote workflows (no daemon, no attach/detach)
- A plugin platform (the socket API covers automation)

## Design Tenets

Beliefs about how a terminal should work. They guide decisions we haven't
made yet.

1. **Keyboard-fast, mouse-unsurprising.**
   Every operation has a keyboard path, and that path should be the
   fastest. When users reach for the mouse, standard macOS behaviors
   work: click to focus, drag to select, right-click for context menus.
   We don't build mouse-first features, but we don't break mouse
   expectations either.

2. **Background awareness over information density.**
   The sidebar is a peripheral awareness channel, not a dashboard.
   Show signals (glow dots, counts), not data (git branches, file paths).
   The shell prompt already shows what the active pane needs. The sidebar
   shows what background panes need your attention for.
   Lesson: we built session-level git metadata and working directory
   display, then reverted both (D3). Per-pane data doesn't belong at
   session level. Sessions span multiple repos.

3. **Pre-attentive signals over cognitive ones.**
   Color and motion process before conscious attention. Icons and text
   require reading. For status indicators, prefer visual properties that
   register peripherally (color, size, position) over symbolic ones that
   require identification (icons, labels).
   Lesson: SF Symbols required scanning each icon to decode meaning.
   Glow dots registered in peripheral vision without focused attention (D2).

4. **The terminal's value multiplies when scriptable.**
   Every stable operation is available via CLI and socket API. The GUI and
   CLI are peers, not primary and secondary. Features that can't be scripted
   are features that can't be composed with other tools.

## Architecture Constraints

Technical boundaries. Do not change without discussion.

- **Three layers: UI (SwiftUI), Session (@Observable models), Terminal
  (libghostty).** Do not add business logic to the UI layer. Do not access
  ghostty_surface_t outside TerminalSurfaceView, GhosttyApp.swift,
  CopyModeManager.swift, KeySequenceManager.swift, IPCService.swift,
  PaneView.swift, and PaneNavigationManager.swift.

- **libghostty parses all escape sequences internally.** Mytty handles
  typed action callbacks (notification names route actions from C callbacks
  to SwiftUI). Do not parse raw escape sequences. Do not duplicate Ghostty's
  terminal logic.

- **State flows one direction:** libghostty -> C callbacks ->
  NotificationCenter -> handlers -> model updates -> SwiftUI reactivity.
  Do not reverse this flow.

- **Session/Tab/Pane are concrete @Observable classes.** 5 model classes
  (SessionStore, MyttySession, MyttyTab, MyttyPane, PopupState) form the
  session hierarchy. The IPC protocol (MyttyServiceProtocol) provides the
  abstraction boundary for external consumers. Do not leak storage
  assumptions into views.

- **IPC contract is the protocol.** MyttyServiceProtocol
  defines the boundary between transport and logic. Protocol, Service,
  Listener, and CLI must stay in sync.

- **Do not modify vendor/ghostty/.** Track upstream, don't fork. One
  ghostty_app_t per process, one ghostty_surface_t per pane.

## Ghostty Concept Mapping

Map Ghostty objects to Mytty objects as follows. Multiple sessions share
one NSWindow, which has no Ghostty counterpart.

| Ghostty | Mytty   | Notes |
|---------|---------|-------|
| App     | App     | 1:1. Single ghostty_app_t per process. |
| Window  | Session | Ghostty's window is an independent container of tabs. Mytty's session serves the same role. |
| Tab     | Tab     | 1:1. Mytty owns tab lifecycle; Ghostty tab actions route to Mytty's tab model. |
| Surface | Pane    | 1:1. A single terminal instance owning one ghostty_surface_t. |

**Action mapping rules:**

- **Window-level actions target the session** containing the triggering
  pane. Exception: actions controlling physical window geometry (fullscreen,
  maximize, reset size) target the containing NSWindow.
- **Surface-level actions target the pane.**
- **App-level actions target the app.**
- **Implement actions with a natural Mytty equivalent.** Do not leave them
  as no-ops. Actions with no natural equivalent (GTK-specific, inspector,
  search) are acknowledged as no-ops with a comment in GhosttyApp.swift
  explaining the gap.

**Target mappings:**

Action names below omit the `GHOSTTY_ACTION_` prefix. These are the
intended mappings. See GhosttyApp.swift for current implementation status.

- `CLOSE_WINDOW` -> close the session containing the triggering pane
- `NEW_WINDOW` -> create a new session
- `GOTO_WINDOW` -> switch to a session by index
- `CLOSE_ALL_WINDOWS` -> close all sessions
- `CLOSE_TAB` -> close the tab containing the triggering pane
- `TOGGLE_FULLSCREEN` -> toggle fullscreen on the containing NSWindow
- `QUIT` -> terminate the app

## Process Commitments

How we work. These govern the roadmap and development workflow.

- Spec before code: every feature gets a written spec before implementation.
- Cleanup gates before major phases: tech debt addressed before it compounds.
- Visual quality ships with features: if it looks unfinished, it is unfinished.
- IPC parity: stable noun+verb operations get IPC in the same commit as GUI.
- Do not add Apple framework dependencies beyond AppKit, SwiftUI,
  UserNotifications, and Carbon (transitive via GhosttyKit) without discussion.

## Key Interfaces

```
SessionStore -> [MyttySession] -> [MyttyTab] -> [MyttyPane]
```

Each layer is @Observable, @MainActor. Pane owns the ghostty_surface_t.

**MyttyServiceProtocol**: the IPC contract. Sessions, Tabs, Panes, Windows,
and Popups as nouns; CRUD + focus/resize/sendKeys as verbs.

**MyttyTheme**: single source for all color tokens. Views reference tokens,
not raw colors.

**GhosttyApp**: singleton managing the ghostty_app_t lifecycle. C callbacks
(no captures) post notifications that handlers route to model updates.
