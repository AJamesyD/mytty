import XCTest

@testable import Mistty

final class KeySequenceParsingTests: XCTestCase {
  func test_singleKeySequence() throws {
    let seq = try TriggerParser.parseSequence("cmd+t")
    XCTAssertNil(seq.prefix)
    XCTAssertEqual(seq.triggers.count, 1)
    XCTAssertEqual(
      seq.triggers[0],
      KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "t")
    )
  }

  func test_twoKeySequence() throws {
    let seq = try TriggerParser.parseSequence("ctrl+a>h")
    XCTAssertNil(seq.prefix)
    XCTAssertEqual(seq.triggers.count, 2)
    XCTAssertEqual(
      seq.triggers[0],
      KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
    )
    XCTAssertEqual(
      seq.triggers[1],
      KeyboardTrigger(prefix: nil, modifiers: [], key: "h")
    )
  }

  func test_threeKeySequence() throws {
    let seq = try TriggerParser.parseSequence("ctrl+a>g>s")
    XCTAssertEqual(seq.triggers.count, 3)
  }

  func test_unconsumedPrefix() throws {
    let seq = try TriggerParser.parseSequence("unconsumed:ctrl+a>h")
    XCTAssertEqual(seq.prefix, .unconsumed)
    XCTAssertEqual(seq.triggers.count, 2)
    XCTAssertNil(seq.triggers[0].prefix)
    XCTAssertEqual(seq.triggers[0].modifiers, [.ctrl])
    XCTAssertEqual(seq.triggers[0].key, "a")
  }

  func test_sequenceTooDeep() {
    XCTAssertThrowsError(try TriggerParser.parseSequence("a>b>c>d>e>f")) { error in
      XCTAssertEqual(error as? TriggerParseError, .sequenceTooDeep(6))
    }
  }

  func test_emptySegment() {
    XCTAssertThrowsError(try TriggerParser.parseSequence("ctrl+a>>h")) { error in
      XCTAssertEqual(error as? TriggerParseError, .empty)
    }
  }

  func test_emptyInput() {
    XCTAssertThrowsError(try TriggerParser.parseSequence("")) { error in
      XCTAssertEqual(error as? TriggerParseError, .empty)
    }
  }

  func test_normalizeSequence() {
    let seq = KeySequence(
      prefix: nil,
      triggers: [
        KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a"),
        KeyboardTrigger(prefix: nil, modifiers: [], key: "h"),
      ])
    XCTAssertEqual(TriggerParser.normalizeSequence(seq), "ctrl+a>h")
  }

  func test_normalizeSequenceWithPrefix() {
    let seq = KeySequence(
      prefix: .unconsumed,
      triggers: [
        KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a"),
        KeyboardTrigger(prefix: nil, modifiers: [], key: "h"),
      ])
    XCTAssertEqual(TriggerParser.normalizeSequence(seq), "unconsumed:ctrl+a>h")
  }

  func test_maxDepthAllowed() throws {
    let seq = try TriggerParser.parseSequence("a>b>c>d>e")
    XCTAssertEqual(seq.triggers.count, 5)
  }

  func test_modifiersOnSecondKey() throws {
    let seq = try TriggerParser.parseSequence("ctrl+a>ctrl+b")
    XCTAssertEqual(seq.triggers[1].modifiers, [.ctrl])
    XCTAssertEqual(seq.triggers[1].key, "b")
  }
}
