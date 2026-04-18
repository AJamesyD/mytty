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

  // MARK: - Popup methods

  private func makePopupDef(name: String = "test", command: String = "htop") -> PopupDefinition {
    PopupDefinition(name: name, command: command)
  }

  func test_togglePopup_createsNewPopup() {
    let session = makeSession()
    let def = makePopupDef()

    session.togglePopup(definition: def)

    XCTAssertEqual(session.popups.count, 1)
    XCTAssertTrue(session.popups[0].isVisible)
    XCTAssertEqual(session.activePopup?.definition.name, "test")
  }

  func test_togglePopup_hidesVisiblePopup() {
    let session = makeSession()
    let def = makePopupDef()
    session.togglePopup(definition: def)
    XCTAssertTrue(session.popups[0].isVisible)

    session.togglePopup(definition: def)

    XCTAssertFalse(session.popups[0].isVisible)
    XCTAssertNil(session.activePopup)
  }

  func test_togglePopup_showsHiddenPopup() {
    let session = makeSession()
    let def = makePopupDef()
    session.togglePopup(definition: def)
    session.togglePopup(definition: def)
    XCTAssertFalse(session.popups[0].isVisible)

    session.togglePopup(definition: def)

    XCTAssertTrue(session.popups[0].isVisible)
    XCTAssertNotNil(session.activePopup)
  }

  func test_togglePopup_hidesOtherPopupWhenShowing() {
    let session = makeSession()
    let def1 = makePopupDef(name: "popup1", command: "htop")
    let def2 = makePopupDef(name: "popup2", command: "btop")
    session.togglePopup(definition: def1)
    session.togglePopup(definition: def2)
    XCTAssertTrue(session.popups[1].isVisible)

    session.togglePopup(definition: def2)
    session.togglePopup(definition: def1)

    XCTAssertTrue(session.popups[0].isVisible)
    XCTAssertEqual(session.activePopup?.definition.name, "popup1")
  }

  func test_openPopup_createsIfNotExists() {
    let session = makeSession()
    let def = makePopupDef()

    session.openPopup(definition: def)

    XCTAssertEqual(session.popups.count, 1)
    XCTAssertTrue(session.popups[0].isVisible)
  }

  func test_openPopup_showsHiddenPopup() {
    let session = makeSession()
    let def = makePopupDef()
    session.togglePopup(definition: def)
    session.togglePopup(definition: def)
    XCTAssertFalse(session.popups[0].isVisible)

    session.openPopup(definition: def)

    XCTAssertTrue(session.popups[0].isVisible)
  }

  func test_openPopup_visiblePopup_isNoop() {
    let session = makeSession()
    let def = makePopupDef()
    session.openPopup(definition: def)
    let popupCount = session.popups.count

    session.openPopup(definition: def)

    XCTAssertEqual(session.popups.count, popupCount)
  }

  func test_closePopup_removesFromArray() {
    let session = makeSession()
    let def = makePopupDef()
    session.togglePopup(definition: def)
    let popup = session.popups[0]

    session.closePopup(popup)

    XCTAssertTrue(session.popups.isEmpty)
    XCTAssertNil(session.activePopup)
  }

  func test_closePopup_clearsActiveIfMatch() {
    let session = makeSession()
    let def1 = makePopupDef(name: "p1")
    let def2 = makePopupDef(name: "p2")
    session.togglePopup(definition: def1)
    session.togglePopup(definition: def2)
    let popup2 = session.popups[1]

    session.closePopup(popup2)

    XCTAssertEqual(session.popups.count, 1)
    XCTAssertNil(session.activePopup)
  }

  func test_hideActivePopup_hidesAndClears() {
    let session = makeSession()
    let def = makePopupDef()
    session.togglePopup(definition: def)
    XCTAssertNotNil(session.activePopup)

    session.hideActivePopup()

    XCTAssertFalse(session.popups[0].isVisible)
    XCTAssertNil(session.activePopup)
  }

  func test_hideActivePopup_noActivePopup_isNoop() {
    let session = makeSession()
    session.hideActivePopup()
    XCTAssertNil(session.activePopup)
  }

  func test_togglePopup_closeOnExit_setsUseCommandField() {
    let session = makeSession()
    let def = PopupDefinition(name: "test", command: "htop", closeOnExit: true)
    session.togglePopup(definition: def)
    XCTAssertFalse(session.popups[0].pane.useCommandField)
  }

  func test_togglePopup_noCloseOnExit_keepsUseCommandField() {
    let session = makeSession()
    let def = PopupDefinition(name: "test", command: "htop", closeOnExit: false)
    session.togglePopup(definition: def)
    XCTAssertTrue(session.popups[0].pane.useCommandField)
  }
}
