import SwiftUI
import XCTest

@testable import Mytty

final class TriggerParserTests: XCTestCase {
  func test_simpleModifierAndKey() throws {
    let trigger = try TriggerParser.parse("cmd+d")
    XCTAssertNil(trigger.prefix)
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "d")
  }

  func test_multipleModifiers() throws {
    let trigger = try TriggerParser.parse("ctrl+shift+h")
    XCTAssertEqual(trigger.modifiers, [.ctrl, .shift])
    XCTAssertEqual(trigger.key, "h")
  }

  func test_prefixUnconsumed() throws {
    let trigger = try TriggerParser.parse("unconsumed:ctrl+h")
    XCTAssertEqual(trigger.prefix, .unconsumed)
    XCTAssertEqual(trigger.modifiers, [.ctrl])
    XCTAssertEqual(trigger.key, "h")
  }

  func test_bareKey() throws {
    let trigger = try TriggerParser.parse("escape")
    XCTAssertNil(trigger.prefix)
    XCTAssertEqual(trigger.modifiers, [])
    XCTAssertEqual(trigger.key, "escape")
  }

  func test_shiftAndKey() throws {
    let trigger = try TriggerParser.parse("shift+g")
    XCTAssertEqual(trigger.modifiers, [.shift])
    XCTAssertEqual(trigger.key, "g")
  }

  func test_multiCharacterKey_gg() throws {
    let trigger = try TriggerParser.parse("gg")
    XCTAssertEqual(trigger.modifiers, [])
    XCTAssertEqual(trigger.key, "gg")
  }

  func test_multiCharacterKey_ge() throws {
    let trigger = try TriggerParser.parse("ge")
    XCTAssertEqual(trigger.modifiers, [])
    XCTAssertEqual(trigger.key, "ge")
  }

  func test_multiCharacterKey_gQuestion() throws {
    let trigger = try TriggerParser.parse("g?")
    XCTAssertEqual(trigger.modifiers, [])
    XCTAssertEqual(trigger.key, "g?")
  }

  func test_plusKey() throws {
    let trigger = try TriggerParser.parse("cmd++")
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "+")
  }

  func test_minusKey() throws {
    let trigger = try TriggerParser.parse("cmd+-")
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "-")
  }

  func test_bracketKey() throws {
    let trigger = try TriggerParser.parse("cmd+]")
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "]")
  }

  func test_spaceKey() throws {
    let trigger = try TriggerParser.parse("ctrl+space")
    XCTAssertEqual(trigger.modifiers, [.ctrl])
    XCTAssertEqual(trigger.key, "space")
  }

  func test_aliasCommand() throws {
    let trigger = try TriggerParser.parse("command+d")
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "d")
  }

  func test_aliasSuper() throws {
    let trigger = try TriggerParser.parse("super+d")
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "d")
  }

  func test_aliasControl() throws {
    let trigger = try TriggerParser.parse("control+h")
    XCTAssertEqual(trigger.modifiers, [.ctrl])
    XCTAssertEqual(trigger.key, "h")
  }

  func test_aliasOption() throws {
    let trigger = try TriggerParser.parse("option+a")
    XCTAssertEqual(trigger.modifiers, [.alt])
    XCTAssertEqual(trigger.key, "a")
  }

  func test_aliasOpt() throws {
    let trigger = try TriggerParser.parse("opt+a")
    XCTAssertEqual(trigger.modifiers, [.alt])
    XCTAssertEqual(trigger.key, "a")
  }

  func test_caseInsensitive() throws {
    let trigger = try TriggerParser.parse("CMD+D")
    XCTAssertEqual(trigger.modifiers, [.cmd])
    XCTAssertEqual(trigger.key, "d")
  }

  func test_emptyThrows() {
    XCTAssertThrowsError(try TriggerParser.parse("")) { error in
      XCTAssertEqual(error as? TriggerParseError, .empty)
    }
  }

  func test_unbindThrows() {
    XCTAssertThrowsError(try TriggerParser.parse("unbind")) { error in
      XCTAssertEqual(error as? TriggerParseError, .reservedKeyword("unbind"))
    }
  }

  func test_unknownPrefixThrows() {
    XCTAssertThrowsError(try TriggerParser.parse("foo:ctrl+h")) { error in
      XCTAssertEqual(error as? TriggerParseError, .unknownPrefix("foo"))
    }
  }

  func test_unknownModifierThrows() {
    XCTAssertThrowsError(try TriggerParser.parse("blah+d")) { error in
      XCTAssertEqual(error as? TriggerParseError, .unknownModifier("blah"))
    }
  }

  func test_normalizeAlphabeticalModifiers() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [.shift, .cmd, .ctrl], key: "d")
    XCTAssertEqual(TriggerParser.normalize(trigger), "cmd+ctrl+shift+d")
  }

  func test_normalizeWithPrefix() throws {
    let trigger = try TriggerParser.parse("unconsumed:ctrl+h")
    XCTAssertEqual(TriggerParser.normalize(trigger), "unconsumed:ctrl+h")
  }

  func test_toKeyboardShortcut_singleCharKey() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "t")
    XCTAssertNotNil(trigger.toKeyboardShortcut())
  }

  func test_toKeyboardShortcut_specialKey_upArrow() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "up")
    XCTAssertNotNil(trigger.toKeyboardShortcut())
  }

  func test_toKeyboardShortcut_specialKey_escape() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [], key: "escape")
    XCTAssertNotNil(trigger.toKeyboardShortcut())
  }

  func test_toKeyboardShortcut_specialKey_space() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "space")
    XCTAssertNotNil(trigger.toKeyboardShortcut())
  }

  func test_toKeyboardShortcut_unconsumedReturnsNil() {
    let trigger = KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "h")
    XCTAssertNil(trigger.toKeyboardShortcut())
  }

  func test_toKeyboardShortcut_multiCharKeyReturnsNil() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [], key: "gg")
    XCTAssertNil(trigger.toKeyboardShortcut())
  }

  func test_toKeyboardShortcut_noModifiers() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [], key: "z")
    XCTAssertNotNil(trigger.toKeyboardShortcut())
  }
}
