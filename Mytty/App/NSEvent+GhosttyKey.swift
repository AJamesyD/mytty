// Transliteration of Ghostty's NSEvent+Extension.swift for Mytty's key encoding needs.
import AppKit
import GhosttyKit

func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
  var raw: UInt32 = 0
  if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
  if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
  if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
  if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
  if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
  return ghostty_input_mods_e(rawValue: raw)
}

extension NSEvent {
  func ghosttyKeyEvent(_ action: ghostty_input_action_e) -> ghostty_input_key_s {
    var key = ghostty_input_key_s()
    key.action = action
    key.keycode = UInt32(keyCode)
    key.mods = ghosttyMods(modifierFlags)
    key.consumed_mods = ghosttyMods(modifierFlags.subtracting([.control, .command]))
    key.text = nil
    key.composing = false
    key.unshifted_codepoint = 0
    if type == .keyDown || type == .keyUp {
      if let chars = characters(byApplyingModifiers: []),
        let codepoint = chars.unicodeScalars.first
      {
        key.unshifted_codepoint = codepoint.value
      }
    }
    return key
  }

  var keyName: String? {
    if let name = Self.keycodeNames[keyCode] {
      return name
    }
    return characters(byApplyingModifiers: [])?.lowercased()
  }

  var keyboardTriggerModifiers: Set<KeyboardTrigger.Modifier> {
    var mods: Set<KeyboardTrigger.Modifier> = []
    if modifierFlags.contains(.command) { mods.insert(.cmd) }
    if modifierFlags.contains(.control) { mods.insert(.ctrl) }
    if modifierFlags.contains(.option) { mods.insert(.alt) }
    if modifierFlags.contains(.shift) { mods.insert(.shift) }
    return mods
  }

  static let keycodeNames: [UInt16: String] = [
    53: "escape",
    123: "left",
    124: "right",
    125: "down",
    126: "up",
    36: "return",
    48: "tab",
    49: "space",
    51: "delete",
    115: "home",
    119: "end",
    116: "pageup",
    121: "pagedown",
  ]
}
