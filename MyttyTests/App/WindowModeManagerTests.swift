import XCTest

@testable import Mytty

@MainActor
final class WindowModeManagerTests: XCTestCase {
  private var store: SessionStore!
  private var manager: WindowModeManager!

  override func setUp() {
    super.setUp()
    store = SessionStore()
    manager = WindowModeManager()
  }

  override func tearDown() {
    manager = nil
    store = nil
    super.tearDown()
  }

  // MARK: - toggleZoom

  func test_toggleZoom_setsZoomedPane() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.activeTab!
    tab.splitActivePane(direction: .horizontal)
    XCTAssertNil(tab.zoomedPane)

    manager.toggleZoom(store: store)

    XCTAssertNotNil(tab.zoomedPane)
    XCTAssertEqual(tab.zoomedPane?.id, tab.activePane?.id)
  }

  func test_toggleZoom_unsetsZoomedPane() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.activeTab!
    tab.splitActivePane(direction: .horizontal)
    tab.zoomedPane = tab.activePane

    manager.toggleZoom(store: store)

    XCTAssertNil(tab.zoomedPane)
  }

  // MARK: - breakPaneToTab

  func test_breakPaneToTab_createsNewTab() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.activeTab!
    tab.splitActivePane(direction: .horizontal)
    let paneToBreak = tab.activePane!
    XCTAssertEqual(session.tabs.count, 1)
    XCTAssertEqual(tab.panes.count, 2)

    manager.breakPaneToTab(store: store)

    XCTAssertEqual(session.tabs.count, 2)
    XCTAssertEqual(session.tabs[1].panes.count, 1)
    XCTAssertEqual(session.tabs[1].panes[0].id, paneToBreak.id)
  }

  func test_breakPaneToTab_singlePane_doesNothing() {
    store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let session = store.activeSession!
    XCTAssertEqual(session.tabs.count, 1)
    XCTAssertEqual(session.activeTab!.panes.count, 1)

    manager.breakPaneToTab(store: store)

    XCTAssertEqual(session.tabs.count, 1)
  }

  func test_breakPaneToTab_removesFromSourceTab() {
    store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = store.activeSession!.activeTab!
    tab.splitActivePane(direction: .horizontal)
    XCTAssertEqual(tab.panes.count, 2)

    manager.breakPaneToTab(store: store)

    XCTAssertEqual(tab.panes.count, 1)
  }

  // MARK: - joinPaneToTab

  func test_joinPaneToTab_movesPaneToTarget() {
    store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let session = store.activeSession!
    let tab0 = session.activeTab!
    tab0.splitActivePane(direction: .horizontal)
    session.addTab()
    let targetTab = session.tabs[1]
    let targetPaneCount = targetTab.panes.count
    session.activeTab = session.tabs[0]
    let paneToMove = session.activeTab!.activePane!

    manager.joinPaneToTab(targetIndex: 0, store: store)

    XCTAssertEqual(targetTab.panes.count, targetPaneCount + 1)
    XCTAssertTrue(targetTab.panes.contains(where: { $0.id == paneToMove.id }))
  }

  func test_joinPaneToTab_outOfRange_doesNothing() {
    store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let session = store.activeSession!
    session.activeTab!.splitActivePane(direction: .horizontal)
    session.addTab()
    session.activeTab = session.tabs[0]
    let tabCount = session.tabs.count

    manager.joinPaneToTab(targetIndex: 99, store: store)

    XCTAssertEqual(session.tabs.count, tabCount)
  }

  func test_joinPaneToTab_lastPaneClosesSourceTab() {
    store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let session = store.activeSession!
    session.addTab()
    session.activeTab = session.tabs[0]
    XCTAssertEqual(session.tabs.count, 2)

    manager.joinPaneToTab(targetIndex: 0, store: store)

    XCTAssertEqual(session.tabs.count, 1)
  }
}
