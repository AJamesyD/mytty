# CLI Control & IPC Design

## Overview

Add CLI control to Mytty via XPC IPC. A separate `mytty-cli` binary communicates with the running Mytty.app through a Mach service, enabling scripting workflows, editor integration, and system automation.

## Architecture

```
mytty-cli ──XPC──► Mytty.app (NSXPCListener)
                         │
                    MyttyServiceProtocol
                    ├── session: create/list/get/close
                    ├── tab: create/list/get/close/rename
                    ├── pane: create/list/get/close/focus/resize/active
                    ├── pane: send-keys/run-command/get-text
                    └── window: create/list/get/close/focus
```

Three new components:

1. **MyttyShared** — shared Swift library with the XPC protocol, Codable response types, and constants
2. **XPC listener in Mytty.app** — implements the protocol, dispatches to SessionStore on @MainActor
3. **mytty-cli** — separate executable using Swift Argument Parser

## XPC Protocol

```swift
@objc protocol MyttyServiceProtocol {
    // Sessions
    func createSession(name: String, directory: String?, exec: String?, reply: @escaping (Data?, Error?) -> Void)
    func listSessions(reply: @escaping (Data?, Error?) -> Void)
    func getSession(id: String, reply: @escaping (Data?, Error?) -> Void)
    func closeSession(id: String, reply: @escaping (Data?, Error?) -> Void)

    // Tabs
    func createTab(sessionId: String, name: String?, exec: String?, reply: @escaping (Data?, Error?) -> Void)
    func listTabs(sessionId: String, reply: @escaping (Data?, Error?) -> Void)
    func getTab(id: String, reply: @escaping (Data?, Error?) -> Void)
    func closeTab(id: String, reply: @escaping (Data?, Error?) -> Void)
    func renameTab(id: String, name: String, reply: @escaping (Data?, Error?) -> Void)

    // Panes
    func createPane(tabId: String, direction: String?, reply: @escaping (Data?, Error?) -> Void)
    func listPanes(tabId: String, reply: @escaping (Data?, Error?) -> Void)
    func getPane(id: String, reply: @escaping (Data?, Error?) -> Void)
    func closePane(id: String, reply: @escaping (Data?, Error?) -> Void)
    func focusPane(id: String, reply: @escaping (Data?, Error?) -> Void)
    func resizePane(id: String, direction: String, amount: Int, reply: @escaping (Data?, Error?) -> Void)
    func activePane(reply: @escaping (Data?, Error?) -> Void)

    // paneId optional — nil targets the active/focused pane
    func sendKeys(paneId: String?, keys: String, reply: @escaping (Data?, Error?) -> Void)
    func runCommand(paneId: String?, command: String, reply: @escaping (Data?, Error?) -> Void)
    func getText(paneId: String?, reply: @escaping (Data?, Error?) -> Void)

    // Windows
    func createWindow(reply: @escaping (Data?, Error?) -> Void)
    func listWindows(reply: @escaping (Data?, Error?) -> Void)
    func getWindow(id: String, reply: @escaping (Data?, Error?) -> Void)
    func closeWindow(id: String, reply: @escaping (Data?, Error?) -> Void)
    func focusWindow(id: String, reply: @escaping (Data?, Error?) -> Void)
}
```

Replies use `Data?` (JSON-encoded Codable structs) because XPC's @objc protocol constraint limits parameter types. This keeps the protocol stable while response shapes can evolve.

## CLI Command Structure

Grammar: `mytty-cli <entity> <action> [flags]`

```
mytty-cli session create --name "project" --directory ~/code/proj --exec "nvim ."
mytty-cli session list
mytty-cli session get <id>
mytty-cli session close <id>

mytty-cli tab create --session <id> [--name "tests"] [--exec "npm test"]
mytty-cli tab list --session <id>
mytty-cli tab get <id>
mytty-cli tab close <id>
mytty-cli tab rename <id> --name "new name"

mytty-cli pane create --tab <id> [--direction horizontal|vertical]
mytty-cli pane list --tab <id>
mytty-cli pane get <id>
mytty-cli pane close <id>
mytty-cli pane focus <id>
mytty-cli pane resize <id> --direction left|right|up|down --amount 5
mytty-cli pane active
mytty-cli pane send-keys [--pane <id>] "ls -la"
mytty-cli pane run-command [--pane <id>] "npm test"
mytty-cli pane get-text [--pane <id>]

mytty-cli window create
mytty-cli window list
mytty-cli window get <id>
mytty-cli window close <id>
mytty-cli window focus <id>
```

### Output Format

Auto-detect via isatty:
- **Interactive terminal:** Human-readable tables
- **Piped/non-interactive:** JSON
- **Override:** `--json` forces JSON, `--human` forces table output
- **Errors:** Always to stderr. Exit code 0 on success, 1 on error.

### send-keys vs run-command

`send-keys` sends raw keystrokes (supports escape sequences like `\n`, `\t`, `C-c`). `run-command` appends a newline automatically — convenience for "type this and hit enter."

## Entity IDs

Atomic integers per entity type, starting at 1. Each type has its own counter on SessionStore:

```swift
private var nextSessionId = 1
private var nextTabId = 1
private var nextPaneId = 1
private var nextWindowId = 1
```

IDs are ephemeral — they reset when the app restarts. This is acceptable since sessions don't persist across restarts yet.

This replaces the current UUID-based IDs on MyttySession, MyttyTab, and MyttyPane.

## Project Structure

### New targets in Package.swift

```
Package
├── Mytty (existing app target)
│   └── depends on MyttyShared
├── MyttyShared (new library target)
│   ├── MyttyServiceProtocol.swift
│   ├── Models/
│   │   ├── SessionResponse.swift
│   │   ├── TabResponse.swift
│   │   ├── PaneResponse.swift
│   │   └── WindowResponse.swift
│   └── XPCConstants.swift
├── MyttyCLI (new executable target)
│   └── depends on MyttyShared
└── MyttyTests (existing, unchanged)
```

### App-side additions

- `Mytty/Services/XPCService.swift` — Implements MyttyServiceProtocol, dispatches to SessionStore on @MainActor
- `Mytty/Services/XPCListener.swift` — Starts NSXPCListener, handles connections

The listener starts in MyttyApp.swift on launch.

### CLI-side structure

```
MyttyCLI/
├── main.swift
├── Commands/
│   ├── SessionCommand.swift
│   ├── TabCommand.swift
│   ├── PaneCommand.swift
│   └── WindowCommand.swift
├── XPCClient.swift
└── OutputFormatter.swift
```

### New dependency

`swift-argument-parser` (CLI target only).

## XPC Implementation Details

### Service registration

Mach service name: `com.mytty.cli-service`

Using `NSXPCListener(machServiceName:)`. For a non-sandboxed app, register via a launchd plist at `~/Library/LaunchAgents/com.mytty.cli-service.plist`, installable on first run or via `mytty-cli install-service`.

### Thread safety

XPC callbacks arrive on arbitrary threads. The XPCService dispatches all SessionStore mutations onto @MainActor, then replies on the XPC connection's thread.

### Authentication

Accept all connections from the same user. No additional auth beyond macOS's built-in XPC user-level isolation.

### Auto-launch

1. CLI attempts XPC connection
2. On failure, launch Mytty.app via `open -a Mytty`
3. Retry with exponential backoff: 100ms, 200ms, 400ms, 800ms, 1600ms
4. After ~3s, fail with: "Could not connect to Mytty.app. Is it installed?"

### Error handling

Errors returned as NSError with domain `com.mytty.error` and codes: entityNotFound, invalidArgument, operationFailed. CLI maps these to human-readable messages.

## Out of Scope

- AppleScript/Shortcuts bridge (can layer on top of XPC later)
- Session persistence/attach (no tmux-like session persistence yet)
- Sandboxed XPC (not needed for non-sandboxed app)
