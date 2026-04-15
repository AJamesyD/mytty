import XCTest

@testable import Mistty

@MainActor
final class PaneNavigationManagerTests: XCTestCase {

  private var manager: PaneNavigationManager!
  private var store: SessionStore!

  override func setUp() {
    super.setUp()
    store = SessionStore()
    manager = PaneNavigationManager()
    manager.activate(store: store)
  }

  override func tearDown() {
    manager.deactivate()
    manager = nil
    store = nil
    super.tearDown()
  }

  func test_handleKeyDown_unmatchedKeyPassesThrough() {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [],
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "a", charactersIgnoringModifiers: "a",
        isARepeat: false, keyCode: 0
      )
    else { return XCTFail("Could not create NSEvent") }

    let result = manager.handleKeyDown(event)
    XCTAssertNotNil(result, "Unmatched key should pass through (return event)")
  }

  func test_handleKeyDown_matchedKeyWithNoPane() {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .control,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "h", charactersIgnoringModifiers: "h",
        isARepeat: false, keyCode: 4
      )
    else { return XCTFail("Could not create NSEvent") }

    let result = manager.handleKeyDown(event)
    XCTAssertNotNil(result, "Matched key with no active pane should pass through")
  }

  func test_handleKeyDown_wrongModifierDoesNotMatch() {
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .command,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "h", charactersIgnoringModifiers: "h",
        isARepeat: false, keyCode: 4
      )
    else { return XCTFail("Could not create NSEvent") }

    let result = manager.handleKeyDown(event)
    XCTAssertNotNil(result, "Wrong modifier should not match navigation binding")
  }

  func test_handleKeyDown_passesThrough_whenPassthroughProcess() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let pane = session.tabs[0].panes[0]
    pane.processTitle = "nvim"

    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .control,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "h", charactersIgnoringModifiers: "h",
        isARepeat: false, keyCode: 4
      )
    else { return XCTFail("Could not create NSEvent") }

    let result = manager.handleKeyDown(event)
    XCTAssertNotNil(result, "Should pass through when running a passthrough process")
  }

  func test_handleKeyDown_passesThrough_whenWindowModeActive() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    session.activeTab?.windowModeState = .normal

    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .control,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "h", charactersIgnoringModifiers: "h",
        isARepeat: false, keyCode: 4
      )
    else { return XCTFail("Could not create NSEvent") }

    let result = manager.handleKeyDown(event)
    XCTAssertNotNil(result, "Should pass through when window mode is active")
  }

  func test_handleKeyDown_matchesCtrlKey_withControlCharacterInCharactersIgnoringModifiers() {
    let session = store.createSession(name: "test", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.tabs[0]
    tab.splitActivePane(direction: .horizontal)

    // Real macOS events have control characters in both characters and
    // charactersIgnoringModifiers when Ctrl is held (Ctrl+H = \u{08}).
    // The fix uses characters(byApplyingModifiers:) which returns "h".
    guard
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: .control,
        timestamp: 0, windowNumber: 0, context: nil,
        characters: "\u{08}", charactersIgnoringModifiers: "\u{08}",
        isARepeat: false, keyCode: 4
      )
    else { return XCTFail("Could not create NSEvent") }

    let result = manager.handleKeyDown(event)
    XCTAssertNil(result, "Ctrl+H should navigate even when charactersIgnoringModifiers returns control character")
  }
}
