// Force-unwrap is idiomatic in tests (XCTUnwrap for failable, ! for known-good fixtures).
// SwiftLint lacks per-directory rule exclusions, so blanket disable is the only option.
// swiftlint:disable:next blanket_disable_command
// swiftlint:disable force_unwrapping
import AppKit
import XCTest

@testable import Mytty

@MainActor
final class HintsModeManagerTests: XCTestCase {
  private var manager: HintsModeManager!

  override func setUp() {
    super.setUp()
    manager = HintsModeManager()
  }

  override func tearDown() {
    manager.deactivate()
    manager = nil
    super.tearDown()
  }

  // MARK: - Helpers

  private let defaultGeometry = HintsGeometry.terminal(
    rows: 1, cols: 80, cellWidth: 8, cellHeight: 16, offsetX: 0, offsetY: 0)

  private func makeTargets(count: Int, matchType: TerminalMatchType = .url) -> [any HintTarget] {
    (0..<count).map { i in
      TerminalHintTarget(
        id: "t\(i)", labelOrigin: .zero,
        displayText: matchType == .url ? "not a url \(i)" : "target-\(i)",
        matchType: matchType, row: 0, colRange: i..<(i + 1))
    }
  }

  private func keyEvent(key: String, code: UInt16, modifiers: NSEvent.ModifierFlags = [])
    -> NSEvent
  {
    NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: modifiers,
      timestamp: 0, windowNumber: 0, context: nil,
      characters: key, charactersIgnoringModifiers: key,
      isARepeat: false, keyCode: code
    )!
  }

  // MARK: - Inactive

  func test_handleKeyDown_inactive_passesThrough() {
    let event = keyEvent(key: "a", code: 0)
    let result = manager.handleKeyDown(event)
    XCTAssertNotNil(result, "Inactive manager should pass events through")
  }

  // MARK: - Activate

  func test_activate_setsActiveState() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 3))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    XCTAssertTrue(manager.isActive)
    guard case .active(let labels, let typed) = manager.state else {
      return XCTFail("Expected .active state")
    }
    XCTAssertEqual(labels.count, 3)
    XCTAssertEqual(typed, "")
  }

  func test_activate_zeroTargets_activeWithEmptyLabels() {
    let provider = MockHintTargetProvider(mockTargets: [])
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    XCTAssertTrue(manager.isActive)
    guard case .active(let labels, _) = manager.state else {
      return XCTFail("Expected .active state")
    }
    XCTAssertTrue(labels.isEmpty)
  }

  func test_zeroTargets_keystrokeDeactivates() {
    let provider = MockHintTargetProvider(mockTargets: [])
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0))

    XCTAssertFalse(manager.isActive, "Keystroke with zero labels should deactivate")
  }

  // MARK: - Escape

  func test_escape_deactivates() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 3))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    let result = manager.handleKeyDown(keyEvent(key: "\u{1B}", code: 53))

    XCTAssertNil(result, "Escape should be consumed")
    XCTAssertFalse(manager.isActive)
  }

  // alphabet "ab" -> 4 targets get two-char labels: aa, ab, ba, bb
  func test_escape_inFiltering_deactivates() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 4))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "ab")
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0))
    guard case .filtering = manager.state else {
      return XCTFail("Expected .filtering state after first key")
    }

    let result = manager.handleKeyDown(keyEvent(key: "\u{1B}", code: 53))

    XCTAssertNil(result)
    XCTAssertFalse(manager.isActive)
  }

  // MARK: - Single-char label selection

  // alphabet "asd" -> deduped ['a','s','d'], 3 targets get single-char labels
  func test_alphabetKey_singleCharLabel_selectsAndDeactivates() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 3))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    let result = manager.handleKeyDown(keyEvent(key: "a", code: 0))

    XCTAssertNil(result, "Alphabet key should be consumed")
    XCTAssertFalse(manager.isActive, "Should deactivate after unique match")
  }

  // MARK: - Two-char label filtering

  // alphabet "ab" -> 4 targets get: aa, ab, ba, bb
  func test_alphabetKey_twoCharLabel_transitionsToFiltering() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 4))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "ab")

    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0))

    guard case .filtering(_, let typed, let remaining) = manager.state else {
      return XCTFail("Expected .filtering state")
    }
    XCTAssertEqual(typed, "a")
    // "aa" and "ab" match prefix "a"
    XCTAssertEqual(remaining.count, 2)
  }

  func test_filtering_secondKey_selectsTarget() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 4))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "ab")
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0))

    let result = manager.handleKeyDown(keyEvent(key: "b", code: 11))

    XCTAssertNil(result)
    XCTAssertFalse(manager.isActive, "Should deactivate after selecting 'ab'")
  }

  // alphabet "abc" deduped -> ['a','b','c']. 4 targets -> two-char labels: aa, ab, ac, ba.
  // No label starts with 'c', so typing 'c' produces no match -> deactivates.
  func test_filtering_noMatch_deactivates() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 4))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "abc")

    _ = manager.handleKeyDown(keyEvent(key: "c", code: 8))

    XCTAssertFalse(manager.isActive, "No-match should deactivate")
  }

  // MARK: - Backspace

  func test_backspace_inFiltering_revertsToActive() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 4))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "ab")
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0))
    guard case .filtering = manager.state else {
      return XCTFail("Expected .filtering")
    }

    let result = manager.handleKeyDown(keyEvent(key: "\u{7F}", code: 51))

    XCTAssertNil(result, "Backspace should be consumed")
    guard case .active(_, let typed) = manager.state else {
      return XCTFail("Expected .active after backspace")
    }
    XCTAssertEqual(typed, "")
  }

  func test_backspace_inActive_consumed() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 4))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "ab")

    let result = manager.handleKeyDown(keyEvent(key: "\u{7F}", code: 51))

    XCTAssertNil(result, "Backspace should be consumed even in active state")
    guard case .active = manager.state else {
      return XCTFail("Expected state to remain .active")
    }
  }

  // MARK: - Non-alphabet key

  func test_nonAlphabetKey_consumed() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 3))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    let result = manager.handleKeyDown(keyEvent(key: "z", code: 6))

    XCTAssertNil(result, "Non-alphabet key should be consumed when active")
    XCTAssertTrue(manager.isActive, "State should not change")
  }

  func test_modifierOnlyKey_consumed() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 3))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    // Modifier-only event has nil charactersIgnoringModifiers
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: .shift,
      timestamp: 0, windowNumber: 0, context: nil,
      characters: "", charactersIgnoringModifiers: "",
      isARepeat: false, keyCode: 56
    )!
    let result = manager.handleKeyDown(event)

    XCTAssertNil(result, "Modifier-only key should be consumed when active")
    XCTAssertTrue(manager.isActive, "State should not change")
  }

  func test_multiCharInput_usesFirstCharOnly() {
    let provider = MockHintTargetProvider(mockTargets: makeTargets(count: 3))
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    // Simulate IME producing multi-char string
    let event = NSEvent.keyEvent(
      with: .keyDown, location: .zero, modifierFlags: [],
      timestamp: 0, windowNumber: 0, context: nil,
      characters: "as", charactersIgnoringModifiers: "as",
      isARepeat: false, keyCode: 0
    )!
    _ = manager.handleKeyDown(event)

    // Should select target with label "a" (first char), not match "as" as substring
    XCTAssertFalse(manager.isActive, "Should select single-char label 'a' using first char")
  }

  // MARK: - Modifier resolution

  func test_shiftModifier_resolvesOpenAction() {
    let target = TerminalHintTarget(
      id: "t0", labelOrigin: .zero, displayText: "https://example.com",
      matchType: .url, row: 0, colRange: 0..<1)
    let label = HintLabel(target: target, label: "a")

    let action = manager.resolveAction(for: label, modifiers: .shift)

    XCTAssertEqual(action, .open)
  }

  func test_ctrlModifier_resolvesPasteAction() {
    let target = TerminalHintTarget(
      id: "t0", labelOrigin: .zero, displayText: "https://example.com",
      matchType: .url, row: 0, colRange: 0..<1)
    let label = HintLabel(target: target, label: "a")

    let action = manager.resolveAction(for: label, modifiers: .control)

    XCTAssertEqual(action, .paste)
  }

  func test_noModifier_resolvesDefaultAction() {
    let target = TerminalHintTarget(
      id: "t0", labelOrigin: .zero, displayText: "https://example.com",
      matchType: .url, row: 0, colRange: 0..<1)
    let label = HintLabel(target: target, label: "a")

    let action = manager.resolveAction(for: label, modifiers: [])

    XCTAssertEqual(action, .copy)
  }

  // MARK: - Copy action pasteboard

  func test_copyAction_putsTextOnPasteboard() {
    let targets = makeTargets(count: 3, matchType: .url)
    let provider = MockHintTargetProvider(mockTargets: targets)
    manager.activate(provider: provider, geometry: defaultGeometry, alphabet: "asd")

    NSPasteboard.general.clearContents()
    _ = manager.handleKeyDown(keyEvent(key: "a", code: 0))

    let pasteboardString = NSPasteboard.general.string(forType: .string)
    XCTAssertEqual(pasteboardString, "not a url 0")
  }
}

// MARK: - Mock

private struct MockHintTargetProvider: HintTargetProvider {
  let providerID = "mock"
  let mockTargets: [any HintTarget]
  func targets(in geometry: HintsGeometry) -> [any HintTarget] { mockTargets }
}
