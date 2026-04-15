# ADR-004: Unix Socket IPC

Status: accepted
Date: 2026-03-18

## Context

Mistty's CLI needs to communicate with the running app to create sessions,
send keystrokes, query state, and control windows. Options:

1. **Apple XPC.** Built-in serialization and launchd integration. But XPC
   requires `@objc` protocols, ties the CLI to Apple frameworks, and
   launchd plist management caused duplicate app launches in early development.

2. **Mach ports (CFMessagePort).** Similar Apple framework dependency, plus
   unreliable port discovery. The initial implementation hit connection failures.

3. **Unix domain socket.** No framework dependency. Works from any language.
   Simple to debug with `nc` or `socat`.

## Decision

Unix domain socket at `~/Library/Application Support/Mistty/mistty.sock`
with length-prefixed JSON framing. Each message is a 4-byte big-endian
length followed by a JSON payload. Responses start with a status byte
(0x00 success, 0x01 error) followed by JSON data.

One request per connection. The CLI connects, sends a request, reads the
response, and disconnects. The app accepts connections on a background
DispatchQueue and bridges to `@MainActor` for service method dispatch.

The directory is created with 0700 permissions. Stale sockets from crashed
processes are unlinked on startup.

## Consequences

- Debuggable: developers can test the API with `nc` or `socat`.
- Language-agnostic: any tool that can open a Unix socket can script Mistty.
- No Apple framework dependency in the transport layer.
- Lost XPC's built-in serialization and launchd lifecycle management.
  We handle framing and app auto-launch ourselves.
- No authentication beyond filesystem permissions (0700 directory).
  Acceptable for a local terminal emulator.

## Lesson

This decision directly serves Tenet 4 in DESIGN.md: "The terminal's value
multiplies when scriptable. Every stable operation is available via CLI and
socket API. The GUI and CLI are peers, not primary and secondary."
