import XCTest

@testable import Mytty

@MainActor
final class PersistenceServiceTests: XCTestCase {
  var store: SessionStore!

  override func setUp() async throws {
    await MainActor.run {
      store = SessionStore()
    }
  }

  // MARK: - Round-trip

  func test_roundTrip_singleSession() {
    let session = store.createSession(name: "dev", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    session.tabs[1].customTitle = "editor"

    let state = store.toPersistentState()
    let newStore = SessionStore()
    newStore.restore(from: state)

    XCTAssertEqual(newStore.sessions.count, 1)
    XCTAssertEqual(newStore.sessions[0].name, "dev")
    XCTAssertEqual(newStore.sessions[0].tabs.count, 2)
    XCTAssertEqual(newStore.sessions[0].tabs[1].customTitle, "editor")
  }

  func test_roundTrip_multipleSessions() {
    store.createSession(name: "one", directory: URL(fileURLWithPath: "/tmp"))
    store.createSession(name: "two", directory: URL(fileURLWithPath: "/tmp"))
    store.activeSession = store.sessions[0]

    let state = store.toPersistentState()
    XCTAssertEqual(state.activeSessionIndex, 0)

    let newStore = SessionStore()
    newStore.restore(from: state)

    XCTAssertEqual(newStore.sessions.count, 2)
    XCTAssertEqual(newStore.sessions[0].name, "one")
    XCTAssertEqual(newStore.sessions[1].name, "two")
    XCTAssertEqual(newStore.activeSession?.name, "one")
  }

  func test_roundTrip_splitPanes() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)
    XCTAssertEqual(tab.panes.count, 2)

    let state = store.toPersistentState()
    let newStore = SessionStore()
    newStore.restore(from: state)

    let restoredTab = newStore.sessions[0].tabs[0]
    XCTAssertEqual(restoredTab.panes.count, 2)
    if case .split(let dir, _, _, _) = restoredTab.layout.root {
      XCTAssertEqual(dir, .horizontal)
    } else {
      XCTFail("Expected split layout")
    }
  }

  func test_roundTrip_paneCommand() {
    let session = store.createSession(
      name: "test", directory: URL(fileURLWithPath: "/tmp"), exec: "vim")
    let pane = session.tabs[0].panes[0]
    XCTAssertEqual(pane.command, "vim")

    let state = store.toPersistentState()
    let newStore = SessionStore()
    newStore.restore(from: state)

    XCTAssertEqual(newStore.sessions[0].tabs[0].panes[0].command, "vim")
  }

  func test_roundTrip_activeIndices() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    session.activeTab = session.tabs[1]

    let state = store.toPersistentState()
    XCTAssertEqual(state.sessions[0].activeTabIndex, 1)

    let newStore = SessionStore()
    newStore.restore(from: state)
    XCTAssertEqual(newStore.sessions[0].activeTab?.id, newStore.sessions[0].tabs[1].id)
  }

  // MARK: - JSON encoding/decoding

  func test_jsonRoundTrip() throws {
    store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let state = store.toPersistentState()

    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PersistentState.self, from: data)

    XCTAssertEqual(decoded.version, PersistentState.currentVersion)
    XCTAssertEqual(decoded.sessions.count, 1)
    XCTAssertEqual(decoded.sessions[0].name, "test")
  }

  func test_corruptJson_doesNotCrash() {
    let corrupt = Data("not json".utf8)
    let result = try? JSONDecoder().decode(PersistentState.self, from: corrupt)
    XCTAssertNil(result)
  }

  func test_versionMismatch() throws {
    let state = PersistentState(
      version: 999,
      activeSessionIndex: nil,
      sessions: []
    )
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(PersistentState.self, from: data)
    XCTAssertNotEqual(decoded.version, PersistentState.currentVersion)
  }

  func test_emptySessions() {
    let state = PersistentState(
      version: PersistentState.currentVersion,
      activeSessionIndex: nil,
      sessions: []
    )
    let newStore = SessionStore()
    newStore.restore(from: state)
    XCTAssertTrue(newStore.sessions.isEmpty)
  }

  func test_missingDirectory_substitutesHome() {
    let state = PersistentState(
      version: PersistentState.currentVersion,
      activeSessionIndex: 0,
      sessions: [
        PersistentSession(
          name: "test",
          directory: URL(fileURLWithPath: "/nonexistent/path/that/does/not/exist"),
          activeTabIndex: 0,
          tabs: [
            PersistentTab(
              customTitle: nil,
              directory: nil,
              activePaneIndex: 0,
              layout: .leaf(
                PersistentPane(
                  directory: URL(fileURLWithPath: "/also/nonexistent"),
                  command: nil,
                  useCommandField: true
                ))
            )
          ]
        )
      ]
    )
    let newStore = SessionStore()
    newStore.restore(from: state)

    let home = FileManager.default.homeDirectoryForCurrentUser
    XCTAssertEqual(newStore.sessions[0].directory, home)
    XCTAssertEqual(newStore.sessions[0].tabs[0].panes[0].directory, home)
  }

  func test_roundTrip_sshCommand() {
    let session = store.createSession(name: "remote", directory: URL(fileURLWithPath: "/tmp"))
    session.sshCommand = "ssh test-user@test-host"

    let state = store.toPersistentState()
    let newStore = SessionStore()
    newStore.restore(from: state)

    XCTAssertEqual(newStore.sessions[0].sshCommand, "ssh test-user@test-host")
  }
}
