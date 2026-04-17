# ADR-005: Mytty Owns the Session Hierarchy

Status: accepted
Date: 2026-03-06

## Context

libghostty has its own concept of tabs and splits. Ghostty (the app) uses
these to manage its window layout. Two options:

1. **Delegate to libghostty.** Less code, but Mytty becomes a skin over
   Ghostty with no control over session structure, persistence, or sidebar.

2. **Own the hierarchy.** Mytty manages SessionStore, sessions, tabs, and
   panes. libghostty only owns the rendering surface. More code, full control.

## Decision

Option 2. Mytty owns the full hierarchy:

```
SessionStore -> [MyttySession] -> [MyttyTab] -> [MyttyPane]
```

Each pane creates and owns a `ghostty_surface_t` for rendering. libghostty
knows nothing about sessions, tabs, or how panes are arranged. The split
layout is a recursive tree managed by Mytty's layout engine, not by
libghostty's built-in split model.

## Consequences

- The sidebar, session persistence, IPC, and custom split layouts are all
  possible because Mytty controls the data model.
- Future features (floating panes, saved layouts, daemon mode) build on
  this hierarchy without touching the terminal layer.
- Cost: Mytty implements tab and split management from scratch (creation,
  closing, reordering, focus tracking, split resize).
- The IPC layer operates on Mytty's model objects. The CLI can create
  sessions, manage tabs, and query pane state because Mytty owns these
  concepts.

## Lesson

This decision produced the architecture constraint in DESIGN.md:
"Three layers: UI (SwiftUI), Session (@Observable models), Terminal
(libghostty). Do not add business logic to the UI layer. Do not access
libghostty types outside TerminalSurfaceView and GhosttyApp.swift."

Owning the session hierarchy is what makes Mytty a product rather than
a Ghostty wrapper. Every feature in the roadmap depends on this separation.
