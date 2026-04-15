import XCTest

@testable import Mistty
@testable import MisttyShared

@MainActor
final class IPCServiceTests: XCTestCase {
  var store: SessionStore!
  var service: MisttyIPCService!

  override func setUp() async throws {
    await MainActor.run {
      store = SessionStore()
      service = MisttyIPCService(store: store)
    }
  }

  func testCreateSession() async throws {
    let data = try await service.createSession(name: "test", directory: "/tmp", exec: nil)
    let response = try JSONDecoder().decode(SessionResponse.self, from: data)
    XCTAssertEqual(response.name, "test")
    XCTAssertEqual(response.directory, "/tmp")
    XCTAssertEqual(response.tabCount, 1)
    XCTAssertFalse(response.tabIds.isEmpty)
    XCTAssertEqual(store.sessions.count, 1)
  }

  func testCreateSessionDefaultDirectory() async throws {
    let data = try await service.createSession(name: "home", directory: nil, exec: nil)
    let response = try JSONDecoder().decode(SessionResponse.self, from: data)
    XCTAssertEqual(response.name, "home")
  }

  func testListSessions() async throws {
    store.createSession(name: "alpha", directory: URL(fileURLWithPath: "/tmp"))
    store.createSession(name: "beta", directory: URL(fileURLWithPath: "/tmp"))

    let data = try await service.listSessions()
    let responses = try JSONDecoder().decode([SessionResponse].self, from: data)
    XCTAssertEqual(responses.count, 2)
    XCTAssertEqual(responses[0].name, "alpha")
    XCTAssertEqual(responses[1].name, "beta")
  }

  func testListSessionsEmpty() async throws {
    let data = try await service.listSessions()
    let responses = try JSONDecoder().decode([SessionResponse].self, from: data)
    XCTAssertTrue(responses.isEmpty)
  }

  func testGetSession() async throws {
    let session = store.createSession(name: "myproject", directory: URL(fileURLWithPath: "/tmp"))

    let data = try await service.getSession(id: session.id)
    let response = try JSONDecoder().decode(SessionResponse.self, from: data)
    XCTAssertEqual(response.id, session.id)
    XCTAssertEqual(response.name, "myproject")
    XCTAssertEqual(response.directory, "/tmp")
  }

  func testGetSessionNotFound() async throws {
    do {
      _ = try await service.getSession(id: 999)
      XCTFail("Expected error")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.domain, MisttyIPC.errorDomain)
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.entityNotFound.rawValue)
    }
  }

  func testCloseSession() async throws {
    let session = store.createSession(name: "doomed", directory: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(store.sessions.count, 1)

    let data = try await service.closeSession(id: session.id)
    XCTAssertNotNil(data)
    XCTAssertTrue(store.sessions.isEmpty)
  }

  func testCloseSessionNotFound() async throws {
    do {
      _ = try await service.closeSession(id: 999)
      XCTFail("Expected error")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.entityNotFound.rawValue)
    }
  }

  // MARK: - Tab Tests

  func testCreateTab() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    XCTAssertEqual(session.tabs.count, 1)

    let data = try await service.createTab(sessionId: session.id, name: "build", exec: nil)
    let response = try JSONDecoder().decode(TabResponse.self, from: data)
    XCTAssertEqual(response.title, "build")
    XCTAssertEqual(response.paneCount, 1)
    XCTAssertFalse(response.paneIds.isEmpty)
    XCTAssertEqual(session.tabs.count, 2)
  }

  func testListTabs() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()

    let data = try await service.listTabs(sessionId: session.id)
    let responses = try JSONDecoder().decode([TabResponse].self, from: data)
    XCTAssertEqual(responses.count, 2)
  }

  func testCloseTab() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    XCTAssertEqual(session.tabs.count, 2)
    let tabId = session.tabs[0].id

    let data = try await service.closeTab(id: tabId)
    XCTAssertNotNil(data)
    XCTAssertEqual(session.tabs.count, 1)
  }

  func testRenameTab() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]

    let data = try await service.renameTab(id: tab.id, name: "logs")
    let response = try JSONDecoder().decode(TabResponse.self, from: data)
    XCTAssertEqual(response.title, "logs")
    XCTAssertEqual(tab.customTitle, "logs")
  }

  // MARK: - Pane Tests

  func testListPanes() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]

    let data = try await service.listPanes(tabId: tab.id)
    let responses = try JSONDecoder().decode([PaneResponse].self, from: data)
    XCTAssertEqual(responses.count, 1)
  }

  func testActivePane() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]

    let data = try await service.activePane()
    let response = try JSONDecoder().decode(PaneResponse.self, from: data)
    XCTAssertEqual(response.id, pane.id)
  }

  func testClosePane() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .vertical)
    XCTAssertEqual(tab.panes.count, 2)
    let paneToClose = tab.panes[0]

    let data = try await service.closePane(id: paneToClose.id)
    XCTAssertNotNil(data)
    XCTAssertEqual(tab.panes.count, 1)
  }

  func testGetPaneNotFound() async throws {
    do {
      _ = try await service.getPane(id: 999)
      XCTFail("Expected error")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.entityNotFound.rawValue)
    }
  }

  // MARK: - SendKeys / RunCommand Tests

  func testSendKeysResolvesPane() async throws {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneId = session.activeTab!.activePane!.id

    do {
      _ = try await service.sendKeys(paneId: paneId, keys: "hello")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.operationFailed.rawValue)
    }
  }

  func testSendKeysPaneNotFound() async throws {
    do {
      _ = try await service.sendKeys(paneId: 999, keys: "hello")
      XCTFail("Expected error")
    } catch {
      XCTAssertEqual((error as NSError).code, MisttyIPC.ErrorCode.entityNotFound.rawValue)
    }
  }

  func testSendKeysActivePane() async throws {
    _ = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))

    do {
      _ = try await service.sendKeys(paneId: 0, keys: "hello")
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.operationFailed.rawValue)
    }
  }

  func testRunCommandDelegatesToSendKeys() async throws {
    do {
      _ = try await service.runCommand(paneId: 999, command: "ls")
      XCTFail("Expected error")
    } catch {
      XCTAssertEqual((error as NSError).code, MisttyIPC.ErrorCode.entityNotFound.rawValue)
    }
  }

  // MARK: - GetText Tests

  func testGetTextResolvesPane() async throws {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneId = session.activeTab!.activePane!.id

    do {
      _ = try await service.getText(paneId: paneId)
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.operationFailed.rawValue)
    }
  }

  func testGetTextPaneNotFound() async throws {
    do {
      _ = try await service.getText(paneId: 999)
      XCTFail("Expected error")
    } catch {
      XCTAssertEqual((error as NSError).code, MisttyIPC.ErrorCode.entityNotFound.rawValue)
    }
  }

  func testGetTextActivePane() async throws {
    _ = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))

    do {
      _ = try await service.getText(paneId: 0)
    } catch {
      let nsError = error as NSError
      XCTAssertEqual(nsError.code, MisttyIPC.ErrorCode.operationFailed.rawValue)
    }
  }

  func testFocusPaneByDirection() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)
    let leftPane = tab.panes[0]
    let rightPane = tab.panes[1]
    XCTAssertEqual(tab.activePane?.id, rightPane.id)

    let data = try await service.focusPaneByDirection(direction: "left", sessionId: session.id)
    let response = try JSONDecoder().decode(PaneResponse.self, from: data)
    XCTAssertEqual(response.id, leftPane.id)
    XCTAssertEqual(tab.activePane?.id, leftPane.id)
  }

  func testFocusPaneByDirectionInvalid() async throws {
    _ = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))

    do {
      _ = try await service.focusPaneByDirection(direction: "diagonal", sessionId: 0)
      XCTFail("Expected error")
    } catch {
      XCTAssertEqual((error as NSError).code, MisttyIPC.ErrorCode.invalidArgument.rawValue)
    }
  }

  func testFocusPane() async throws {
    let session = store.createSession(name: "proj", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .vertical)
    let firstPane = tab.panes[0]
    XCTAssertNotEqual(tab.activePane?.id, firstPane.id)

    let data = try await service.focusPane(id: firstPane.id)
    let response = try JSONDecoder().decode(PaneResponse.self, from: data)
    XCTAssertEqual(response.id, firstPane.id)
    XCTAssertEqual(tab.activePane?.id, firstPane.id)
    XCTAssertEqual(store.activeSession?.id, session.id)
    XCTAssertEqual(session.activeTab?.id, tab.id)
  }
}
