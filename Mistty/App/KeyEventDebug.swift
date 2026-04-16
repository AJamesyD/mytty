import AppKit

enum KeyEventDebug {
  static let enabled = ProcessInfo.processInfo.environment["MISTTY_KEY_DEBUG"] != nil

  static func log(_ label: String, _ event: NSEvent) {
    let chars = event.characters ?? "nil"
    let charsIM = event.charactersIgnoringModifiers ?? "nil"
    let charsBM = event.characters(byApplyingModifiers: []) ?? "nil"
    let mods = modString(event.modifierFlags)
    Swift.print(
      "[\(label)] keyCode=\(event.keyCode) chars=\"\(chars)\" charsIM=\"\(charsIM)\" charsBM=\"\(charsBM)\" mods=\(mods)"
    )
  }

  static func print(_ msg: String) {
    Swift.print("[KeyDebug] \(msg)")
  }

  private static func modString(_ flags: NSEvent.ModifierFlags) -> String {
    var parts: [String] = []
    if flags.contains(.command) { parts.append("cmd") }
    if flags.contains(.control) { parts.append("ctrl") }
    if flags.contains(.option) { parts.append("alt") }
    if flags.contains(.shift) { parts.append("shift") }
    if flags.contains(.capsLock) { parts.append("caps") }
    return parts.isEmpty ? "none" : parts.joined(separator: "+")
  }
}
