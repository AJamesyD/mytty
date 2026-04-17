# Unix Domain Socket IPC Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace CFMessagePort-based IPC between Mytty CLI and app with Unix domain sockets.

**Architecture:** Transport-layer swap. The service layer (`MyttyIPCService`), dispatch routing, wire format (status byte + JSON), and CLI command interface all remain the same. Only the underlying transport changes from CFMessagePort/Mach ports to Unix domain sockets with length-prefixed framing. All XPC naming is cleaned up to IPC.

**Tech Stack:** Swift 6, Foundation (POSIX sockets via Darwin module), Swift Package Manager

**Spec:** `docs/superpowers/specs/2026-03-18-xpc-to-unix-socket-ipc-design.md`

---

## Chunk 1: Renames and Protocol Cleanup

### Task 1: Rename XPCConstants to IPCConstants

**Files:**
- Rename: `MyttyShared/XPCConstants.swift` → `MyttyShared/IPCConstants.swift`

- [ ] **Step 1: Rename the file**

```bash
git mv MyttyShared/XPCConstants.swift MyttyShared/IPCConstants.swift
```

- [ ] **Step 2: Rename the enum and update strings**

In `MyttyShared/IPCConstants.swift`, replace:
- `MyttyXPC` → `MyttyIPC`
- `"com.mytty.cli-service"` → keep as-is (this is just a logical name now, not a Mach service)
- `"com.mytty.error"` → keep as-is

```swift
import Foundation

public enum MyttyIPC {
    public static let serviceName = "com.mytty.cli-service"
    public static let errorDomain = "com.mytty.error"

    public enum ErrorCode: Int {
        case entityNotFound = 1
        case invalidArgument = 2
        case operationFailed = 3
    }

    public static func error(_ code: ErrorCode, _ message: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
```

- [ ] **Step 3: Add socket path constant**

Add to the `MyttyIPC` enum:

```swift
public static var socketPath: String {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
    return appSupport.appendingPathComponent("Mytty/mytty.sock").path
}

public static let maxMessageSize: UInt32 = 16 * 1024 * 1024  // 16 MB
```

- [ ] **Step 4: Update all references from MyttyXPC to MyttyIPC**

Files that reference `MyttyXPC`:
- `Mytty/Services/IPCListener.swift` (lines 71, 183)
- `Mytty/Services/XPCService.swift` (throughout — ~20 references)
- `MyttyCLI/XPCClient.swift` (line 45)
- `MyttyTests/Services/XPCServiceTests.swift` (lines 98, 99, 125, 254, 271, 281, 305, 377)

Use find-and-replace: `MyttyXPC` → `MyttyIPC` in all files.

- [ ] **Step 5: Build to verify**

```bash
swift build 2>&1 | head -20
```

Expected: builds successfully.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor: rename MyttyXPC to MyttyIPC, move to IPCConstants.swift"
```

---

### Task 2: Remove @objc from MyttyServiceProtocol

**Files:**
- Modify: `MyttyShared/MyttyServiceProtocol.swift:3`

- [ ] **Step 1: Remove @objc attribute**

Change line 3 from:
```swift
@objc public protocol MyttyServiceProtocol {
```
to:
```swift
public protocol MyttyServiceProtocol {
```

- [ ] **Step 2: Remove NSObject conformance from service class**

In `Mytty/Services/XPCService.swift` (will be `IPCService.swift` after Task 3), change:
```swift
final class MyttyXPCService: NSObject, MyttyServiceProtocol, @unchecked Sendable {
```
to:
```swift
final class MyttyXPCService: MyttyServiceProtocol, @unchecked Sendable {
```

And remove the `super.init()` call from `init(store:)`.

- [ ] **Step 3: Build to verify**

```bash
swift build 2>&1 | head -20
```

- [ ] **Step 4: Commit**

```bash
git add MyttyShared/MyttyServiceProtocol.swift Mytty/Services/XPCService.swift
git commit -m "refactor: remove @objc and NSObject from service protocol"
```

---

### Task 3: Rename XPCService to IPCService

**Files:**
- Rename: `Mytty/Services/XPCService.swift` → `Mytty/Services/IPCService.swift`
- Rename: `MyttyTests/Services/XPCServiceTests.swift` → `MyttyTests/Services/IPCServiceTests.swift`
- Modify: `Mytty/App/MyttyApp.swift:34`

- [ ] **Step 1: Rename files**

```bash
git mv Mytty/Services/XPCService.swift Mytty/Services/IPCService.swift
git mv MyttyTests/Services/XPCServiceTests.swift MyttyTests/Services/IPCServiceTests.swift
```

- [ ] **Step 2: Rename class in IPCService.swift**

Replace `MyttyXPCService` → `MyttyIPCService` throughout `Mytty/Services/IPCService.swift`.

Also update the `Reply` doc comment from "XPC reply closure" to "reply closure".

- [ ] **Step 3: Update IPCListener.swift reference**

In `Mytty/Services/IPCListener.swift`, replace all `MyttyXPCService` with `MyttyIPCService`. Note: this file will be fully rewritten in Task 5, so this step can be skipped if you prefer — the rewrite already uses `MyttyIPCService`.

- [ ] **Step 4: Update MyttyApp.swift reference**

In `Mytty/App/MyttyApp.swift:34`, change:
```swift
let service = MyttyXPCService(store: store)
```
to:
```swift
let service = MyttyIPCService(store: store)
```

- [ ] **Step 5: Update test file references**

In `MyttyTests/Services/IPCServiceTests.swift`:
- Rename class: `XPCServiceTests` → `IPCServiceTests`
- Replace `MyttyXPCService` → `MyttyIPCService` (lines 9, 14)

- [ ] **Step 6: Build and run tests**

```bash
swift build 2>&1 | head -20
swift test 2>&1 | tail -20
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor: rename XPCService to IPCService throughout"
```

---

### Task 4: Remove legacy launchd cleanup from MyttyApp

**Files:**
- Modify: `Mytty/App/MyttyApp.swift`

- [ ] **Step 1: Remove cleanup call and method**

In `MyttyApp.swift`:
- Remove the `cleanupLegacyLaunchdPlist()` call from `init()` (line 13)
- Remove the entire `cleanupLegacyLaunchdPlist()` method (lines 17-27)

The `init()` becomes:
```swift
init() {
    _ = GhosttyAppManager.shared
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | head -20
```

- [ ] **Step 3: Commit**

```bash
git add Mytty/App/MyttyApp.swift
git commit -m "refactor: remove legacy launchd plist cleanup"
```

---

## Chunk 2: Transport Layer Rewrite

### Task 5: Rewrite IPCListener to use Unix domain sockets

**Files:**
- Rewrite: `Mytty/Services/IPCListener.swift`

This is the server side. The app listens on a Unix domain socket. Each client connection is one request/response.

- [ ] **Step 1: Write the new IPCListener**

Replace the entire contents of `Mytty/Services/IPCListener.swift` with:

```swift
import Darwin
import Foundation
import MyttyShared

/// Unix domain socket IPC listener. The app binds to a socket and accepts
/// one-shot connections from the CLI: read request, dispatch, write response, close.
@MainActor
final class IPCListener {
    nonisolated(unsafe) private let service: MyttyIPCService
    nonisolated(unsafe) private var serverFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private let queue = DispatchQueue(label: "com.mytty.ipc-listener", qos: .userInitiated)

    init(service: MyttyIPCService) {
        self.service = service
    }

    func start() {
        let path = MyttyIPC.socketPath

        // Ensure parent directory exists with 0700 permissions
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

        // Unconditionally unlink any stale socket
        unlink(path)

        // Create socket
        serverFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFD >= 0 else {
            print("Warning: failed to create IPC socket: \(String(cString: strerror(errno)))")
            return
        }

        // Bind
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            print("Warning: socket path too long")
            close(serverFD); serverFD = -1
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.bind(serverFD, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            print("Warning: failed to bind IPC socket: \(String(cString: strerror(errno)))")
            close(serverFD); serverFD = -1
            return
        }

        // Listen
        guard Darwin.listen(serverFD, 5) == 0 else {
            print("Warning: failed to listen on IPC socket: \(String(cString: strerror(errno)))")
            close(serverFD); serverFD = -1
            return
        }

        // Accept connections using GCD
        let source = DispatchSource.makeReadSource(fileDescriptor: serverFD, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptConnection()
        }
        source.setCancelHandler { [serverFD] in
            close(serverFD)
        }
        source.resume()
        acceptSource = source
    }

    func stop() {
        acceptSource?.cancel()
        acceptSource = nil
        serverFD = -1
        unlink(MyttyIPC.socketPath)
    }

    // MARK: - Connection Handling

    private nonisolated func acceptConnection() {
        let clientFD = Darwin.accept(serverFD, nil, nil)
        guard clientFD >= 0 else { return }

        // Set SO_NOSIGPIPE to avoid SIGPIPE on write to closed socket
        var on: Int32 = 1
        setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // Set read/write timeout (5 seconds)
        var tv = timeval(tv_sec: 5, tv_usec: 0)
        setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        queue.async {
            self.handleConnection(clientFD)
        }
    }

    private nonisolated func handleConnection(_ fd: Int32) {
        defer { close(fd) }

        // Read length prefix (4 bytes, big-endian UInt32)
        guard let lengthBytes = readExact(fd: fd, count: 4) else { return }
        let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        guard length > 0, length <= MyttyIPC.maxMessageSize else { return }

        // Read request payload
        guard let requestData = readExact(fd: fd, count: Int(length)) else { return }

        // Parse request
        guard let json = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
              let method = json["method"] as? String
        else {
            writeResponse(fd: fd, data: errorResponse("Invalid request format"))
            return
        }

        // Dispatch to service (synchronous via semaphore — service methods are @MainActor)
        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: String?

        let reply: (Data?, Error?) -> Void = { data, error in
            responseData = data
            responseError = error?.localizedDescription
            semaphore.signal()
        }

        IPCListener.dispatch(service: service, method: method, params: json, reply: reply)
        semaphore.wait()

        if let errorMsg = responseError {
            writeResponse(fd: fd, data: errorResponse(errorMsg))
        } else {
            var result = Data([0x00])
            if let d = responseData { result.append(d) }
            writeResponse(fd: fd, data: result)
        }
    }

    private nonisolated func errorResponse(_ message: String) -> Data {
        var result = Data([0x01])
        result.append(Data(message.utf8))
        return result
    }

    // MARK: - Socket I/O Helpers

    /// Read exactly `count` bytes, looping for short reads and EINTR. Returns nil on error/timeout.
    private nonisolated func readExact(fd: Int32, count: Int) -> Data? {
        var buffer = Data(count: count)
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { ptr in
                Darwin.read(fd, ptr.baseAddress! + offset, count - offset)
            }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return nil }
            offset += n
        }
        return buffer
    }

    /// Write response with length prefix, looping for short writes.
    private nonisolated func writeResponse(fd: Int32, data: Data) {
        // Write length prefix
        var length = UInt32(data.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)
        writeAll(fd: fd, data: lengthData)
        // Write payload
        writeAll(fd: fd, data: data)
    }

    private nonisolated func writeAll(fd: Int32, data: Data) {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { ptr in
                Darwin.write(fd, ptr.baseAddress! + offset, data.count - offset)
            }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return }
            offset += n
        }
    }

    // MARK: - Method Dispatch

    nonisolated static func dispatch(
        service: MyttyIPCService,
        method: String,
        params: [String: Any],
        reply: @escaping (Data?, Error?) -> Void
    ) {
        func str(_ key: String) -> String? { params[key] as? String }
        func int(_ key: String) -> Int { params[key] as? Int ?? 0 }
        func dbl(_ key: String) -> Double { params[key] as? Double ?? 0 }
        func boo(_ key: String) -> Bool { params[key] as? Bool ?? false }

        switch method {
        // Sessions
        case "createSession":
            service.createSession(name: str("name") ?? "Default", directory: str("directory"), exec: str("exec"), reply: reply)
        case "listSessions":
            service.listSessions(reply: reply)
        case "getSession":
            service.getSession(id: int("id"), reply: reply)
        case "closeSession":
            service.closeSession(id: int("id"), reply: reply)

        // Tabs
        case "createTab":
            service.createTab(sessionId: int("sessionId"), name: str("name"), exec: str("exec"), reply: reply)
        case "listTabs":
            service.listTabs(sessionId: int("sessionId"), reply: reply)
        case "getTab":
            service.getTab(id: int("id"), reply: reply)
        case "closeTab":
            service.closeTab(id: int("id"), reply: reply)
        case "renameTab":
            service.renameTab(id: int("id"), name: str("name") ?? "", reply: reply)

        // Panes
        case "createPane":
            service.createPane(tabId: int("tabId"), direction: str("direction"), reply: reply)
        case "listPanes":
            service.listPanes(tabId: int("tabId"), reply: reply)
        case "getPane":
            service.getPane(id: int("id"), reply: reply)
        case "closePane":
            service.closePane(id: int("id"), reply: reply)
        case "focusPane":
            service.focusPane(id: int("id"), reply: reply)
        case "focusPaneByDirection":
            service.focusPaneByDirection(direction: str("direction") ?? "", sessionId: int("sessionId"), reply: reply)
        case "resizePane":
            service.resizePane(id: int("id"), direction: str("direction") ?? "", amount: int("amount"), reply: reply)
        case "sendKeys":
            service.sendKeys(paneId: int("paneId"), keys: str("keys") ?? "", reply: reply)
        case "runCommand":
            service.runCommand(paneId: int("paneId"), command: str("command") ?? "", reply: reply)
        case "getText":
            service.getText(paneId: int("paneId"), reply: reply)
        case "activePane":
            service.activePane(reply: reply)

        // Windows
        case "createWindow":
            service.createWindow(reply: reply)
        case "listWindows":
            service.listWindows(reply: reply)
        case "getWindow":
            service.getWindow(id: int("id"), reply: reply)
        case "closeWindow":
            service.closeWindow(id: int("id"), reply: reply)
        case "focusWindow":
            service.focusWindow(id: int("id"), reply: reply)

        // Popups
        case "openPopup":
            service.openPopup(
                sessionId: int("sessionId"), name: str("name") ?? "",
                exec: str("exec") ?? "", width: dbl("width"), height: dbl("height"),
                closeOnExit: boo("closeOnExit"), reply: reply)
        case "closePopup":
            service.closePopup(popupId: int("popupId"), reply: reply)
        case "togglePopup":
            service.togglePopup(sessionId: int("sessionId"), name: str("name") ?? "", reply: reply)
        case "listPopups":
            service.listPopups(sessionId: int("sessionId"), reply: reply)

        default:
            reply(nil, MyttyIPC.error(.operationFailed, "Unknown method: \(method)"))
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | head -20
```

- [ ] **Step 3: Commit**

```bash
git add Mytty/Services/IPCListener.swift
git commit -m "feat: rewrite IPCListener from CFMessagePort to Unix domain socket"
```

---

### Task 6: Rewrite IPCClient to use Unix domain sockets

**Files:**
- Rewrite: `MyttyCLI/XPCClient.swift`

- [ ] **Step 1: Write the new IPCClient**

Replace the entire contents of `MyttyCLI/XPCClient.swift` with:

```swift
import Darwin
import Foundation
import MyttyShared

enum IPCClientError: Error, CustomStringConvertible {
    case connectionFailed(String)
    case remoteError(String)

    var description: String {
        switch self {
        case .connectionFailed(let message): return message
        case .remoteError(let message): return message
        }
    }
}

/// CLI-side IPC client using Unix domain sockets to communicate with the Mytty app.
final class IPCClient {
    private var socketFD: Int32 = -1

    /// Connect to the running Mytty app, launching it if needed.
    func connect() throws {
        if tryConnect() { return }

        // Launch the app
        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launchProcess.arguments = ["-a", "Mytty"]
        try? launchProcess.run()
        launchProcess.waitUntilExit()

        // Retry with exponential backoff
        let delays: [UInt32] = [100_000, 200_000, 400_000, 800_000, 1_600_000]
        for delay in delays {
            usleep(delay)
            if tryConnect() { return }
        }

        throw IPCClientError.connectionFailed(
            "Could not connect to Mytty.app. Is it running?"
        )
    }

    private func tryConnect() -> Bool {
        let path = MyttyIPC.socketPath

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        // Set SO_NOSIGPIPE
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result != 0 {
            close(fd)
            return false
        }

        socketFD = fd
        return true
    }

    /// Send an IPC request and return the response data.
    func call(_ method: String, _ params: [String: Any] = [:]) throws -> Data {
        guard socketFD >= 0 else {
            throw IPCClientError.connectionFailed("Not connected")
        }

        // Build request
        var request = params
        request["method"] = method
        let requestData = try JSONSerialization.data(withJSONObject: request)

        // Write length-prefixed request
        var length = UInt32(requestData.count).bigEndian
        let lengthData = Data(bytes: &length, count: 4)
        try writeAll(data: lengthData)
        try writeAll(data: requestData)

        // Read length-prefixed response
        let responseLengthData = try readExact(count: 4)
        let responseLength = responseLengthData.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

        guard responseLength > 0, responseLength <= MyttyIPC.maxMessageSize else {
            throw IPCClientError.connectionFailed("Invalid response length")
        }

        let responseData = try readExact(count: Int(responseLength))

        guard !responseData.isEmpty else {
            throw IPCClientError.connectionFailed("Empty response")
        }

        let statusByte = responseData[0]
        let payload = responseData.dropFirst()

        if statusByte == 0x01 {
            let message = String(data: Data(payload), encoding: .utf8) ?? "Unknown error"
            throw IPCClientError.remoteError(message)
        }

        return Data(payload)
    }

    deinit {
        if socketFD >= 0 { close(socketFD) }
    }

    // MARK: - Socket I/O Helpers

    private func readExact(count: Int) throws -> Data {
        var buffer = Data(count: count)
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { ptr in
                Darwin.read(socketFD, ptr.baseAddress! + offset, count - offset)
            }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 {
                throw IPCClientError.connectionFailed("Read failed")
            }
            offset += n
        }
        return buffer
    }

    private func writeAll(data: Data) throws {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { ptr in
                Darwin.write(socketFD, ptr.baseAddress! + offset, data.count - offset)
            }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 {
                throw IPCClientError.connectionFailed("Write failed")
            }
            offset += n
        }
    }
}
```

- [ ] **Step 2: Build to verify**

```bash
swift build 2>&1 | head -20
```

- [ ] **Step 3: Commit**

```bash
git add MyttyCLI/XPCClient.swift
git commit -m "feat: rewrite IPCClient from CFMessagePort to Unix domain socket"
```

---

**Note:** The CLI command files (`MyttyCLI/Commands/*.swift`) already use the `IPCClient` class and `client.call()` pattern in the working tree. No changes needed for those files.

## Chunk 3: Verify and Clean Up

### Task 7: Run full build and tests

- [ ] **Step 1: Clean build**

```bash
swift build 2>&1 | tail -10
```

- [ ] **Step 2: Run tests**

```bash
swift test 2>&1 | tail -30
```

- [ ] **Step 3: Fix any issues found**

If tests fail due to remaining `MyttyXPC` references, update them to `MyttyIPC`.

- [ ] **Step 4: Commit any fixes**

```bash
git add -A
git commit -m "fix: resolve remaining XPC references from rename"
```

---

### Task 8: Manual smoke test

- [ ] **Step 1: Build release**

```bash
swift build -c release 2>&1 | tail -5
```

- [ ] **Step 2: Run the app and test CLI**

Launch the app, then from a terminal:

```bash
.build/release/MyttyCLI session list
.build/release/MyttyCLI session create --name test
.build/release/MyttyCLI session list
.build/release/MyttyCLI tab list --session-id 1
```

Verify: CLI connects, commands return JSON, no crashes.

- [ ] **Step 3: Verify socket file exists**

```bash
ls -la ~/Library/Application\ Support/Mytty/mytty.sock
```

- [ ] **Step 4: Verify auto-launch works**

Quit the app, then run a CLI command — it should launch the app automatically.
