import Foundation

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

enum TriggerParseError: Error, Equatable {
  case empty
  case unknownModifier(String)
  case unknownPrefix(String)
  case reservedKeyword(String)
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
      key = parts.last!
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
}
