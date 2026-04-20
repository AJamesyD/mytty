import XCTest

@testable import Mytty

@MainActor
final class CopyModeManagerTests: XCTestCase {
  private var manager: CopyModeManager!

  override func setUp() {
    super.setUp()
    manager = CopyModeManager()
  }

  override func tearDown() {
    manager = nil
    super.tearDown()
  }

  // MARK: - findMatchOnLine (forward)

  func test_findMatch_forward_findsAfterCursor() {
    let result = manager.findMatchOnLine(
      "hello world hello", query: "hello", cursorCol: 0, forward: true)
    XCTAssertEqual(result, 12)
  }

  func test_findMatch_forward_noMatchAfterCursor() {
    let result = manager.findMatchOnLine("hello world", query: "hello", cursorCol: 0, forward: true)
    XCTAssertNil(result)
  }

  func test_findMatch_forward_matchAtStart() {
    let result = manager.findMatchOnLine(
      "hello world", query: "hello", cursorCol: -1, forward: true)
    XCTAssertEqual(result, 0)
  }

  func test_findMatch_forward_caseInsensitive() {
    let result = manager.findMatchOnLine(
      "Hello World HELLO", query: "hello", cursorCol: 0, forward: true)
    XCTAssertEqual(result, 12)
  }

  func test_findMatch_forward_emptyLine() {
    let result = manager.findMatchOnLine("", query: "hello", cursorCol: 0, forward: true)
    XCTAssertNil(result)
  }

  func test_findMatch_forward_emptyQuery() {
    let result = manager.findMatchOnLine("hello", query: "", cursorCol: 0, forward: true)
    // Empty query is guarded by callers; function returns nil
    XCTAssertNil(result)
  }

  func test_findMatch_forward_noMatch() {
    let result = manager.findMatchOnLine("hello world", query: "xyz", cursorCol: 0, forward: true)
    XCTAssertNil(result)
  }

  // MARK: - findMatchOnLine (reverse)

  func test_findMatch_reverse_findsBeforeCursor() {
    let result = manager.findMatchOnLine(
      "hello world hello", query: "hello", cursorCol: 12, forward: false)
    XCTAssertEqual(result, 0)
  }

  func test_findMatch_reverse_noMatchBeforeCursor() {
    let result = manager.findMatchOnLine(
      "hello world", query: "hello", cursorCol: 0, forward: false)
    XCTAssertNil(result)
  }

  func test_findMatch_reverse_multipleMatches() {
    let result = manager.findMatchOnLine(
      "aaa bbb aaa bbb aaa", query: "aaa", cursorCol: 16, forward: false)
    XCTAssertEqual(result, 8)
  }

  func test_findMatch_reverse_caseInsensitive() {
    let result = manager.findMatchOnLine(
      "HELLO world", query: "hello", cursorCol: 6, forward: false)
    XCTAssertEqual(result, 0)
  }

  func test_findMatch_reverse_emptyLine() {
    let result = manager.findMatchOnLine("", query: "hello", cursorCol: 5, forward: false)
    XCTAssertNil(result)
  }

  // MARK: - Edge cases

  func test_findMatch_forward_adjacentMatches() {
    let result = manager.findMatchOnLine("aaaa", query: "aa", cursorCol: 0, forward: true)
    XCTAssertEqual(result, 2)
  }

  func test_findMatch_forward_matchAtEndOfLine() {
    let result = manager.findMatchOnLine("world hello", query: "hello", cursorCol: 0, forward: true)
    XCTAssertEqual(result, 6)
  }

  func test_findMatch_reverse_cursorAtEnd() {
    let result = manager.findMatchOnLine(
      "hello world", query: "world", cursorCol: Int.max, forward: false)
    XCTAssertEqual(result, 6)
  }

  func test_findMatch_forward_unicode() {
    let result = manager.findMatchOnLine("日本語hello世界", query: "hello", cursorCol: 0, forward: true)
    XCTAssertEqual(result, 3)
  }
}
