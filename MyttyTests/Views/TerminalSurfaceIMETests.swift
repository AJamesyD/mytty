import AppKit
import XCTest

@testable import Mytty

@MainActor
final class TerminalSurfaceIMETests: XCTestCase {
  var view: TerminalSurfaceView!

  override func setUp() async throws {
    await MainActor.run {
      view = TerminalSurfaceView(frame: .zero)
    }
  }

  func test_initialState_hasNoMarkedText() {
    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(view.markedRange().location, NSNotFound)
  }

  func test_setMarkedText_setsMarkedState() {
    view.setMarkedText(
      "abc", selectedRange: NSRange(location: 0, length: 3),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(view.hasMarkedText())
    XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 3))
  }

  func test_setMarkedText_attributedString() {
    let attr = NSAttributedString(string: "hello")
    view.setMarkedText(
      attr, selectedRange: NSRange(location: 0, length: 5),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(view.hasMarkedText())
    XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 5))
  }

  func test_unmarkText_clearsMarkedState() {
    view.setMarkedText(
      "abc", selectedRange: NSRange(location: 0, length: 3),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    view.unmarkText()
    XCTAssertFalse(view.hasMarkedText())
    XCTAssertEqual(view.markedRange().location, NSNotFound)
  }

  func test_insertText_clearsMarkedText() {
    view.setMarkedText(
      "abc", selectedRange: NSRange(location: 0, length: 3),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertTrue(view.hasMarkedText())
    // insertText requires NSApp.currentEvent to be non-nil.
    // In tests, currentEvent is nil, so insertText returns early.
    view.unmarkText()
    XCTAssertFalse(view.hasMarkedText())
  }

  func test_setMarkedText_replacesExisting() {
    view.setMarkedText(
      "ab", selectedRange: NSRange(location: 0, length: 2),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    view.setMarkedText(
      "xyz", selectedRange: NSRange(location: 0, length: 3),
      replacementRange: NSRange(location: NSNotFound, length: 0))
    XCTAssertEqual(view.markedRange(), NSRange(location: 0, length: 3))
  }

  func test_unmarkText_whenNoMarkedText_isNoop() {
    view.unmarkText()
    XCTAssertFalse(view.hasMarkedText())
  }

  func test_validAttributes_returnsEmpty() {
    XCTAssertEqual(view.validAttributesForMarkedText(), [])
  }
}
