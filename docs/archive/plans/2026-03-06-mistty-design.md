> **Superseded by [docs/DESIGN.md](../DESIGN.md).** This document is the original
> MVP design from 2026-03-06, kept for historical reference.

# Mistty Design

## Overview

Mistty is a macOS terminal emulator built on libghostty with a session-first workflow. The core differentiator is native tmux-style session management built directly into the terminal — no separate multiplexer required.

**Tech stack:** Swift + SwiftUI + libghostty
**Config:** XDG-compliant at `~/.config/mistty/config.toml`
**MVP scope:** Core terminal + session workflow (session manager, fuzzy find) + tabs + split panes

---

## Architecture

Two phases:

**Phase 0 — Spike**

A minimal Xcode project that links libghostty, renders one terminal in a SwiftUI window via `NSViewRepresentable`, and handles basic input/output. Goal: understand the libghostty surface lifecycle, event model, and rendering requirements. Output: a short spike doc capturing what the library requires. MVP architecture may be adjusted based on spike findings.

**Phase 1 — MVP**

Three-layer architecture:

```
UI Layer (SwiftUI)
  ├── Sidebar (session tree)
  ├── Session Manager overlay (cmd+j)
  ├── Tab bar + pane layout
  └── Window mode / copy mode overlays

Session Layer (Swift protocols)
  ├── MisttySession  (owns tabs)
  ├── MisttyTab      (owns panes)
  └── MisttyPane     (wraps a terminal surface)

Terminal Layer (libghostty)
  └── NSViewRepresentable wrapping a ghostty_surface_t
```

Sessions, tabs, and panes are protocol-based so the backing store (currently in-memory `@Observable` classes) can be replaced with a background daemon (tmux server model) later without touching the UI layer.

Config is parsed at launch and exposed as an `@Observable` singleton.

---

## Components

### Session Manager overlay (`cmd+j`)

Fullscreen-ish fuzzy-find overlay. Data sources:
- Running in-memory sessions
- Recent directories via `zoxide` (shell out to `zoxide query -l`)
- SSH hosts parsed from `~/.ssh/config`

Filtered with a fuzzy matching Swift package. Enter opens an existing session or creates a new one in the selected directory/host. Keyboard-only navigation.

### Sidebar

`NavigationSplitView` left column. Shows a tree: sessions at the top level, tabs nested beneath each. Collapsible per-session with a chevron. Hideable globally via `cmd+s` (stored as `@AppStorage`). Bell activity indicators on tabs/sessions with unread output.

### Session / Tab / Pane model

`@Observable` classes: `SessionStore` (root) → `[MisttySession]` → `[MisttyTab]` → `[MisttyPane]`. Each `MisttyPane` holds a `ghostty_surface_t` handle. Protocols define the interface so the backing can swap to a daemon. Active pane/tab/session tracked as `@State` in the root view.

### Terminal surface

`NSViewRepresentable` wrapping the libghostty surface (exact shape determined by spike). One surface per pane. Handles focus, keyboard input forwarding, and resize events.

### Split pane layout

App-managed (not libghostty's layout). SwiftUI `HSplitView`/`VSplitView` or a custom recursive layout depending on spike findings. Each leaf is a terminal surface view.

---

## Data Flow

**Session creation:**
`cmd+j` → user selects directory/host → `SessionStore.createSession(directory:)` → creates `MisttySession` with one `MisttyTab` containing one `MisttyPane` → libghostty surface initialized → shell spawned in that directory → sidebar updates reactively.

**Input path:**
Key event → focused `NSView` → forwarded to `ghostty_surface_t` → libghostty processes → PTY write.

**Output path:**
libghostty reads PTY → renders to surface → triggers view redraw. Bell events bubble up through pane → tab → session to update sidebar indicators.

**Config:**
Parsed once at launch from `~/.config/mistty/config.toml` into a `MisttyConfig` struct. Exposed as an environment object. No live-reload for MVP.

---

## Error Handling

MVP approach — keep it simple:
- If libghostty surface initialization fails: show an error view in the pane
- If `zoxide` or SSH config parsing fails: silently omit those sources from the session manager overlay — the app still works with just running sessions

---

## Testing

- Unit tests: session model (create/close/switch sessions, tab management) and config parser
- libghostty surface and SwiftUI views: manual testing only for MVP
- Integration tests: post-MVP

---

## Post-MVP Features

From the original plan, deferred after MVP:
- Session persistence via background daemon (designed for from day one)
- Save/restore layouts
- Window mode (`cmd+x`) with pane resize, swap, break, merge, rotate
- Copy mode (vim-style scrollback navigation)
- Sidebar bell activity
- Tab rename
- Preference pane
- Live config reload
