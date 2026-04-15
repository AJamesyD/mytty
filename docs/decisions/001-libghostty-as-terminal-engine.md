# ADR-001: libghostty as Terminal Engine

Status: accepted
Date: 2026-03-06

## Context

Mistty needed a terminal rendering engine. Three options:

1. **Build from scratch.** Full control, but terminal emulation is a
   multi-year effort (VT parsing, sixel graphics, ligature shaping, GPU
   rendering). This would consume all development time with no product
   differentiation.

2. **Fork Ghostty.** Gives us a working terminal and the freedom to modify
   internals. But forking means maintaining a diverging codebase, merging
   upstream changes becomes painful, and we'd own bugs in code we didn't write.

3. **Embed libghostty.** Use Ghostty's C library as a rendering engine.
   libghostty handles terminal parsing, rendering, and input. Mistty owns
   everything above the surface: session management, UI, IPC, configuration.

## Decision

Embed libghostty. One `ghostty_app_t` per process, one `ghostty_surface_t`
per pane. Mistty creates surfaces, forwards input events, and receives
typed action callbacks. All terminal protocol parsing stays inside libghostty.

The integration boundary is C function pointers: six runtime callbacks for
app lifecycle, plus an action callback that delivers events (title changes,
bell, close requests) back to the host. C callbacks cannot capture Swift
context, so we use the `Unmanaged` userdata pattern to bridge.

## Consequences

- Mistty ships a working terminal from day one. Development focuses on
  session management, the sidebar, and IPC, not terminal correctness.
- A thin C callback bridge (GhosttyApp.swift) is the only file that touches
  libghostty types directly. The rest of the app works with Swift models.
- Mistty is tied to Ghostty's release cycle for terminal improvements.
  We track upstream via a git submodule in `vendor/ghostty/`.
- libghostty requires Zig 0.15.2 (provided by the Nix devshell). This adds
  a build dependency that contributors must install.

## Lesson

This decision produced the architecture constraint in DESIGN.md:
"libghostty parses all escape sequences internally." Mistty handles typed
action callbacks. Do not parse raw escape sequences. Do not duplicate
Ghostty's terminal logic.
