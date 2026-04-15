# ADR-003: NotificationCenter for Action Routing

Status: accepted
Date: 2026-03-13

## Context

libghostty delivers events (title changes, bell, close requests) via a C
action callback. C function pointers cannot capture Swift context, so the
callback is a top-level function in GhosttyApp.swift. We needed a way to
route these events into SwiftUI for model updates.

Alternatives considered:

1. **Delegate pattern.** The callback has no captures, so we'd need a
   global or userdata pointer to reach the delegate. Couples the callback
   to a specific handler object.

2. **Combine publishers.** Adds a framework dependency to the model layer.
   We avoid Combine in model code to keep concurrency simple (@MainActor +
   Observation).

3. **Async streams.** Bridging from C to AsyncStream requires a continuation
   stored somewhere the callback can reach. Complex for fire-and-forget events.

## Decision

NotificationCenter. The C action callback posts a notification with the
event data. SwiftUI views subscribe with `.onReceive`. Handler methods in
`ContentView+Handlers.swift` translate notifications into model updates.

Adding a new action means: handle in the C callback, add a
Notification.Name, add `.onReceive`, add a handler method, add a test.

## Consequences

- Decoupled: the C callback knows nothing about SwiftUI or the model layer.
  It posts a notification and returns.
- Testable: tests post notifications directly and verify handler behavior.
  No need to simulate libghostty.
- Stringly-typed: notification names are strings. Typos compile but fail
  silently. A Notification.Name extension centralizes all names to mitigate.
- One-directional by construction: notifications flow from libghostty toward
  SwiftUI, never the reverse.

## Lesson

This decision produced the architecture constraint in DESIGN.md:
"State flows one direction: libghostty -> C callbacks -> NotificationCenter
-> handlers -> model updates -> SwiftUI reactivity. Do not reverse this flow."
