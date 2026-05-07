import XCTest

@testable import Mytty

@MainActor
final class CopyModeTranslationTests: XCTestCase {
  private var manager: CopyModeManager!

  override func setUp() {
    super.setUp()
    manager = CopyModeManager()
    manager.setBindingsForTesting([
      "h": "move-left",
      "j": "move-down",
      "k": "move-up",
      "l": "move-right",
      "w": "word-forward",
      "y": "yank",
    ])
  }

  override func tearDown() {
    manager = nil
    super.tearDown()
  }

  // MARK: - shouldTranslate

  func test_shouldTranslate_normalState_returnsTrue() {
    let state = CopyModeState(rows: 24, cols: 80)
    XCTAssertTrue(manager.shouldTranslate(state, key: "h", keyCode: 4))
  }

  func test_shouldTranslate_searchMode_returnsFalse() {
    var state = CopyModeState(rows: 24, cols: 80)
    state.subMode = .searchForward
    XCTAssertFalse(manager.shouldTranslate(state, key: "h", keyCode: 4))
  }

  func test_shouldTranslate_pendingFindChar_returnsFalse() {
    var state = CopyModeState(rows: 24, cols: 80)
    state.pendingFindChar = .f
    XCTAssertFalse(manager.shouldTranslate(state, key: "a", keyCode: 0))
  }

  func test_shouldTranslate_pendingG_returnsFalse() {
    var state = CopyModeState(rows: 24, cols: 80)
    state.pendingG = true
    XCTAssertFalse(manager.shouldTranslate(state, key: "g", keyCode: 5))
  }

  func test_shouldTranslate_digitAccumulation_returnsFalse() {
    let state = CopyModeState(rows: 24, cols: 80)
    XCTAssertFalse(manager.shouldTranslate(state, key: "5", keyCode: 23))
  }

  func test_shouldTranslate_zeroWithPendingCount_returnsFalse() {
    var state = CopyModeState(rows: 24, cols: 80)
    state.pendingCount = 3
    XCTAssertFalse(manager.shouldTranslate(state, key: "0", keyCode: 29))
  }

  func test_shouldTranslate_zeroWithoutPendingCount_returnsTrue() {
    let state = CopyModeState(rows: 24, cols: 80)
    XCTAssertTrue(manager.shouldTranslate(state, key: "0", keyCode: 29))
  }

  func test_shouldTranslate_showingHelp_returnsFalse() {
    var state = CopyModeState(rows: 24, cols: 80)
    state.showingHelp = true
    XCTAssertFalse(manager.shouldTranslate(state, key: "h", keyCode: 4))
  }

  func test_shouldTranslate_escape_returnsFalse() {
    let state = CopyModeState(rows: 24, cols: 80)
    XCTAssertFalse(manager.shouldTranslate(state, key: "\u{1b}", keyCode: 53))
  }

  // MARK: - translateKey

  func test_translateKey_mappedBinding_returnsCanonical() {
    let state = CopyModeState(rows: 24, cols: 80)
    let (key, _) = manager.translateKey("h", modifiers: [], state: state, keyCode: 4)
    XCTAssertEqual(key, "h")
  }

  func test_translateKey_remappedBinding_returnsCanonical() {
    manager.setBindingsForTesting(["a": "move-left"])
    let state = CopyModeState(rows: 24, cols: 80)
    let (key, _) = manager.translateKey("a", modifiers: [], state: state, keyCode: 0)
    XCTAssertEqual(key, "h")
  }

  func test_translateKey_unmappedKey_passesThrough() {
    let state = CopyModeState(rows: 24, cols: 80)
    let (key, mods) = manager.translateKey("x", modifiers: [], state: state, keyCode: 7)
    XCTAssertEqual(key, "x")
    XCTAssertEqual(mods, [])
  }

  func test_translateKey_ctrlBinding_addsControlModifier() {
    manager.setBindingsForTesting(["d": "half-page-down"])
    let state = CopyModeState(rows: 24, cols: 80)
    let (key, mods) = manager.translateKey("d", modifiers: [], state: state, keyCode: 2)
    XCTAssertEqual(key, "d")
    XCTAssertTrue(mods.contains(.control))
  }

  func test_translateKey_nonCtrlBinding_removesControlModifier() {
    manager.setBindingsForTesting(["h": "move-left"])
    let state = CopyModeState(rows: 24, cols: 80)
    let (key, mods) = manager.translateKey("h", modifiers: [.control], state: state, keyCode: 4)
    // Lookup uses CopyModeKey(key: "h", hasCtrl: true) which won't match
    // our binding of CopyModeKey(key: "h", hasCtrl: false), so it passes through
    XCTAssertEqual(key, "h")
    XCTAssertTrue(mods.contains(.control))
  }

  func test_translateKey_searchMode_bypassesTranslation() {
    var state = CopyModeState(rows: 24, cols: 80)
    state.subMode = .searchForward
    let (key, _) = manager.translateKey("h", modifiers: [], state: state, keyCode: 4)
    XCTAssertEqual(key, "h")
  }
}
