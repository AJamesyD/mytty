import AppKit
import Foundation
import GhosttyKit
import MyttyShared

// One method per IPC endpoint. Size grows linearly with the API surface.
// swiftlint:disable:next type_body_length
@MainActor final class MyttyIPCService: MyttyServiceProtocol {
  private let store: SessionStore
  let broker = EventBroker()

  init(store: SessionStore) {
    self.store = store
  }

  // MARK: - Helpers

  private func encode<T: Encodable>(_ value: T) -> Data? {
    try? JSONEncoder().encode(value)
  }

  @MainActor private func sessionResponse(_ session: MyttySession) -> SessionResponse {
    SessionResponse(
      id: session.id,
      name: session.name,
      directory: session.directory.path,
      tabCount: session.tabs.count,
      tabIds: session.tabs.map(\.id)
    )
  }

  @MainActor private func tabResponse(_ tab: MyttyTab) -> TabResponse {
    TabResponse(
      id: tab.id,
      title: tab.displayTitle,
      paneCount: tab.panes.count,
      paneIds: tab.panes.map(\.id)
    )
  }

  @MainActor private func paneResponse(_ pane: MyttyPane, tab: MyttyTab? = nil) -> PaneResponse {
    PaneResponse(
      id: pane.id,
      directory: pane.directory?.path,
      zoomed: tab?.zoomedPane?.id == pane.id,
      title: pane.processTitle
    )
  }

  @MainActor private func popupResponse(_ popup: PopupState) -> PopupResponse {
    PopupResponse(
      id: popup.id,
      name: popup.definition.name,
      command: popup.definition.command,
      isVisible: popup.isVisible,
      paneId: popup.pane.id
    )
  }

  private func encodeOrThrow<T: Encodable>(_ value: T) throws -> Data {
    guard let data = encode(value) else {
      throw MyttyIPC.error(.operationFailed, "Encoding failed")
    }
    return data
  }

  // MARK: - Sessions

  func createSession(name: String, directory: String?, exec: String?) async throws -> Data {
    let dir = URL(
      fileURLWithPath: directory ?? FileManager.default.homeDirectoryForCurrentUser.path)
    let session = store.createSession(name: name, directory: dir, exec: exec)
    Task {
      await broker.publish(
        event: "session.created",
        params: ["sessionId": .int(session.id), "name": .string(session.name)])
    }
    return try encodeOrThrow(sessionResponse(session))
  }

  func listSessions() async throws -> Data {
    let responses = store.sessions.map { sessionResponse($0) }
    return try encodeOrThrow(responses)
  }

  func getSession(id: Int) async throws -> Data {
    guard let session = store.session(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(id) not found")
    }
    return try encodeOrThrow(sessionResponse(session))
  }

  func closeSession(id: Int) async throws -> Data {
    guard let session = store.session(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(id) not found")
    }
    store.closeSession(session)
    Task { await broker.publish(event: "session.closed", params: ["sessionId": .int(id)]) }
    return try encodeOrThrow([String: String]())
  }

  func renameSession(id: Int, name: String) async throws -> Data {
    guard let session = store.session(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(id) not found")
    }
    session.name = name
    Task {
      await broker.publish(
        event: "session.renamed", params: ["sessionId": .int(id), "name": .string(name)])
    }
    return try encodeOrThrow(sessionResponse(session))
  }

  // MARK: - Tabs

  func createTab(sessionId: Int, name: String?, exec: String?) async throws -> Data {
    guard let session = store.session(byId: sessionId) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(sessionId) not found")
    }
    session.addTab(exec: exec)
    guard let tab = session.tabs.last else {
      throw MyttyIPC.error(.operationFailed, "Failed to create tab")
    }
    if let name { tab.customTitle = name }
    Task {
      await broker.publish(
        event: "tab.created", params: ["tabId": .int(tab.id), "sessionId": .int(sessionId)])
    }
    return try encodeOrThrow(tabResponse(tab))
  }

  func listTabs(sessionId: Int) async throws -> Data {
    guard let session = store.session(byId: sessionId) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(sessionId) not found")
    }
    let responses = session.tabs.map { tabResponse($0) }
    return try encodeOrThrow(responses)
  }

  func getTab(id: Int) async throws -> Data {
    guard let (_, tab) = store.tab(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Tab \(id) not found")
    }
    return try encodeOrThrow(tabResponse(tab))
  }

  func closeTab(id: Int) async throws -> Data {
    guard let (session, tab) = store.tab(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Tab \(id) not found")
    }
    session.closeTab(tab)
    Task { await broker.publish(event: "tab.closed", params: ["tabId": .int(id)]) }
    return try encodeOrThrow([String: String]())
  }

  func renameTab(id: Int, name: String) async throws -> Data {
    guard let (_, tab) = store.tab(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Tab \(id) not found")
    }
    tab.customTitle = name
    Task {
      await broker.publish(
        event: "tab.renamed", params: ["tabId": .int(id), "name": .string(name)])
    }
    return try encodeOrThrow(tabResponse(tab))
  }

  func moveTab(id: Int, toIndex: Int) async throws -> Data {
    guard let (session, tab) = store.tab(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Tab \(id) not found")
    }
    session.moveTab(withID: id, toIndex: toIndex)
    return try encodeOrThrow(tabResponse(tab))
  }

  // MARK: - Panes

  func createPane(tabId: Int, direction: String?) async throws -> Data {
    guard let (_, tab) = store.tab(byId: tabId) else {
      throw MyttyIPC.error(.entityNotFound, "Tab \(tabId) not found")
    }
    let splitDir: SplitDirection = direction == "horizontal" ? .horizontal : .vertical
    tab.splitActivePane(direction: splitDir)
    guard let newPane = tab.panes.last else {
      throw MyttyIPC.error(.operationFailed, "Failed to create pane")
    }
    Task {
      await broker.publish(
        event: "pane.created", params: ["paneId": .int(newPane.id), "tabId": .int(tabId)])
    }
    return try encodeOrThrow(paneResponse(newPane, tab: tab))
  }

  func listPanes(tabId: Int) async throws -> Data {
    guard let (_, tab) = store.tab(byId: tabId) else {
      throw MyttyIPC.error(.entityNotFound, "Tab \(tabId) not found")
    }
    let responses = tab.panes.map { paneResponse($0, tab: tab) }
    return try encodeOrThrow(responses)
  }

  func getPane(id: Int) async throws -> Data {
    guard let (_, tab, pane) = store.pane(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Pane \(id) not found")
    }
    return try encodeOrThrow(paneResponse(pane, tab: tab))
  }

  func closePane(id: Int) async throws -> Data {
    guard let (_, tab, pane) = store.pane(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Pane \(id) not found")
    }
    tab.closePane(pane)
    Task { await broker.publish(event: "pane.closed", params: ["paneId": .int(id)]) }
    return try encodeOrThrow([String: String]())
  }

  func focusPane(id: Int) async throws -> Data {
    guard let (session, tab, pane) = store.pane(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Pane \(id) not found")
    }
    store.activeSession = session
    session.activeTab = tab
    tab.activePane = pane
    pane.surfaceView.window?.makeFirstResponder(pane.surfaceView)
    Task { await broker.publish(event: "pane.focused", params: ["paneId": .int(id)]) }
    return try encodeOrThrow(paneResponse(pane, tab: tab))
  }

  func focusPaneByDirection(direction: String, sessionId: Int) async throws -> Data {
    let session: MyttySession?
    if sessionId == 0 {
      session = store.activeSession
    } else {
      session = store.session(byId: sessionId)
    }
    guard let session else {
      throw MyttyIPC.error(.entityNotFound, "Session not found")
    }
    guard let tab = session.activeTab,
      let pane = tab.activePane
    else {
      throw MyttyIPC.error(.entityNotFound, "No active pane")
    }

    let navDirection: NavigationDirection
    switch direction {
    case "left": navDirection = .left
    case "right": navDirection = .right
    case "up": navDirection = .up
    case "down": navDirection = .down
    default:
      throw MyttyIPC.error(
        .invalidArgument, "Invalid direction: \(direction). Use left, right, up, or down")
    }

    guard let target = tab.layout.adjacentPane(from: pane, direction: navDirection) else {
      throw MyttyIPC.error(.operationFailed, "No pane in direction \(direction)")
    }

    tab.activePane = target
    target.surfaceView.window?.makeFirstResponder(target.surfaceView)
    Task { await broker.publish(event: "pane.focused", params: ["paneId": .int(target.id)]) }
    return try encodeOrThrow(paneResponse(target, tab: tab))
  }

  func resizePane(id: Int, direction: String, amount: Int) async throws -> Data {
    guard let (_, tab, pane) = store.pane(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Pane \(id) not found")
    }
    let delta = CGFloat(amount) / 100.0
    let splitDir: SplitDirection?
    let sign: CGFloat
    switch direction {
    case "left":
      splitDir = .horizontal
      sign = -1.0
    case "right":
      splitDir = .horizontal
      sign = 1.0
    case "up":
      splitDir = .vertical
      sign = -1.0
    case "down":
      splitDir = .vertical
      sign = 1.0
    default:
      throw MyttyIPC.error(
        .invalidArgument, "Invalid direction: \(direction). Use left, right, up, or down")
    }
    tab.layout.resizeSplit(containing: pane, delta: delta * sign, along: splitDir)
    return Data("{}".utf8)
  }

  func activePane() async throws -> Data {
    guard let (_, tab, pane) = store.activePaneInfo() else {
      throw MyttyIPC.error(.entityNotFound, "No active pane")
    }
    return try encodeOrThrow(paneResponse(pane, tab: tab))
  }

  func sendKeys(paneId: Int, keys: String) async throws -> Data {
    let targetPane: MyttyPane?
    if paneId == 0 {
      targetPane = store.activePaneInfo()?.pane
    } else {
      targetPane = store.pane(byId: paneId)?.pane
    }
    guard let pane = targetPane else {
      throw MyttyIPC.error(.entityNotFound, "Pane \(paneId) not found")
    }
    let view = pane.surfaceView
    guard let surface = view.surface else {
      throw MyttyIPC.error(.operationFailed, "Pane has no active surface")
    }
    keys.withCString { ptr in
      ghostty_surface_text(surface, ptr, UInt(keys.utf8.count))
    }
    return try encodeOrThrow([String: String]())
  }

  func runCommand(paneId: Int, command: String) async throws -> Data {
    try await sendKeys(paneId: paneId, keys: command + "\n")
  }

  func getText(paneId: Int) async throws -> Data {
    let targetPane: MyttyPane?
    if paneId == 0 {
      targetPane = store.activePaneInfo()?.pane
    } else {
      targetPane = store.pane(byId: paneId)?.pane
    }
    guard let pane = targetPane else {
      throw MyttyIPC.error(.entityNotFound, "Pane \(paneId) not found")
    }
    guard let surface = pane.surfaceView.surface else {
      throw MyttyIPC.error(.operationFailed, "Pane has no active surface")
    }

    let size = ghostty_surface_size(surface)
    let rows = Int(size.rows)
    let cols = Int(size.columns)

    var sel = ghostty_selection_s()
    sel.top_left.tag = GHOSTTY_POINT_VIEWPORT
    sel.top_left.coord = GHOSTTY_POINT_COORD_EXACT
    sel.top_left.x = 0
    sel.top_left.y = 0
    sel.bottom_right.tag = GHOSTTY_POINT_VIEWPORT
    sel.bottom_right.coord = GHOSTTY_POINT_COORD_EXACT
    sel.bottom_right.x = UInt32(cols - 1)
    sel.bottom_right.y = UInt32(rows - 1)
    sel.rectangle = false

    var text = ghostty_text_s()
    guard ghostty_surface_read_text(surface, sel, &text) else {
      throw MyttyIPC.error(.operationFailed, "Failed to read text from surface")
    }
    defer { ghostty_surface_free_text(surface, &text) }

    let content: String
    if let ptr = text.text {
      content = String(cString: ptr)
    } else {
      content = ""
    }

    return try encodeOrThrow(["text": content])
  }

  func paneAtEdge(direction: String, sessionId: Int) async throws -> Data {
    let session: MyttySession?
    if sessionId == 0 {
      session = store.activeSession
    } else {
      session = store.session(byId: sessionId)
    }
    guard let session else {
      throw MyttyIPC.error(.entityNotFound, "Session not found")
    }
    guard let tab = session.activeTab, let pane = tab.activePane else {
      throw MyttyIPC.error(.entityNotFound, "No active pane")
    }
    let navDirection: NavigationDirection
    switch direction {
    case "left": navDirection = .left
    case "right": navDirection = .right
    case "up": navDirection = .up
    case "down": navDirection = .down
    default:
      throw MyttyIPC.error(
        .invalidArgument, "Invalid direction: \(direction). Use left, right, up, or down")
    }
    let atEdge = tab.layout.adjacentPane(from: pane, direction: navDirection) == nil
    return try encodeOrThrow(["atEdge": atEdge])
  }

  func paneSetVar(paneId: Int, key: String, value: String?) async throws -> Data {
    let pane: MyttyPane
    if paneId == 0 {
      guard let active = store.activePaneInfo()?.pane else {
        throw MyttyIPC.error(.entityNotFound, "No active pane")
      }
      pane = active
    } else {
      guard let (_, _, found) = store.pane(byId: paneId) else {
        throw MyttyIPC.error(.entityNotFound, "Pane \(paneId) not found")
      }
      pane = found
    }
    if let value {
      pane.vars[key] = value
    } else {
      pane.vars.removeValue(forKey: key)
    }
    return try encodeOrThrow([String: String]())
  }

  func paneGetVar(paneId: Int, key: String) async throws -> Data {
    let pane: MyttyPane
    if paneId == 0 {
      guard let active = store.activePaneInfo()?.pane else {
        throw MyttyIPC.error(.entityNotFound, "No active pane")
      }
      pane = active
    } else {
      guard let (_, _, found) = store.pane(byId: paneId) else {
        throw MyttyIPC.error(.entityNotFound, "Pane \(paneId) not found")
      }
      pane = found
    }
    if let value = pane.vars[key] {
      return try encodeOrThrow(["value": value])
    }
    return try encodeOrThrow(["value": nil as String?])
  }

  // MARK: - Windows

  func listWindows() async throws -> Data {
    let responses = store.trackedWindows.map { tracked in
      WindowResponse(id: tracked.id, sessionCount: store.sessions.count)
    }
    return try encodeOrThrow(responses)
  }

  func getWindow(id: Int) async throws -> Data {
    guard let tracked = store.trackedWindow(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Window \(id) not found")
    }
    return try encodeOrThrow(
      WindowResponse(id: tracked.id, sessionCount: store.sessions.count))
  }

  func closeWindow(id: Int) async throws -> Data {
    guard let tracked = store.trackedWindow(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Window \(id) not found")
    }
    tracked.window.close()
    store.unregisterWindow(tracked.window)
    return try encodeOrThrow([String: String]())
  }

  func focusWindow(id: Int) async throws -> Data {
    guard let tracked = store.trackedWindow(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Window \(id) not found")
    }
    tracked.window.makeKeyAndOrderFront(nil)
    return try encodeOrThrow([String: String]())
  }

  // MARK: - Popups

  func openPopup(
    sessionId: Int, name: String, exec: String, width: Double, height: Double, closeOnExit: Bool
  ) async throws -> Data {
    guard let session = store.session(byId: sessionId) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(sessionId) not found")
    }
    let definition = PopupDefinition(
      name: name, command: exec, width: width, height: height, closeOnExit: closeOnExit)
    session.openPopup(definition: definition)
    guard let popup = session.activePopup else {
      throw MyttyIPC.error(.operationFailed, "Failed to create popup")
    }
    return try encodeOrThrow(popupResponse(popup))
  }

  func closePopup(id: Int) async throws -> Data {
    guard let (session, popup) = store.popup(byId: id) else {
      throw MyttyIPC.error(.entityNotFound, "Popup \(id) not found")
    }
    session.closePopup(popup)
    return try encodeOrThrow([String: String]())
  }

  func togglePopup(sessionId: Int, name: String) async throws -> Data {
    guard let session = store.session(byId: sessionId) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(sessionId) not found")
    }
    let config = MyttyConfig.load()
    guard let definition = config.popups.first(where: { $0.name == name }) else {
      throw MyttyIPC.error(.entityNotFound, "Popup definition '\(name)' not found in config")
    }
    session.togglePopup(definition: definition)
    if let popup = session.popups.first(where: { $0.definition.name == name }) {
      return try encodeOrThrow(popupResponse(popup))
    }
    return try encodeOrThrow([String: String]())
  }

  func listPopups(sessionId: Int) async throws -> Data {
    guard let session = store.session(byId: sessionId) else {
      throw MyttyIPC.error(.entityNotFound, "Session \(sessionId) not found")
    }
    let responses = session.popups.map { popupResponse($0) }
    return try encodeOrThrow(responses)
  }
}
