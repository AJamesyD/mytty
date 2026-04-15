import Darwin
import Foundation
import MisttyShared
import os

private struct ListenerState: Sendable {
  var serverFD: Int32 = -1
  var running = false
}

@MainActor
final class IPCListener {
  private let service: MisttyIPCService
  private let state = OSAllocatedUnfairLock(initialState: ListenerState())
  private let queue = DispatchQueue(label: "com.mistty.ipc-listener", qos: .userInitiated)
  let broker = EventBroker()

  init(service: MisttyIPCService) {
    self.service = service
  }

  func start() {
    let path = MisttyIPC.socketPath

    let dir = (path as NSString).deletingLastPathComponent
    try? FileManager.default.createDirectory(
      atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])

    unlink(path)

    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      print("Warning: failed to create IPC socket: \(String(cString: strerror(errno)))")
      return
    }

    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let pathBytes = path.utf8CString
    guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
      print("Warning: socket path too long")
      Darwin.close(fd)
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
        Darwin.bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bindResult == 0 else {
      print("Warning: failed to bind IPC socket: \(String(cString: strerror(errno)))")
      Darwin.close(fd)
      return
    }

    guard Darwin.listen(fd, 5) == 0 else {
      print("Warning: failed to listen on IPC socket: \(String(cString: strerror(errno)))")
      Darwin.close(fd)
      return
    }

    state.withLock { s in
      s.serverFD = fd
      s.running = true
    }

    let service = self.service
    let broker = self.broker
    queue.async { [state] in
      IPCListener.acceptLoop(state: state, service: service, broker: broker)
    }
  }

  func stop() {
    let fd = state.withLock { s -> Int32 in
      s.running = false
      let fd = s.serverFD
      s.serverFD = -1
      return fd
    }
    if fd >= 0 { Darwin.close(fd) }
    unlink(MisttyIPC.socketPath)
  }

  // MARK: - Accept Loop

  private nonisolated static func acceptLoop(
    state: OSAllocatedUnfairLock<ListenerState>, service: MisttyIPCService, broker: EventBroker
  ) {
    while true {
      let fd = state.withLock { $0.running ? $0.serverFD : -1 }
      guard fd >= 0 else { break }

      let clientFD = Darwin.accept(fd, nil, nil)
      guard clientFD >= 0 else {
        let stillRunning = state.withLock { $0.running }
        if !stillRunning { break }
        continue
      }

      var on: Int32 = 1
      setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

      var tv = timeval(tv_sec: 5, tv_usec: 0)
      setsockopt(clientFD, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
      setsockopt(clientFD, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

      Task {
        await handleConnection(clientFD, service: service, broker: broker)
      }
    }
  }

  // MARK: - Connection Handling

  private nonisolated static func handleConnection(
    _ fd: Int32, service: MisttyIPCService, broker: EventBroker
  ) async {
    defer { Darwin.close(fd) }

    var byte: UInt8 = 0
    let peeked = recv(fd, &byte, 1, MSG_PEEK)
    guard peeked == 1 else { return }

    if byte == 0x43 {
      await handleJSONRPCConnection(fd, service: service, broker: broker)
    } else {
      await handleLegacyConnection(fd, service: service)
    }
  }

  // MARK: - JSON-RPC Connection Handling

  private nonisolated static func handleJSONRPCConnection(
    _ fd: Int32, service: MisttyIPCService, broker: EventBroker
  ) async {
    defer { Task { await broker.removeSubscriptions(forFD: fd) } }
    let encoder = JSONEncoder()

    while true {
      guard let messageData = readContentLengthMessage(fd: fd) else { return }

      guard let request = try? JSONDecoder().decode(JSONRPCMessage.Request.self, from: messageData)
      else {
        let errResp = JSONRPCMessage.Response.error(
          id: 0, code: MisttyIPC.JSONRPCErrorCode.parseError, message: "Parse error")
        if let data = try? encoder.encode(errResp) {
          writeContentLengthMessage(fd: fd, data: data)
        }
        continue
      }

      let response: JSONRPCMessage.Response

      switch request.method {
      case "initialize":
        let result: JSONValue = [
          "serverVersion": .string(MisttyIPC.protocolVersion),
          "capabilities": ["events": true],
        ]
        response = .success(id: request.id, result: result)

      case "subscribe":
        let events: [String]
        if case .array(let arr) = request.params?["events"] {
          events = arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } }
        } else {
          events = []
        }
        let subId = await broker.subscribe(fd: fd, events: events)
        response = .success(id: request.id, result: ["subscriptionId": .string(subId)])

      case "unsubscribe":
        if case .string(let subId) = request.params?["subscriptionId"] {
          await broker.unsubscribe(id: subId)
        }
        response = .success(id: request.id, result: .null)

      default:
        response = await dispatchJSONRPCMethod(request, service: service)
      }

      guard let data = try? encoder.encode(response) else { return }
      writeContentLengthMessage(fd: fd, data: data)
    }
  }

  private nonisolated static func callService(
    _ request: JSONRPCMessage.Request,
    _ body: @Sendable () async throws -> Data
  ) async -> JSONRPCMessage.Response {
    do {
      let data = try await body()
      if let result = try? JSONDecoder().decode(JSONValue.self, from: data) {
        return .success(id: request.id, result: result)
      }
      return .success(id: request.id, result: .null)
    } catch let error as NSError {
      let rpcCode: Int
      switch MisttyIPC.ErrorCode(rawValue: error.code) {
      case .entityNotFound: rpcCode = MisttyIPC.JSONRPCErrorCode.entityNotFound
      case .invalidArgument: rpcCode = MisttyIPC.JSONRPCErrorCode.invalidArgument
      case .notSupported: rpcCode = MisttyIPC.JSONRPCErrorCode.notSupported
      default: rpcCode = MisttyIPC.JSONRPCErrorCode.operationFailed
      }
      return .error(id: request.id, code: rpcCode, message: error.localizedDescription)
    }
  }

  private nonisolated static func dispatchJSONRPCMethod(
    _ request: JSONRPCMessage.Request, service: MisttyIPCService
  ) async -> JSONRPCMessage.Response {
    let params = request.params ?? [:]

    let str: @Sendable (String) -> String? = { key in
      if case .string(let s) = params[key] { return s }
      return nil
    }
    let int: @Sendable (String) -> Int = { key in
      if case .int(let i) = params[key] { return i }
      return 0
    }
    let dbl: @Sendable (String) -> Double = { key in
      if case .double(let d) = params[key] { return d }
      if case .int(let i) = params[key] { return Double(i) }
      return 0
    }
    let boo: @Sendable (String) -> Bool = { key in
      if case .bool(let b) = params[key] { return b }
      return false
    }

    switch request.method {
    // Sessions
    case "session.create":
      return await callService(request) {
        try await service.createSession(
          name: str("name") ?? "Default", directory: str("directory"), exec: str("exec"))
      }
    case "session.list":
      return await callService(request) { try await service.listSessions() }
    case "session.get":
      return await callService(request) { try await service.getSession(id: int("id")) }
    case "session.close":
      return await callService(request) { try await service.closeSession(id: int("id")) }
    case "session.rename":
      return await callService(request) {
        try await service.renameSession(id: int("id"), name: str("name") ?? "")
      }

    // Tabs
    case "tab.create":
      return await callService(request) {
        try await service.createTab(
          sessionId: int("sessionId"), name: str("name"), exec: str("exec"))
      }
    case "tab.list":
      return await callService(request) {
        try await service.listTabs(sessionId: int("sessionId"))
      }
    case "tab.get":
      return await callService(request) { try await service.getTab(id: int("id")) }
    case "tab.close":
      return await callService(request) { try await service.closeTab(id: int("id")) }
    case "tab.rename":
      return await callService(request) {
        try await service.renameTab(id: int("id"), name: str("name") ?? "")
      }
    case "tab.move":
      return await callService(request) {
        try await service.moveTab(id: int("id"), toIndex: int("toIndex"))
      }

    // Panes
    case "pane.create":
      return await callService(request) {
        try await service.createPane(tabId: int("tabId"), direction: str("direction"))
      }
    case "pane.list":
      return await callService(request) {
        try await service.listPanes(tabId: int("tabId"))
      }
    case "pane.get":
      return await callService(request) { try await service.getPane(id: int("id")) }
    case "pane.close":
      return await callService(request) { try await service.closePane(id: int("id")) }
    case "pane.focus":
      return await callService(request) { try await service.focusPane(id: int("id")) }
    case "pane.focusByDirection":
      return await callService(request) {
        try await service.focusPaneByDirection(
          direction: str("direction") ?? "", sessionId: int("sessionId"))
      }
    case "pane.resize":
      return await callService(request) {
        try await service.resizePane(
          id: int("id"), direction: str("direction") ?? "", amount: int("amount"))
      }
    case "pane.active":
      return await callService(request) { try await service.activePane() }
    case "pane.sendKeys":
      return await callService(request) {
        try await service.sendKeys(paneId: int("paneId"), keys: str("keys") ?? "")
      }
    case "pane.runCommand":
      return await callService(request) {
        try await service.runCommand(paneId: int("paneId"), command: str("command") ?? "")
      }
    case "pane.getText":
      return await callService(request) {
        try await service.getText(paneId: int("paneId"))
      }

    // Windows
    case "window.create":
      return await callService(request) { try await service.createWindow() }
    case "window.list":
      return await callService(request) { try await service.listWindows() }
    case "window.get":
      return await callService(request) { try await service.getWindow(id: int("id")) }
    case "window.close":
      return await callService(request) { try await service.closeWindow(id: int("id")) }
    case "window.focus":
      return await callService(request) { try await service.focusWindow(id: int("id")) }

    // Popups
    case "popup.open":
      return await callService(request) {
        try await service.openPopup(
          sessionId: int("sessionId"), name: str("name") ?? "",
          exec: str("exec") ?? "", width: dbl("width"), height: dbl("height"),
          closeOnExit: boo("closeOnExit"))
      }
    case "popup.list":
      return await callService(request) {
        try await service.listPopups(sessionId: int("sessionId"))
      }
    case "popup.close":
      return await callService(request) {
        try await service.closePopup(popupId: int("popupId"))
      }
    case "popup.toggle":
      return await callService(request) {
        try await service.togglePopup(sessionId: int("sessionId"), name: str("name") ?? "")
      }

    default:
      return .error(
        id: request.id, code: MisttyIPC.JSONRPCErrorCode.methodNotFound,
        message: "Method not found: \(request.method)")
    }
  }

  private nonisolated static func handleLegacyConnection(
    _ fd: Int32, service: MisttyIPCService
  ) async {
    guard let lengthBytes = readExact(fd: fd, count: 4) else { return }
    let length = lengthBytes.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }

    guard length > 0, length <= MisttyIPC.maxMessageSize else { return }

    guard let requestData = readExact(fd: fd, count: Int(length)) else { return }

    guard let json = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any],
      let method = json["method"] as? String
    else {
      writeResponse(fd: fd, data: errorResponse("Invalid request format"))
      return
    }

    do {
      let data = try await dispatch(service: service, method: method, params: json)
      var result = Data([0x00])
      result.append(data)
      writeResponse(fd: fd, data: result)
    } catch {
      writeResponse(fd: fd, data: errorResponse(error.localizedDescription))
    }
  }

  private nonisolated static func errorResponse(_ message: String) -> Data {
    var result = Data([0x01])
    result.append(Data(message.utf8))
    return result
  }

  // MARK: - Socket I/O Helpers

  private nonisolated static func readExact(fd: Int32, count: Int) -> Data? {
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

  private nonisolated static func writeResponse(fd: Int32, data: Data) {
    var length = UInt32(data.count).bigEndian
    let lengthData = Data(bytes: &length, count: 4)
    writeAll(fd: fd, data: lengthData)
    writeAll(fd: fd, data: data)
  }

  private nonisolated static func writeAll(fd: Int32, data: Data) {
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

  // MARK: - Content-Length Framing

  private nonisolated static func readContentLengthMessage(fd: Int32) -> Data? {
    var headerBytes = Data()
    let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
    while headerBytes.count < 256 {
      guard let byte = readExact(fd: fd, count: 1) else { return nil }
      headerBytes.append(byte)
      if headerBytes.count >= 4, Data(headerBytes.suffix(4)) == separator {
        break
      }
    }
    guard headerBytes.count >= 4, Data(headerBytes.suffix(4)) == separator else { return nil }
    let headerStr = String(data: headerBytes.dropLast(4), encoding: .utf8) ?? ""
    guard headerStr.hasPrefix("Content-Length: "),
      let length = Int(headerStr.dropFirst("Content-Length: ".count)),
      length > 0, length <= MisttyIPC.maxMessageSize
    else { return nil }
    return readExact(fd: fd, count: length)
  }

  private nonisolated static func writeContentLengthMessage(fd: Int32, data: Data) {
    let header = "Content-Length: \(data.count)\r\n\r\n"
    writeAll(fd: fd, data: Data(header.utf8))
    writeAll(fd: fd, data: data)
  }

  // MARK: - Method Dispatch

  nonisolated static func dispatch(
    service: MisttyIPCService,
    method: String,
    params: [String: Any]
  ) async throws -> Data {
    func str(_ key: String) -> String? { params[key] as? String }
    func int(_ key: String) -> Int { params[key] as? Int ?? 0 }
    func dbl(_ key: String) -> Double { params[key] as? Double ?? 0 }
    func boo(_ key: String) -> Bool { params[key] as? Bool ?? false }

    switch method {
    // Sessions
    case "createSession":
      return try await service.createSession(
        name: str("name") ?? "Default", directory: str("directory"), exec: str("exec"))
    case "listSessions":
      return try await service.listSessions()
    case "getSession":
      return try await service.getSession(id: int("id"))
    case "closeSession":
      return try await service.closeSession(id: int("id"))
    case "renameSession":
      return try await service.renameSession(id: int("id"), name: str("name") ?? "")

    // Tabs
    case "createTab":
      return try await service.createTab(
        sessionId: int("sessionId"), name: str("name"), exec: str("exec"))
    case "listTabs":
      return try await service.listTabs(sessionId: int("sessionId"))
    case "getTab":
      return try await service.getTab(id: int("id"))
    case "closeTab":
      return try await service.closeTab(id: int("id"))
    case "renameTab":
      return try await service.renameTab(id: int("id"), name: str("name") ?? "")
    case "moveTab":
      return try await service.moveTab(id: int("id"), toIndex: int("toIndex"))

    // Panes
    case "createPane":
      return try await service.createPane(tabId: int("tabId"), direction: str("direction"))
    case "listPanes":
      return try await service.listPanes(tabId: int("tabId"))
    case "getPane":
      return try await service.getPane(id: int("id"))
    case "closePane":
      return try await service.closePane(id: int("id"))
    case "focusPane":
      return try await service.focusPane(id: int("id"))
    case "focusPaneByDirection":
      return try await service.focusPaneByDirection(
        direction: str("direction") ?? "", sessionId: int("sessionId"))
    case "resizePane":
      return try await service.resizePane(
        id: int("id"), direction: str("direction") ?? "", amount: int("amount"))
    case "sendKeys":
      return try await service.sendKeys(paneId: int("paneId"), keys: str("keys") ?? "")
    case "runCommand":
      return try await service.runCommand(paneId: int("paneId"), command: str("command") ?? "")
    case "getText":
      return try await service.getText(paneId: int("paneId"))
    case "activePane":
      return try await service.activePane()

    // Windows
    case "createWindow":
      return try await service.createWindow()
    case "listWindows":
      return try await service.listWindows()
    case "getWindow":
      return try await service.getWindow(id: int("id"))
    case "closeWindow":
      return try await service.closeWindow(id: int("id"))
    case "focusWindow":
      return try await service.focusWindow(id: int("id"))

    // Popups
    case "openPopup":
      return try await service.openPopup(
        sessionId: int("sessionId"), name: str("name") ?? "",
        exec: str("exec") ?? "", width: dbl("width"), height: dbl("height"),
        closeOnExit: boo("closeOnExit"))
    case "closePopup":
      return try await service.closePopup(popupId: int("popupId"))
    case "togglePopup":
      return try await service.togglePopup(sessionId: int("sessionId"), name: str("name") ?? "")
    case "listPopups":
      return try await service.listPopups(sessionId: int("sessionId"))

    default:
      throw MisttyIPC.error(.operationFailed, "Unknown method: \(method)")
    }
  }
}
