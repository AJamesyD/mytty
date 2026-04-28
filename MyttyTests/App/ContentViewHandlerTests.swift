// Force-unwrap is idiomatic in tests (XCTUnwrap for failable, ! for known-good fixtures).
// SwiftLint lacks per-directory rule exclusions, so blanket disable is the only option.
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

  // MARK: - handleMouseOverLink

  func test_handleMouseOverLink_setsHoverUrl() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleMouseOverLink(
      Notification(
        name: .ghosttyMouseOverLink, object: nil,
        userInfo: [
          Notification.payloadKey: MouseOverLinkPayload(paneID: paneID, url: "https://example.com")
        ]))

    XCTAssertEqual(session.tabs[0].panes[0].hoverUrl, "https://example.com")
  }

  func test_handleMouseOverLink_clearsHoverUrl() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.hoverUrl = "https://example.com"
    let view = ContentView(store: store)

    view.handleMouseOverLink(
      Notification(
        name: .ghosttyMouseOverLink, object: nil,
        userInfo: [Notification.payloadKey: MouseOverLinkPayload(paneID: pane.id, url: nil)]))

    XCTAssertNil(pane.hoverUrl)
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
        userInfo: [
          Notification.payloadKey: DesktopNotificationPayload(
            paneID: paneID, title: "done", body: "task finished")
        ]))
  }

  // MARK: - handleCommandFinished

  func test_handleCommandFinished_setsLastCommandResult() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleCommandFinished(
      Notification(
        name: .ghosttyCommandFinished, object: nil,
        userInfo: [
          Notification.payloadKey: CommandFinishedPayload(
            paneID: paneID, exitCode: Int16(0), duration: UInt64(1_000_000))
        ]))

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
        userInfo: [
          Notification.payloadKey: CommandFinishedPayload(
            paneID: paneID, exitCode: Int16(1), duration: UInt64(500))
        ]))

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
        userInfo: [
          Notification.payloadKey: CommandFinishedPayload(
            paneID: paneID, exitCode: Int16(1), duration: UInt64(500))
        ]))

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
            state: .set,
            progress: Int8(75))
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
            state: .remove,
            progress: Int8(0))
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
            paneID: pane.id, kind: .background, r: 0.2, g: 0.3, b: 0.4)
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
            paneID: pane.id, kind: .foreground, r: 1.0, g: 1.0, b: 1.0)
        ]))

    XCTAssertNil(pane.surfaceView.layer?.backgroundColor)
  }

  // MARK: - handleGhosttyNewTab

  func test_handleGhosttyNewTab_addsTab() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyNewTab(
      Notification(
        name: .ghosttyNewTab, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertEqual(session.tabs.count, 2)
  }

  // MARK: - handleGhosttyNewSplit

  func test_handleGhosttyNewSplit_splitsPaneHorizontally() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let tab = session.tabs[0]
    let view = ContentView(store: store)

    view.handleGhosttyNewSplit(
      Notification(
        name: .ghosttyNewSplit, object: nil,
        userInfo: [
          Notification.payloadKey: NewSplitPayload(paneID: paneID, direction: .horizontal)
        ]))

    XCTAssertEqual(tab.panes.count, 2)
  }

  // MARK: - handleGhosttyCloseTab

  func test_handleGhosttyCloseTab_singleTab_closesSession() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyCloseTab(
      Notification(
        name: .ghosttyCloseTab, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertTrue(store.sessions.isEmpty)
  }

  func test_handleGhosttyCloseTab_multipleTabs_removesTab() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyCloseTab(
      Notification(
        name: .ghosttyCloseTab, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertEqual(session.tabs.count, 1)
  }

  // MARK: - handleGhosttyCloseWindow

  func test_handleGhosttyCloseWindow_closesSession() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyCloseWindow(
      Notification(
        name: .ghosttyCloseWindow, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertTrue(store.sessions.isEmpty)
  }

  // MARK: - handleGhosttyGotoSplit

  func test_handleGhosttyGotoSplit_next_activatesNextPane() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)
    let firstPaneID = tab.panes[0].id
    let secondPane = tab.panes[1]
    let view = ContentView(store: store)

    view.handleGhosttyGotoSplit(
      Notification(
        name: .ghosttyGotoSplit, object: nil,
        userInfo: [
          Notification.payloadKey: GotoSplitPayload(paneID: firstPaneID, direction: .next)
        ]))

    XCTAssertEqual(tab.activePane?.id, secondPane.id)
  }

  func test_handleGhosttyGotoSplit_previous_activatesPreviousPane() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)
    let firstPane = tab.panes[0]
    let secondPaneID = tab.panes[1].id
    let view = ContentView(store: store)

    view.handleGhosttyGotoSplit(
      Notification(
        name: .ghosttyGotoSplit, object: nil,
        userInfo: [
          Notification.payloadKey: GotoSplitPayload(paneID: secondPaneID, direction: .previous)
        ]))

    XCTAssertEqual(tab.activePane?.id, firstPane.id)
  }

  // MARK: - handleGhosttyResizeSplit

  func test_handleGhosttyResizeSplit_doesNotCrash() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)
    let paneID = tab.panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyResizeSplit(
      Notification(
        name: .ghosttyResizeSplit, object: nil,
        userInfo: [
          Notification.payloadKey: ResizeSplitPayload(paneID: paneID, amount: 10, direction: .right)
        ]))
  }

  // MARK: - handleGhosttyEqualizeSplits

  func test_handleGhosttyEqualizeSplits_doesNotCrash() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)
    let paneID = tab.panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyEqualizeSplits(
      Notification(
        name: .ghosttyEqualizeSplits, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))
  }

  // MARK: - handleGhosttyToggleSplitZoom

  func test_handleGhosttyToggleSplitZoom_zoomOn() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    let paneID = tab.panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyToggleSplitZoom(
      Notification(
        name: .ghosttyToggleSplitZoom, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: paneID)]))

    XCTAssertEqual(tab.zoomedPane?.id, paneID)
  }

  func test_handleGhosttyToggleSplitZoom_zoomOff() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    let pane = tab.panes[0]
    tab.zoomedPane = pane
    let view = ContentView(store: store)

    view.handleGhosttyToggleSplitZoom(
      Notification(
        name: .ghosttyToggleSplitZoom, object: nil,
        userInfo: [Notification.payloadKey: PanePayload(paneID: pane.id)]))

    XCTAssertNil(tab.zoomedPane)
  }

  // MARK: - handleGhosttyGotoTab

  func test_handleGhosttyGotoTab_byIndex_activatesTab() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    let paneID = session.tabs[1].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyGotoTab(
      Notification(
        name: .ghosttyGotoTab, object: nil,
        userInfo: [Notification.payloadKey: GotoTabPayload(paneID: paneID, tab: 0)]))

    XCTAssertEqual(session.activeTab?.id, session.tabs[0].id)
  }

  func test_handleGhosttyGotoTab_previous_activatesPreviousTab() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    let paneID = session.tabs[1].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyGotoTab(
      Notification(
        name: .ghosttyGotoTab, object: nil,
        userInfo: [Notification.payloadKey: GotoTabPayload(paneID: paneID, tab: -1)]))

    XCTAssertEqual(session.activeTab?.id, session.tabs[0].id)
  }

  func test_handleGhosttyGotoTab_next_activatesNextTab() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    session.activeTab = session.tabs[0]
    let paneID = session.tabs[0].panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyGotoTab(
      Notification(
        name: .ghosttyGotoTab, object: nil,
        userInfo: [Notification.payloadKey: GotoTabPayload(paneID: paneID, tab: -2)]))

    XCTAssertEqual(session.activeTab?.id, session.tabs[1].id)
  }

  // MARK: - handleGhosttyMoveTab

  func test_handleGhosttyMoveTab_movesTabForward() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    let firstTab = session.tabs[0]
    let paneID = firstTab.panes[0].id
    let view = ContentView(store: store)

    view.handleGhosttyMoveTab(
      Notification(
        name: .ghosttyMoveTab, object: nil,
        userInfo: [Notification.payloadKey: MoveTabPayload(paneID: paneID, amount: 1)]))

    XCTAssertEqual(session.tabs[1].id, firstTab.id)
  }

  // MARK: - handleKeyTable

  func test_handleKeyTable_activate_addsKeyTable() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    let view = ContentView(store: store)

    view.handleKeyTable(
      Notification(
        name: .ghosttyKeyTable, object: nil,
        userInfo: [
          Notification.payloadKey: KeyTablePayload(
            paneID: pane.id, action: .activate(name: "leader"))
        ]))

    XCTAssertEqual(pane.activeKeyTables, ["leader"])
  }

  func test_handleKeyTable_deactivate_removesLastKeyTable() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.activeKeyTables = ["leader"]
    let view = ContentView(store: store)

    view.handleKeyTable(
      Notification(
        name: .ghosttyKeyTable, object: nil,
        userInfo: [
          Notification.payloadKey: KeyTablePayload(paneID: pane.id, action: .deactivate)
        ]))

    XCTAssertTrue(pane.activeKeyTables.isEmpty)
  }

  func test_handleKeyTable_deactivateAll_clearsAllKeyTables() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.activeKeyTables = ["a", "b"]
    let view = ContentView(store: store)

    view.handleKeyTable(
      Notification(
        name: .ghosttyKeyTable, object: nil,
        userInfo: [
          Notification.payloadKey: KeyTablePayload(paneID: pane.id, action: .deactivateAll)
        ]))

    XCTAssertTrue(pane.activeKeyTables.isEmpty)
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
      { $0.handleDesktopNotification($1) },
      { $0.handleGhosttyNewTab($1) },
      { $0.handleGhosttyNewSplit($1) },
      { $0.handleGhosttyCloseTab($1) },
      { $0.handleGhosttyCloseWindow($1) },
      { $0.handleGhosttyGotoSplit($1) },
      { $0.handleGhosttyResizeSplit($1) },
      { $0.handleGhosttyEqualizeSplits($1) },
      { $0.handleGhosttyToggleSplitZoom($1) },
      { $0.handleGhosttyGotoTab($1) },
      { $0.handleGhosttyMoveTab($1) },
      { $0.handleKeyTable($1) },
      { $0.handleGhosttyChildExited($1) },
      { $0.handleMouseOverLink($1) },
      { $0.handleColorChange($1) },
      { $0.handleGhosttyToggleFullscreen($1) },
      { $0.handleGhosttyToggleMaximize($1) },
    ]
    for handler in handlers {
      handler(
        view,
        Notification(
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
      { $0.handleDesktopNotification($1) },
      { $0.handleGhosttyNewTab($1) },
      { $0.handleGhosttyNewSplit($1) },
      { $0.handleGhosttyCloseTab($1) },
      { $0.handleGhosttyCloseWindow($1) },
      { $0.handleGhosttyGotoSplit($1) },
      { $0.handleGhosttyResizeSplit($1) },
      { $0.handleGhosttyEqualizeSplits($1) },
      { $0.handleGhosttyToggleSplitZoom($1) },
      { $0.handleGhosttyGotoTab($1) },
      { $0.handleGhosttyMoveTab($1) },
      { $0.handleKeyTable($1) },
      { $0.handleGhosttyChildExited($1) },
      { $0.handleMouseOverLink($1) },
      { $0.handleColorChange($1) },
      { $0.handleGhosttyToggleFullscreen($1) },
      { $0.handleGhosttyToggleMaximize($1) },
    ]
    for handler in handlers {
      handler(
        view,
        Notification(
          name: .ghosttySetTitle, object: nil,
          userInfo: [Notification.payloadKey: PanePayload(paneID: unknownID)]))
    }
  }

  func test_handler_missingPayload_doesNotCrash() {
    _ = ContentView(store: store)
    let names: [Notification.Name] = [
      .ghosttySetTitle, .ghosttyRingBell, .ghosttyCloseSurface,
      .ghosttyPwd, .ghosttySetTabTitle, .ghosttyCommandFinished,
      .ghosttyProgressReport, .ghosttyDesktopNotification, .ghosttyNewTab, .ghosttyNewSplit,
      .ghosttyCloseTab, .ghosttyCloseWindow, .ghosttyGotoSplit,
      .ghosttyResizeSplit, .ghosttyEqualizeSplits, .ghosttyToggleSplitZoom,
      .ghosttyGotoTab, .ghosttyMoveTab, .ghosttyKeyTable,
      .ghosttyChildExited,
      .ghosttyMouseOverLink, .ghosttyColorChange,
      .ghosttyToggleFullscreen, .ghosttyToggleMaximize,
    ]
    for name in names {
      let notification = Notification(name: name, object: nil, userInfo: nil)
      XCTAssertNil(notification.payload(PanePayload.self))
    }
  }
}
