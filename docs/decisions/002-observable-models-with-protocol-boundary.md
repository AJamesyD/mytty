# ADR-002: Observable Models with Protocol Boundary

Status: accepted
Date: 2026-03-06

## Context

Mistty manages a hierarchy: SessionStore holds sessions, sessions hold tabs,
tabs hold panes. We needed a model layer for this hierarchy. Options:

1. **CoreData / SwiftData.** Persistence built in, but heavy frameworks with
   their own object lifecycle. Testing requires mock stores or in-memory
   configurations. Schema migrations add ongoing cost.

2. **Plain @Observable classes.** Simple, testable, no framework dependency.
   But if we later need persistence or a daemon process, we'd have to
   retrofit an abstraction boundary.

3. **@Observable classes behind protocols.** Same simplicity as plain classes,
   but the protocol boundary lets us swap the backing store without changing
   the UI layer.

## Decision

Option 3. Five `@MainActor @Observable` classes (SessionStore, MisttySession,
MisttyTab, MisttyPane, PopupState) back the protocols today. The UI layer
depends on the protocol, not the concrete class.

In-memory storage is sufficient for the current product (no daemon, no
attach/detach). The protocol boundary exists so that a future daemon mode
can provide a different backing store without touching any view code.

## Consequences

- Testing is simple: create real instances of SessionStore and its children.
  No mocks needed, no persistence framework to configure.
- No lock-in to CoreData, SwiftData, or any persistence framework. The
  protocol is the escape hatch.
- The protocol boundary adds a small amount of indirection. Every model
  property that views read must be declared in the protocol.
- All model classes use `@Observable` (Observation framework). We do not use
  `ObservableObject` or `@Published`, which are legacy patterns in this project.

## Lesson

This decision produced the architecture constraint in DESIGN.md:
"Session/Tab/Pane are protocol-based. The backing store can be replaced
with a daemon without touching the UI layer. Do not leak storage
assumptions into views."
