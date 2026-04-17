import XCTest

@testable import Mytty

@MainActor
final class MyttySessionTests: XCTestCase {
  private func makeSession(name: String = "test") -> MyttySession {
    var nextTab = 1
    var nextPane = 1
    var nextPopup = 1
    return MyttySession(
      id: 1, name: name,
      directory: URL(fileURLWithPath: "/tmp"),
      tabIDGenerator: {
        defer { nextTab += 1 }
        return nextTab
      },
      paneIDGenerator: {
        defer { nextPane += 1 }
        return nextPane
      },
      popupIDGenerator: {
        defer { nextPopup += 1 }
        return nextPopup
      }
    )
  }

  func test_initCreatesOneTab() {
    let session = makeSession()
    XCTAssertEqual(session.tabs.count, 1)
    XCTAssertNotNil(session.activeTab)
    XCTAssertEqual(session.activeTab?.id, session.tabs[0].id)
  }

  func test_addTab() {
    let session = makeSession()
    session.addTab()
    XCTAssertEqual(session.tabs.count, 2)
    XCTAssertEqual(session.activeTab?.id, session.tabs[1].id)
  }

  func test_closeTab_switchesToLast() {
    let session = makeSession()
    session.addTab()
    let first = session.tabs[0]
    let second = session.tabs[1]
    session.activeTab = second
    session.closeTab(second)
    XCTAssertEqual(session.tabs.count, 1)
    XCTAssertEqual(session.activeTab?.id, first.id)
  }

  func test_closeTab_nonActive() {
    let session = makeSession()
    session.addTab()
    let first = session.tabs[0]
    let second = session.tabs[1]
    session.activeTab = second
    session.closeTab(first)
    XCTAssertEqual(session.tabs.count, 1)
    XCTAssertEqual(session.activeTab?.id, second.id)
  }

  func test_moveTab() {
    let session = makeSession()
    session.addTab()
    let firstID = session.tabs[0].id
    let secondID = session.tabs[1].id
    session.moveTab(withID: firstID, toIndex: 1)
    XCTAssertEqual(session.tabs[0].id, secondID)
    XCTAssertEqual(session.tabs[1].id, firstID)
  }

  func test_moveTab_sameIndex() {
    let session = makeSession()
    session.addTab()
    let firstID = session.tabs[0].id
    let secondID = session.tabs[1].id
    session.moveTab(withID: firstID, toIndex: 0)
    XCTAssertEqual(session.tabs[0].id, firstID)
    XCTAssertEqual(session.tabs[1].id, secondID)
  }

  func test_nextTab_wraps() {
    let session = makeSession()
    session.addTab()
    session.addTab()
    let firstID = session.tabs[0].id
    session.activeTab = session.tabs[2]
    session.nextTab()
    XCTAssertEqual(session.activeTab?.id, firstID)
  }

  func test_prevTab_wraps() {
    let session = makeSession()
    session.addTab()
    session.addTab()
    let lastID = session.tabs[2].id
    session.activeTab = session.tabs[0]
    session.prevTab()
    XCTAssertEqual(session.activeTab?.id, lastID)
  }

  func test_nextTab_singleTab() {
    let session = makeSession()
    let tabID = session.activeTab?.id
    session.nextTab()
    XCTAssertEqual(session.activeTab?.id, tabID)
  }
}
