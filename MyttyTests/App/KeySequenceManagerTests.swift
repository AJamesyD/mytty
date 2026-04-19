// Force-unwrap is idiomatic in tests (XCTUnwrap for failable, ! for known-good fixtures).
// SwiftLint lacks per-directory rule exclusions, so blanket disable is the only option.
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable force_unwrapping
import XCTest

@testable import Mytty

@MainActor
final class KeySequenceManagerTests: XCTestCase {
  private var manager: KeySequenceManager!
  private var dispatched: [String]!

  override func setUp() {
    super.setUp()
    manager = KeySequenceManager()
    dispatched = []
  }

  override func tearDown() {
    manager.deactivate()
    manager = nil
    dispatched = nil
    super.tearDown()
  }

  // MARK: - Helpers

  private func activateWithTrie(_ trie: SequenceTrieNode, timeout: TimeInterval = 1.0) {
    manager.activate(
      trie: trie,
      timeout: timeout,
      dispatch: { [self] action in dispatched.append(action) },
      surfaceForUnconsumed: { nil }
    )
  }

  private func makeTwoKeyTrie() -> SequenceTrieNode {
    let hLeaf = SequenceTrieNode(children: [:], action: "navigate-left")
    let lLeaf = SequenceTrieNode(children: [:], action: "navigate-right")
    let hKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "h")
    let lKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "l")
    let leaderChild = SequenceTrieNode(children: [hKey: hLeaf, lKey: lLeaf])
    let leader = KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
    return SequenceTrieNode(children: [leader: leaderChild])
  }

  private func makeThreeKeyTrie() -> SequenceTrieNode {
    let sLeaf = SequenceTrieNode(children: [:], action: "toggle-sidebar")
    let sKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "s")
    let gChild = SequenceTrieNode(children: [sKey: sLeaf])
    let gKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "g")
    let leaderChild = SequenceTrieNode(children: [gKey: gChild])
    let leader = KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
    return SequenceTrieNode(children: [leader: leaderChild])
  }

  private func keyEvent(key: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [])
    -> NSEvent {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers,
      timestamp: 0, windowNumber: 0, context: nil,
      characters: key, charactersIgnoringModifiers: key,
      isARepeat: false, keyCode: code
    )!
  }

  // MARK: - Tests

  func test_idleUnmatchedKeyPassesThrough() {
    activateWithTrie(makeTwoKeyTrie())
    let result = manager.handleKeyDown(keyEvent(key: "x", code: 7))
    XCTAssertNotNil(result, "Unmatched key should pass through")
    XCTAssertTrue(dispatched.isEmpty)
  }

  func test_leaderKeyConsumed() {
    activateWithTrie(makeTwoKeyTrie())
    let result = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    XCTAssertNil(result, "Leader key should be consumed")
    XCTAssertFalse(manager.pendingDisplay.isEmpty)
    XCTAssertTrue(dispatched.isEmpty)
  }

  func test_fullSequenceDispatches() {
    activateWithTrie(makeTwoKeyTrie())
    let r1 = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    let r2 = manager.handleKeyDown(keyEvent(key: "h", code: 4))
    XCTAssertNil(r1)
    XCTAssertNil(r2)
    XCTAssertEqual(dispatched, ["navigate-left"])
    XCTAssertTrue(manager.pendingDisplay.isEmpty)
  }

  func test_invalidKeyAfterLeaderCancels() {
    activateWithTrie(makeTwoKeyTrie())
    let r1 = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    let r2 = manager.handleKeyDown(keyEvent(key: "x", code: 7))
    XCTAssertNil(r1)
    XCTAssertNil(r2)
    XCTAssertTrue(dispatched.isEmpty)
    XCTAssertTrue(manager.pendingDisplay.isEmpty)
  }

  func test_escapeCancel() {
    activateWithTrie(makeTwoKeyTrie())
    let r1 = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    let r2 = manager.handleKeyDown(keyEvent(key: "\u{1B}", code: 53))
    XCTAssertNil(r1)
    XCTAssertNil(r2)
    XCTAssertTrue(dispatched.isEmpty)
    XCTAssertTrue(manager.pendingDisplay.isEmpty)
  }

  func test_modifierOnlyKeyIgnored() {
    activateWithTrie(makeTwoKeyTrie())
    let r1 = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    XCTAssertNil(r1)

    let modOnly = manager.handleKeyDown(keyEvent(key: "", code: 59, modifiers: .control))
    XCTAssertNotNil(modOnly, "Modifier-only event should pass through")
    XCTAssertFalse(manager.pendingDisplay.isEmpty, "Should still be pending")

    let r3 = manager.handleKeyDown(keyEvent(key: "h", code: 4))
    XCTAssertNil(r3)
    XCTAssertEqual(dispatched, ["navigate-left"])
  }

  func test_emptyTriePassesThrough() {
    activateWithTrie(SequenceTrieNode())
    let result = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    XCTAssertNotNil(result, "Empty trie should pass all keys through")
  }

  func test_pendingDisplayFormat() {
    activateWithTrie(makeTwoKeyTrie())
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    XCTAssertEqual(manager.pendingDisplay, "ctrl+a ...")
  }

  func test_deactivateCancelsPending() {
    activateWithTrie(makeTwoKeyTrie())
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    manager.deactivate()
    XCTAssertTrue(manager.pendingDisplay.isEmpty)
  }

  func test_reloadConfigCancelsPending() {
    activateWithTrie(makeTwoKeyTrie())
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    manager.reloadConfig(trie: SequenceTrieNode(), timeout: 1.0)
    XCTAssertTrue(manager.pendingDisplay.isEmpty)
  }

  func test_threeKeySequence() {
    activateWithTrie(makeThreeKeyTrie())
    let r1 = manager.handleKeyDown(keyEvent(key: "a", code: 0, modifiers: .control))
    let r2 = manager.handleKeyDown(keyEvent(key: "g", code: 5))
    let r3 = manager.handleKeyDown(keyEvent(key: "s", code: 1))
    XCTAssertNil(r1)
    XCTAssertNil(r2)
    XCTAssertNil(r3)
    XCTAssertEqual(dispatched, ["toggle-sidebar"])
  }
}
