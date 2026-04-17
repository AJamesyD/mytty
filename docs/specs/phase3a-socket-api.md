# Phase 3a: JSON-RPC Socket API

Mytty macOS terminal emulator, libghostty backend.

**Goal:** Replace the IPC transport layer with JSON-RPC 2.0 over persistent Unix domain socket connections. The service protocol methods and business logic are preserved. The new transport adds protocol-level versioning, structured errors, and event streaming.

**Date:** 2026-04-15

---

## 1. Protocol choice

### Current

Custom length-prefixed binary framing: 4-byte UInt32 big-endian length prefix, followed by the payload. Responses are prefixed with a status byte (0x00 success, 0x01 error) before the response payload. Connections are one-shot.

### Proposed

JSON-RPC 2.0 messages framed with LSP-style `Content-Length` headers. Each message is:

```
Content-Length: <byte-count>\r\n\r\n<json-rpc-message>
```

The `jsonrpc: "2.0"` field provides protocol-level versioning. The framing is identical to the Language Server Protocol's base protocol.

### Alternatives rejected

- **MessagePack-RPC:** No maintained Swift RPC library. Binary format makes debugging harder.
- **Cap'n Proto:** No Swift support.
- **Custom evolved protocol:** JSON-RPC 2.0 already standardizes what a custom protocol would become (method dispatch, error codes, request/response correlation).
- **Wezterm binary PDU:** Rust-specific, not portable to Swift.
- **Kitty escape-sequence framing:** Coupled to TTY transport, not suitable for socket IPC.

---

## 2. Connection lifecycle

### Current

One-shot: connect, send request, read response, close. The CLI creates a new connection per command.

### Proposed

Persistent connections. The client connects once, sends multiple requests, and receives responses and notifications. The connection stays open until the client disconnects or the server shuts down.

**Handshake:** The client sends an `initialize` request as the first message after connecting. The server responds with capabilities and version. This follows the LSP pattern.

Request:
```json
{"jsonrpc":"2.0","method":"initialize","params":{"clientVersion":"1.0","clientName":"mytty-cli"},"id":0}
```

Response:
```json
{"jsonrpc":"2.0","result":{"serverVersion":"1.0","capabilities":{"events":true}},"id":0}
```

**Graceful shutdown:** The server sends a `shutdown` notification to all connected clients before closing. Clients should handle connection close gracefully.

**Backward compatibility:** During migration, the server detects whether an incoming connection uses the old protocol (first 4 bytes are a UInt32 length) or the new protocol (first bytes are ASCII `C` from `Content-Length:`). This allows the CLI and app to be updated independently. Remove old protocol support in Phase 3a-3.

---

## 3. Method mapping

All 31 existing methods from `MyttyServiceProtocol` map to JSON-RPC method names using `noun.verb` convention.

**Sessions (5):** `session.create`, `session.list`, `session.get`, `session.close`, `session.rename`

**Tabs (6):** `tab.create`, `tab.list`, `tab.get`, `tab.close`, `tab.rename`, `tab.move`

**Panes (11):** `pane.create`, `pane.list`, `pane.get`, `pane.close`, `pane.focus`, `pane.focusByDirection`, `pane.resize`, `pane.active`, `pane.sendKeys`, `pane.runCommand`, `pane.getText`

**Windows (5):** `window.create`, `window.list`, `window.get`, `window.close`, `window.focus`

**Popups (4):** `popup.open`, `popup.list`, `popup.close`, `popup.toggle`

**New methods (3):** `initialize`, `subscribe`, `unsubscribe`

### Example: session.create

```
-> Content-Length: 93\r\n\r\n{"jsonrpc":"2.0","method":"session.create","params":{"name":"Dev","directory":"/tmp"},"id":1}
<- Content-Length: 84\r\n\r\n{"jsonrpc":"2.0","result":{"id":1,"name":"Dev","directory":"/tmp","tabs":[]},"id":1}
```

The `params` object uses the same parameter names as the current protocol. The `result` object uses the same response models from `MyttyShared/Models/`.

`pane.sendKeys` and `pane.runCommand` use `paneId: 0` as sentinel for "active pane", preserving current behavior.

---

## 4. Error handling

### Current

Status byte 0x01 followed by a raw UTF-8 error string. Structured error codes (`entityNotFound`, `invalidArgument`, `operationFailed`) from `MyttyIPC.ErrorCode` are lost in transit.

### Proposed

JSON-RPC error objects with application-defined codes:

| Code | Name | Current enum value |
|------|------|-------------------|
| 1001 | entityNotFound | ErrorCode.entityNotFound (1) |
| 1002 | invalidArgument | ErrorCode.invalidArgument (2) |
| 1003 | operationFailed | ErrorCode.operationFailed (3) |
| 1004 | notSupported | (new, for createWindow) |

Codes 1001-1999 are reserved for Mytty application errors. The JSON-RPC reserved range (-32768 to -32000) is used for protocol-level errors (parse error, invalid request, method not found).

Example error response:

```json
{"jsonrpc":"2.0","error":{"code":1001,"message":"Session not found","data":{"entityType":"session","entityId":42}},"id":5}
```

---

## 5. Event streaming

### Current

No event support. The CLI polls or makes one-shot queries.

### Proposed

JSON-RPC notifications (messages without `id`) sent from server to client on subscribed events.

**Subscription flow:**

1. Client sends `subscribe` request with event filter: `{"events": ["session.closed", "pane.titleChanged"]}`
2. Server returns subscription ID: `{"subscriptionId": "sub-abc123"}`
3. Server pushes notifications: `{"jsonrpc":"2.0","method":"session.closed","params":{"subscriptionId":"sub-abc123","sessionId":1}}`
4. Client sends `unsubscribe` with the subscription ID to stop.
5. On disconnect, all subscriptions for that client are cleaned up automatically.

**Event types (initial set):**

- `session.created`, `session.closed`, `session.renamed`
- `tab.created`, `tab.closed`, `tab.renamed`
- `pane.created`, `pane.closed`, `pane.focused`, `pane.titleChanged`, `pane.exited`
- `window.closed`
- `app.willTerminate`

More event types can be added without protocol changes.

**Wildcard subscription:** `{"events": ["session.*"]}` subscribes to all session events. `{"events": ["*"]}` subscribes to everything.

---

## 6. Server concurrency model

### Current

`DispatchSemaphore.wait()` blocks a GCD thread until a `@MainActor Task` completes. This is a known anti-pattern that ties up thread pool slots.

### Proposed

Replace with Swift Concurrency:

```
Socket read loop (background Task)
  -> parse JSON-RPC request
  -> await service.method() on @MainActor
  -> encode JSON-RPC response
  -> write to socket
```

Each connection gets its own `Task`. Cancellation propagates on disconnect. The listener uses raw `FileDescriptor` with async read/write (Swift 6 structured concurrency). SwiftNIO is an alternative but would add a third-party dependency that the project does not currently have. The spec requires that the semaphore bridge is eliminated and that connection handling uses structured concurrency.

`MyttyServiceProtocol` changes from callback-based (`reply: @escaping (Data?, Error?) -> Void`) to async/await (`async throws -> Codable`). This is the largest change in the migration.

### Alternative

Keep the callback-based protocol and wrap it in `withCheckedContinuation` at the dispatch layer. This minimizes changes to `MyttyIPCService` but leaves the callback pattern in place. The full async migration is recommended since the callback pattern exists only because of the semaphore bridge.

---

## 7. Client changes

### Current

`IPCClient` in `MyttyCLI/XPCClient.swift` (misnamed). Creates a new connection per `call()`. Launches Mytty.app via `open -a` if the socket is unavailable.

### Proposed

- Rename file to `IPCClient.swift` (fix historical misnaming).
- Persistent connection: connect once, reuse for all commands in a CLI invocation.
- For simple CLI commands (e.g., `mytty-cli session list`), the connection lifecycle is: connect, initialize, call method, disconnect. The persistent connection matters more for future scripting and watch modes.
- Add `--watch` flag pattern: connect, subscribe to events, print notifications as they arrive. Example: `mytty-cli session list --watch` prints the initial list then streams create/close events.
- Keep the auto-launch behavior (connect, fail, launch app, retry with backoff).

---

## 8. Migration strategy

Phased approach to avoid breaking the CLI while the app is updated:

1. **Phase 3a-1:** Add JSON-RPC listener alongside the existing listener on the same socket. Detect protocol by first bytes. Add `initialize` handshake. Migrate `session.*` methods as proof of concept.
2. **Phase 3a-2:** Migrate remaining methods. Add event subscription. Migrate `MyttyServiceProtocol` to async/await.
3. **Phase 3a-3:** Remove old protocol support. Rename `XPCClient.swift`. Clean up.

Each sub-phase is a separate commit that passes all tests.

---

## 9. Files changed

Modified files:

| File | Changes |
|------|---------|
| `Mytty/Services/IPCListener.swift` | Replace transport: Content-Length framing, persistent connections, JSON-RPC dispatch, Swift Concurrency |
| `MyttyShared/MyttyServiceProtocol.swift` | Migrate from callback-based to async/await |
| `MyttyShared/IPCConstants.swift` | Add JSON-RPC error codes (1001-1004), protocol version constant |
| `Mytty/Services/IPCService.swift` | Update method signatures to async/await |
| `MyttyCLI/XPCClient.swift` (rename to `IPCClient.swift`) | Rename, persistent connection, Content-Length framing, JSON-RPC client |
| `MyttyCLI/Commands/*.swift` | Update call sites for new client API |
| `MyttyShared/Models/` | No changes (response models preserved) |

New files:

| File | Purpose |
|------|---------|
| `MyttyShared/JSONRPCModels.swift` | Request, Response, Notification, Error Codable types |
| `Mytty/Services/EventBroker.swift` | Manages subscriptions and dispatches notifications to connected clients |

---

## 10. Testing

Unit tests for:
- JSON-RPC message parsing (request, response, notification, error, batch)
- Content-Length framing (encode/decode, partial reads, oversized messages)
- Method name mapping (all 31 methods dispatch correctly with new names)
- Error code mapping (application codes 1001-1004, protocol error codes)
- Event subscription lifecycle (subscribe, receive, unsubscribe, disconnect cleanup)
- Initialize handshake (version negotiation, capability reporting)
- Protocol detection (old vs new format during migration)

Integration test:
- CLI end-to-end: `mytty-cli session list` works with the new protocol

---

## 11. Out of scope

| Feature | Reason | Target |
|---------|--------|--------|
| TLS/authentication | Unix socket permissions (0700) are sufficient for local use | Future, if remote access needed |
| Binary streaming | No current method needs raw binary; base64 is fine for getText | Future, if terminal output streaming added |
| HTTP transport | JSON-RPC is transport-agnostic but HTTP adds complexity for no local benefit | Not planned |
| Batch requests | No CLI command currently needs batching | Future, if scripting API added |
| `createWindow` removal | Dead method, but removing it is a separate cleanup | Phase 3a cleanup |

---

## 12. Acceptance criteria

- `mytty-cli session list` returns results using JSON-RPC 2.0 over the new protocol.
- `mytty-cli session create --name Test` creates a session and returns a JSON-RPC result.
- Error responses include structured error codes (e.g., `{"code": 1001}` for entity not found).
- `mytty-cli --version` and `initialize` handshake report matching protocol versions.
- Event subscription: a test client can subscribe to `session.created`, create a session via a second connection, and receive the notification.
- No `DispatchSemaphore` usage remains in `IPCListener.swift`.
- Old protocol detection works during migration phase (Phase 3a-1 and 3a-2).
- All existing CLI commands work without behavior changes (same output, same exit codes).
- `swift test` passes with no new warnings.
