import SwiftUI

enum TriggerPrefix: String, Sendable, Equatable {
  case unconsumed
}

struct KeyboardTrigger: Sendable, Equatable, Hashable {
  var prefix: TriggerPrefix?
  var modifiers: Set<Modifier>
  var key: String

  enum Modifier: String, Sendable, Equatable, Hashable, Comparable {
    case ctrl, alt, shift, cmd

    static func < (lhs: Modifier, rhs: Modifier) -> Bool {
      lhs.rawValue < rhs.rawValue
    }
  }
}

struct KeySequence: Sendable, Equatable, Hashable {
  static let maxDepth = 5
  var prefix: TriggerPrefix?
  var triggers: [KeyboardTrigger]
}

enum TriggerParseError: Error, Equatable {
  case empty
  case unknownModifier(String)
  case unknownPrefix(String)
  case reservedKeyword(String)
  case sequenceTooDeep(Int)
}

struct TriggerParser {
  private static let modifierAliases: [String: KeyboardTrigger.Modifier] = [
    "cmd": .cmd, "command": .cmd, "super": .cmd,
    "ctrl": .ctrl, "control": .ctrl,
    "alt": .alt, "opt": .alt, "option": .alt,
    "shift": .shift,
  ]

  static func parse(_ input: String) throws -> KeyboardTrigger {
    let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { throw TriggerParseError.empty }
    guard trimmed != "unbind" else { throw TriggerParseError.reservedKeyword("unbind") }

    var remaining = trimmed
    var prefix: TriggerPrefix?

    if let colonIndex = remaining.firstIndex(of: ":") {
      let prefixStr = String(remaining[remaining.startIndex..<colonIndex])
      if let p = TriggerPrefix(rawValue: prefixStr) {
        prefix = p
        remaining = String(remaining[remaining.index(after: colonIndex)...])
      } else if modifierAliases[prefixStr] == nil {
        throw TriggerParseError.unknownPrefix(prefixStr)
      }
    }

    let parts = remaining.split(separator: "+", omittingEmptySubsequences: false).map(String.init)

    if parts.count == 1 {
      return KeyboardTrigger(prefix: prefix, modifiers: [], key: parts[0])
    }

    // When the last element is empty, the key is "+".
    // "cmd++" splits into ["cmd", "", ""] so we take "+" as the key
    // and parse modifiers from everything before the last two elements.
    var key: String
    var modParts: [String]
    if parts.last == "" && parts.count >= 2 {
      key = "+"
      modParts = Array(parts.dropLast(2))
    } else {
      guard let lastPart = parts.last else { throw TriggerParseError.empty }
      key = lastPart
      modParts = Array(parts.dropLast())
    }

    var modifiers: Set<KeyboardTrigger.Modifier> = []
    for mod in modParts {
      guard let modifier = modifierAliases[mod] else {
        throw TriggerParseError.unknownModifier(mod)
      }
      modifiers.insert(modifier)
    }

    return KeyboardTrigger(prefix: prefix, modifiers: modifiers, key: key)
  }

  static func normalize(_ trigger: KeyboardTrigger) -> String {
    let sortedMods = trigger.modifiers.sorted().map(\.rawValue)
    let keyParts = sortedMods + [trigger.key]
    let body = keyParts.joined(separator: "+")
    if let prefix = trigger.prefix {
      return prefix.rawValue + ":" + body
    }
    return body
  }

  static func parseSequence(_ input: String) throws -> KeySequence {
    let trimmed = input.trimmingCharacters(in: .whitespaces).lowercased()
    guard !trimmed.isEmpty else { throw TriggerParseError.empty }
    guard trimmed != "unbind" else { throw TriggerParseError.reservedKeyword("unbind") }

    var remaining = trimmed
    var prefix: TriggerPrefix?

    if let colonIndex = remaining.firstIndex(of: ":") {
      let prefixStr = String(remaining[remaining.startIndex..<colonIndex])
      if let p = TriggerPrefix(rawValue: prefixStr) {
        prefix = p
        remaining = String(remaining[remaining.index(after: colonIndex)...])
      }
    }

    let segments = remaining.split(separator: ">", omittingEmptySubsequences: false).map(
      String.init)
    guard segments.count <= KeySequence.maxDepth else {
      throw TriggerParseError.sequenceTooDeep(segments.count)
    }

    var triggers: [KeyboardTrigger] = []
    for segment in segments {
      let trimmedSegment = segment.trimmingCharacters(in: .whitespaces)
      guard !trimmedSegment.isEmpty else { throw TriggerParseError.empty }
      triggers.append(try parse(trimmedSegment))
    }

    return KeySequence(prefix: prefix, triggers: triggers)
  }

  static func normalizeSequence(_ seq: KeySequence) -> String {
    let body = seq.triggers.map { normalize($0) }.joined(separator: ">")
    if let prefix = seq.prefix {
      return prefix.rawValue + ":" + body
    }
    return body
  }
}

extension KeyboardTrigger {
  func toKeyboardShortcut() -> KeyboardShortcut? {
    if prefix == .unconsumed { return nil }
    guard let keyEquiv = keyEquivalent else { return nil }
    return KeyboardShortcut(keyEquiv, modifiers: eventModifiers)
  }

  private var keyEquivalent: KeyEquivalent? {
    switch key {
    case "escape": return .escape
    case "return", "enter": return .return
    case "tab": return .tab
    case "space": return .space
    case "delete", "backspace": return .delete
    case "up": return .upArrow
    case "down": return .downArrow
    case "left": return .leftArrow
    case "right": return .rightArrow
    case "home": return .home
    case "end": return .end
    case "pageup": return .pageUp
    case "pagedown": return .pageDown
    default:
      guard key.count == 1, let char = key.first else { return nil }
      return KeyEquivalent(char)
    }
  }

  var displayLabel: String {
    var parts: [String] = []
    if modifiers.contains(.ctrl) { parts.append("⌃") }
    if modifiers.contains(.alt) { parts.append("⌥") }
    if modifiers.contains(.shift) { parts.append("⇧") }
    if modifiers.contains(.cmd) { parts.append("⌘") }
    parts.append(Self.keySymbol(for: key))
    return parts.joined()
  }

  private static func keySymbol(for key: String) -> String {
    switch key {
    case "escape": return "⎋"
    case "return", "enter": return "↩"
    case "tab": return "⇥"
    case "space": return "␣"
    case "delete", "backspace": return "⌫"
    case "up": return "↑"
    case "down": return "↓"
    case "left": return "←"
    case "right": return "→"
    case "home": return "↖"
    case "end": return "↘"
    case "pageup": return "⇞"
    case "pagedown": return "⇟"
    default: return key.uppercased()
    }
  }

  private var eventModifiers: EventModifiers {
    var result: EventModifiers = []
    if modifiers.contains(.cmd) { result.insert(.command) }
    if modifiers.contains(.ctrl) { result.insert(.control) }
    if modifiers.contains(.alt) { result.insert(.option) }
    if modifiers.contains(.shift) { result.insert(.shift) }
    return result
  }
}
