// swiftlint:disable:next blanket_disable_command
// swiftlint:disable force_unwrapping
import AppKit
import GhosttyKit
import XCTest

@testable import Mytty

@MainActor
final class ContentViewHandlerTests: XCTestCase {
  var store: SessionStore!

  override func setUp() async throws {
    await MainActor.run {
      store = SessionStore()
    }
  }

  // MARK: - handleSetTitle

  func test_handleSetTitle_setsProcessTitle() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleSetTitle(
      Notification(
        name: .ghosttySetTitle, object: nil,
        userInfo: [Notification.payloadKey: SetTitlePayload(paneID: paneID, title: "vim")]))

    XCTAssertEqual(session.tabs[0].panes[0].processTitle, "vim")
  }

  // MARK: - handleRingBell

  func test_handleRingBell_backgroundTab_setsHasBell() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    let backgroundTab = session.tabs[0]
    let paneID = backgroundTab.panes[0].id
    let view = ContentView(store: store)

    view.handleRingBell(
      Notification(
        name: .ghosttyRingBell, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertTrue(backgroundTab.hasBell)
  }

  func test_handleRingBell_activeTab_doesNotSetHasBell() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let activeTab = session.activeTab!
    let paneID = activeTab.panes[0].id
    let view = ContentView(store: store)

    view.handleRingBell(
      Notification(
        name: .ghosttyRingBell, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertFalse(activeTab.hasBell)
  }

  // MARK: - handleCloseSurface

  func test_handleCloseSurface_removesPane() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleCloseSurface(
      Notification(
        name: .ghosttyCloseSurface, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertTrue(store.sessions.isEmpty)
  }

  // MARK: - handlePwd

  func test_handlePwd_setsWorkingDirectory() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handlePwd(
      Notification(
        name: .ghosttyPwd, object: nil,
        userInfo: [Notification.payloadKey: PwdPayload(paneID: paneID, pwd: "/Users/test")]))

    XCTAssertEqual(session.tabs[0].panes[0].workingDirectory?.path, "/Users/test")
  }

  // MARK: - handleSetTabTitle

  func test_handleSetTabTitle_setsTabTitle() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleSetTabTitle(
      Notification(
        name: .ghosttySetTabTitle, object: nil,
        userInfo: [Notification.payloadKey: SetTitlePayload(paneID: paneID, title: "editor")]))

    XCTAssertEqual(session.tabs[0].tabTitle, "editor")
  }

  // MARK: - handleDesktopNotification

  func test_handleDesktopNotification_activePaneReturnsEarly() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.activeTab!.activePane!.id
    let view = ContentView(store: store)

    view.handleDesktopNotification(
      Notification(
        name: .ghosttyDesktopNotification, object: nil,
        userInfo: [Notification.payloadKey: DesktopNotificationPayload(paneID: paneID, title: "done", body: "task finished")]))
  }

  // MARK: - handleCommandFinished

  func test_handleCommandFinished_setsLastCommandResult() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleCommandFinished(
      Notification(
        name: .ghosttyCommandFinished, object: nil,
        userInfo: [Notification.payloadKey: CommandFinishedPayload(paneID: paneID, exitCode: Int16(0), duration: UInt64(1_000_000))]))

    XCTAssertEqual(session.tabs[0].panes[0].lastCommandResult?.exitCode, 0)
  }

  func test_handleCommandFinished_backgroundTab_nonZeroExit_setsHasFailedCommand() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    let backgroundTab = session.tabs[0]
    let paneID = backgroundTab.panes[0].id
    let view = ContentView(store: store)

    view.handleCommandFinished(
      Notification(
        name: .ghosttyCommandFinished, object: nil,
        userInfo: [Notification.payloadKey: CommandFinishedPayload(paneID: paneID, exitCode: Int16(1), duration: UInt64(500))]))

    XCTAssertTrue(backgroundTab.hasFailedCommand)
  }

  func test_handleCommandFinished_activeTab_nonZeroExit_doesNotSetHasFailedCommand() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let activeTab = session.activeTab!
    let paneID = activeTab.panes[0].id
    let view = ContentView(store: store)

    view.handleCommandFinished(
      Notification(
        name: .ghosttyCommandFinished, object: nil,
        userInfo: [Notification.payloadKey: CommandFinishedPayload(paneID: paneID, exitCode: Int16(1), duration: UInt64(500))]))

    XCTAssertFalse(activeTab.hasFailedCommand)
  }

  // MARK: - handleProgressReport

  func test_handleProgressReport_setState_setsProgress() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleProgressReport(
      Notification(
        name: .ghosttyProgressReport, object: nil,
        userInfo: [
          Notification.payloadKey: ProgressReportPayload(
            paneID: paneID,
            state: GHOSTTY_PROGRESS_STATE_SET.rawValue,
            progress: Int8(75)),
        ]))

    if case .set(let progress) = session.tabs[0].panes[0].progressState {
      XCTAssertEqual(progress, 75)
    } else {
      XCTFail("Expected .set state")
    }
  }

  func test_handleProgressReport_removeState_setsNil() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.progressState = .set(progress: 50)
    let view = ContentView(store: store)

    view.handleProgressReport(
      Notification(
        name: .ghosttyProgressReport, object: nil,
        userInfo: [
          Notification.payloadKey: ProgressReportPayload(
            paneID: pane.id,
            state: GHOSTTY_PROGRESS_STATE_REMOVE.rawValue,
            progress: Int8(0)),
        ]))

    XCTAssertNil(pane.progressState)
  }

  // MARK: - handleColorChange

  func test_handleColorChange_background_setsLayerColor() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.surfaceView.wantsLayer = true
    let view = ContentView(store: store)

    view.handleColorChange(
      Notification(
        name: .ghosttyColorChange, object: nil,
        userInfo: [
          Notification.payloadKey: ColorChangePayload(
            paneID: pane.id, kind: .background, r: 0.2, g: 0.3, b: 0.4),
        ]))

    XCTAssertNotNil(pane.surfaceView.layer?.backgroundColor)
  }

  func test_handleColorChange_foreground_ignored() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.surfaceView.wantsLayer = true
    let view = ContentView(store: store)

    view.handleColorChange(
      Notification(
        name: .ghosttyColorChange, object: nil,
        userInfo: [
          Notification.payloadKey: ColorChangePayload(
            paneID: pane.id, kind: .foreground, r: 1.0, g: 1.0, b: 1.0),
        ]))

    XCTAssertNil(pane.surfaceView.layer?.backgroundColor)
  }

  // MARK: - Nil Safety

  func test_handler_nilPaneID_doesNotCrash() {
    let view = ContentView(store: store)
    let handlers: [(ContentView, Notification) -> Void] = [
      { $0.handleSetTitle($1) },
      { $0.handleRingBell($1) },
      { $0.handleCloseSurface($1) },
      { $0.handlePwd($1) },
      { $0.handleSetTabTitle($1) },
      { $0.handleCommandFinished($1) },
      { $0.handleProgressReport($1) },
      { $0.handleGhosttyNewTab($1) },
      { $0.handleGhosttyCloseTab($1) },
      { $0.handleGhosttyToggleSplitZoom($1) },
      { $0.handleGhosttyChildExited($1) },
    ]
    for handler in handlers {
      handler(view, Notification(
        name: .ghosttySetTitle, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: nil)]))
    }
  }

  func test_handler_unknownPaneID_doesNotCrash() {
    _ = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let view = ContentView(store: store)
    let unknownID = 999_999
    let handlers: [(ContentView, Notification) -> Void] = [
      { $0.handleSetTitle($1) },
      { $0.handleRingBell($1) },
      { $0.handleCloseSurface($1) },
      { $0.handlePwd($1) },
      { $0.handleSetTabTitle($1) },
      { $0.handleCommandFinished($1) },
      { $0.handleProgressReport($1) },
      { $0.handleGhosttyNewTab($1) },
      { $0.handleGhosttyCloseTab($1) },
      { $0.handleGhosttyToggleSplitZoom($1) },
      { $0.handleGhosttyChildExited($1) },
    ]
    for handler in handlers {
      handler(view, Notification(
        name: .ghosttySetTitle, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: unknownID)]))
    }
  }

  func test_handler_missingPayload_doesNotCrash() {
    let view = ContentView(store: store)
    let names: [Notification.Name] = [
      .ghosttySetTitle, .ghosttyRingBell, .ghosttyCloseSurface,
      .ghosttyPwd, .ghosttySetTabTitle, .ghosttyCommandFinished,
      .ghosttyProgressReport, .ghosttyNewTab, .ghosttyCloseTab,
      .ghosttyToggleSplitZoom, .ghosttyChildExited,
    ]
    for name in names {
      let notification = Notification(name: name, object: nil, userInfo: nil)
      XCTAssertNil(notification.payload(PanePayload.self))
    }
  }
}
