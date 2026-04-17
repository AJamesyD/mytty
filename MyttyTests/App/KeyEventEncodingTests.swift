import AppKit
import GhosttyKit
import Testing

@testable import Mytty

struct KeyEventEncodingTests {

  private func makeKeyDown(keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent? {
    let cgEvent = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true)
    cgEvent?.flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
    guard let cg = cgEvent else { return nil }
    return NSEvent(cgEvent: cg)
  }

  // MARK: - ghosttyMods

  @Test func testGhosttyModsShift() {
    #expect(ghosttyMods(.shift) == GHOSTTY_MODS_SHIFT)
  }

  @Test func testGhosttyModsControl() {
    #expect(ghosttyMods(.control) == GHOSTTY_MODS_CTRL)
  }

  @Test func testGhosttyModsOption() {
    #expect(ghosttyMods(.option) == GHOSTTY_MODS_ALT)
  }

  @Test func testGhosttyModsCommand() {
    #expect(ghosttyMods(.command) == GHOSTTY_MODS_SUPER)
  }

  @Test func testGhosttyModsCapsLock() {
    #expect(ghosttyMods(.capsLock) == GHOSTTY_MODS_CAPS)
  }

  @Test func testGhosttyModsCombination() {
    let expected = ghostty_input_mods_e(
      rawValue: GHOSTTY_MODS_SHIFT.rawValue | GHOSTTY_MODS_CTRL.rawValue)
    #expect(ghosttyMods([.shift, .control]) == expected)
  }

  @Test func testGhosttyModsEmpty() {
    #expect(ghosttyMods([]).rawValue == 0)
  }

  // MARK: - consumed_mods contract

  @Test func testConsumedModsShiftedCharacter() throws {
    let event = try #require(makeKeyDown(keyCode: 41, modifiers: .shift))
    let key = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
    #expect(key.consumed_mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0)
  }

  @Test func testConsumedModsPlainCharacter() throws {
    let event = try #require(makeKeyDown(keyCode: 9))
    let key = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
    #expect(key.consumed_mods.rawValue == 0)
  }

  @Test func testConsumedModsControlNotConsumed() throws {
    let event = try #require(makeKeyDown(keyCode: 8, modifiers: .control))
    let key = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
    #expect(key.consumed_mods.rawValue & GHOSTTY_MODS_CTRL.rawValue == 0)
  }

  @Test func testConsumedModsCommandNotConsumed() throws {
    let event = try #require(makeKeyDown(keyCode: 17, modifiers: .command))
    let key = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
    #expect(key.consumed_mods.rawValue & GHOSTTY_MODS_SUPER.rawValue == 0)
  }

  @Test func testConsumedModsOptionConsumed() throws {
    let event = try #require(makeKeyDown(keyCode: 0, modifiers: .option))
    let key = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
    #expect(key.consumed_mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
  }

  // MARK: - keycodeNames

  @Test func testKeycodeNamesKnownKeys() {
    #expect(NSEvent.keycodeNames[53] == "escape")
    #expect(NSEvent.keycodeNames[36] == "return")
    #expect(NSEvent.keycodeNames[48] == "tab")
  }

  @Test func testKeycodeNamesUnknownKey() {
    #expect(NSEvent.keycodeNames[255] == nil)
  }

  // MARK: - keyboardTriggerModifiers

  @Test func testKeyboardTriggerModifiersShift() throws {
    let event = try #require(makeKeyDown(keyCode: 0, modifiers: .shift))
    #expect(event.keyboardTriggerModifiers.contains(.shift))
  }

  @Test func testKeyboardTriggerModifiersMultiple() throws {
    let event = try #require(makeKeyDown(keyCode: 0, modifiers: [.command, .shift]))
    #expect(event.keyboardTriggerModifiers.contains(.cmd))
    #expect(event.keyboardTriggerModifiers.contains(.shift))
  }
}
