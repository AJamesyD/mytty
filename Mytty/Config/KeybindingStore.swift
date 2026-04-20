import Foundation

enum BindingMode: String, Sendable, Equatable, Hashable {
  case global
  case windowMode = "window-mode"
  case copyMode = "copy-mode"
}

struct WhichKeyNode: Sendable, Equatable {
  var action: String
  var key: String
}

struct WhichKeyGroup: Sendable, Equatable {
  var name: String
  var key: String = ""
  var bindings: [WhichKeyNode]
}

struct SequenceTrieNode: Sendable, Equatable {
  var children: [KeyboardTrigger: SequenceTrieNode] = [:]
  var action: String?
  var isUnconsumed: Bool = false
}

struct KeybindingStore: Sendable, Equatable {
  private(set) var bindings: [BindingMode: [String: KeyboardTrigger]] = [:]
  private(set) var whichKeyGroups: [WhichKeyGroup] = []
  private(set) var passthroughProcesses: [String]
  private(set) var warnings: [String] = []
  private(set) var sequenceTrie = SequenceTrieNode()
  private(set) var sequenceTimeout: TimeInterval = 1.0

  static let defaultPassthroughProcesses = ["nvim", "neovim", "vim", "helix", "lazygit"]

  static let defaultBindings: [BindingMode: [String: KeyboardTrigger]] = [
    .global: [
      "increase-font-size": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "+"),
      "decrease-font-size": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "-"),
      "toggle-sidebar": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "\\"),
      "toggle-tab-bar": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "t"),
      "new-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "t"),
      "split-horizontal": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "d"),
      "split-vertical": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "d"),
      "close-pane": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "w"),
      "close-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "w"),
      "window-mode": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "w"),
      "copy-mode": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "c"),
      "which-key": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "space"),
      "rename-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "r"),
      "focus-tab-1": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "1"),
      "focus-tab-2": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "2"),
      "focus-tab-3": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "3"),
      "focus-tab-4": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "4"),
      "focus-tab-5": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "5"),
      "focus-tab-6": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "6"),
      "focus-tab-7": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "7"),
      "focus-tab-8": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "8"),
      "focus-tab-9": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "9"),
      "next-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "]"),
      "previous-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "["),
      "previous-session": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .alt], key: "up"),
      "next-session": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .alt], key: "down"),
      "previous-prompt": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "up"),
      "next-prompt": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "down"),
      "navigate-left": KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "h"),
      "navigate-down": KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "j"),
      "navigate-up": KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "k"),
      "navigate-right": KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "l"),
      "session-manager": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "n"),
    ],
    .windowMode: [
      "exit": KeyboardTrigger(prefix: nil, modifiers: [], key: "escape"),
      "swap-left": KeyboardTrigger(prefix: nil, modifiers: [], key: "left"),
      "swap-right": KeyboardTrigger(prefix: nil, modifiers: [], key: "right"),
      "swap-up": KeyboardTrigger(prefix: nil, modifiers: [], key: "up"),
      "swap-down": KeyboardTrigger(prefix: nil, modifiers: [], key: "down"),
      "zoom": KeyboardTrigger(prefix: nil, modifiers: [], key: "z"),
      "break-to-tab": KeyboardTrigger(prefix: nil, modifiers: [], key: "b"),
      "rotate": KeyboardTrigger(prefix: nil, modifiers: [], key: "r"),
      "join-pick": KeyboardTrigger(prefix: nil, modifiers: [], key: "m"),
      "layout-even-horizontal": KeyboardTrigger(prefix: nil, modifiers: [], key: "1"),
      "layout-even-vertical": KeyboardTrigger(prefix: nil, modifiers: [], key: "2"),
      "layout-main-horizontal": KeyboardTrigger(prefix: nil, modifiers: [], key: "3"),
      "layout-main-vertical": KeyboardTrigger(prefix: nil, modifiers: [], key: "4"),
      "layout-tiled": KeyboardTrigger(prefix: nil, modifiers: [], key: "5"),
      "resize-left": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "left"),
      "resize-right": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "right"),
      "resize-up": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "up"),
      "resize-down": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "down"),
    ],
    .copyMode: [
      "move-left": KeyboardTrigger(prefix: nil, modifiers: [], key: "h"),
      "move-down": KeyboardTrigger(prefix: nil, modifiers: [], key: "j"),
      "move-up": KeyboardTrigger(prefix: nil, modifiers: [], key: "k"),
      "move-right": KeyboardTrigger(prefix: nil, modifiers: [], key: "l"),
      "line-start": KeyboardTrigger(prefix: nil, modifiers: [], key: "0"),
      "line-end": KeyboardTrigger(prefix: nil, modifiers: [], key: "$"),
      "bottom": KeyboardTrigger(prefix: nil, modifiers: [], key: "G"),
      "visual": KeyboardTrigger(prefix: nil, modifiers: [], key: "v"),
      "visual-line": KeyboardTrigger(prefix: nil, modifiers: [], key: "V"),
      "word-forward": KeyboardTrigger(prefix: nil, modifiers: [], key: "w"),
      "word-forward-big": KeyboardTrigger(prefix: nil, modifiers: [], key: "W"),
      "word-backward": KeyboardTrigger(prefix: nil, modifiers: [], key: "b"),
      "word-backward-big": KeyboardTrigger(prefix: nil, modifiers: [], key: "B"),
      "word-end": KeyboardTrigger(prefix: nil, modifiers: [], key: "e"),
      "word-end-big": KeyboardTrigger(prefix: nil, modifiers: [], key: "E"),
      "search-forward": KeyboardTrigger(prefix: nil, modifiers: [], key: "/"),
      "search-backward": KeyboardTrigger(prefix: nil, modifiers: [], key: "?"),
      "search-next": KeyboardTrigger(prefix: nil, modifiers: [], key: "n"),
      "search-prev": KeyboardTrigger(prefix: nil, modifiers: [], key: "N"),
      "find-char": KeyboardTrigger(prefix: nil, modifiers: [], key: "f"),
      "find-char-back": KeyboardTrigger(prefix: nil, modifiers: [], key: "F"),
      "find-till": KeyboardTrigger(prefix: nil, modifiers: [], key: "t"),
      "find-till-back": KeyboardTrigger(prefix: nil, modifiers: [], key: "T"),
      "repeat-find": KeyboardTrigger(prefix: nil, modifiers: [], key: ";"),
      "repeat-find-back": KeyboardTrigger(prefix: nil, modifiers: [], key: ","),
      "half-page-down": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "d"),
      "half-page-up": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "u"),
      "page-down": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "f"),
      "page-up": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "b"),
      "yank": KeyboardTrigger(prefix: nil, modifiers: [], key: "y"),
      "exit": KeyboardTrigger(prefix: nil, modifiers: [], key: "escape"),
      "top": KeyboardTrigger(prefix: nil, modifiers: [], key: "gg"),
    ],
  ]

  static let defaultWhichKeyGroups: [WhichKeyGroup] = [
    WhichKeyGroup(
      name: "window",
      key: "w",
      bindings: [
        WhichKeyNode(action: "swap-left", key: "h"),
        WhichKeyNode(action: "swap-down", key: "j"),
        WhichKeyNode(action: "swap-up", key: "k"),
        WhichKeyNode(action: "swap-right", key: "l"),
        WhichKeyNode(action: "zoom", key: "z"),
        WhichKeyNode(action: "break-to-tab", key: "b"),
        WhichKeyNode(action: "rotate", key: "r"),
        WhichKeyNode(action: "even-layout", key: "="),
      ]),
    WhichKeyGroup(
      name: "pane",
      key: "p",
      bindings: [
        WhichKeyNode(action: "split-vertical", key: "v"),
        WhichKeyNode(action: "split-horizontal", key: "h"),
        WhichKeyNode(action: "close-pane", key: "x"),
      ]),
    WhichKeyGroup(
      name: "session",
      key: "s",
      bindings: [
        WhichKeyNode(action: "new-session", key: "n"),
        WhichKeyNode(action: "close-session", key: "c"),
      ]),
    WhichKeyGroup(
      name: "tab",
      key: "t",
      bindings: [
        WhichKeyNode(action: "new-tab", key: "n"),
        WhichKeyNode(action: "close-tab", key: "x"),
      ]
        + (1...9).map { WhichKeyNode(action: "focus-tab-\($0)", key: "\($0)") }),
  ]

  init(
    bindings: [BindingMode: [String: KeyboardTrigger]] = [:],
    whichKeyGroups: [WhichKeyGroup] = [],
    passthroughProcesses: [String] = defaultPassthroughProcesses,
    warnings: [String] = [],
    sequenceTrie: SequenceTrieNode = SequenceTrieNode(),
    sequenceTimeout: TimeInterval = 1.0
  ) {
    self.bindings = bindings
    self.whichKeyGroups = whichKeyGroups
    self.passthroughProcesses = passthroughProcesses
    self.warnings = warnings
    self.sequenceTrie = sequenceTrie
    self.sequenceTimeout = sequenceTimeout
  }

  func trigger(for action: String, in mode: BindingMode) -> KeyboardTrigger? {
    bindings[mode]?[action]
  }

  func reverseLookup(in mode: BindingMode) -> [KeyboardTrigger: String] {
    var result: [KeyboardTrigger: String] = [:]
    guard let modeBindings = bindings[mode] else { return result }
    for (action, trigger) in modeBindings {
      result[trigger] = action
    }
    return result
  }

  static func merge(
    defaults: [BindingMode: [String: KeyboardTrigger]],
    overrides: [BindingMode: [String: KeyboardTrigger]],
    resets: Set<BindingMode>,
    globalReset: Bool
  ) -> [BindingMode: [String: KeyboardTrigger]] {
    if globalReset {
      return overrides
    }
    var result = defaults
    for (mode, userBindings) in overrides {
      if resets.contains(mode) {
        result[mode] = userBindings
      } else {
        for (action, trigger) in userBindings {
          result[mode, default: [:]][action] = trigger
        }
      }
    }
    for (mode, modeBindings) in result {
      result[mode] = modeBindings.filter { _, trigger in
        trigger.key != "__unbind__"
      }
    }
    return result
  }

  static func detectConflicts(
    bindings: [BindingMode: [String: KeyboardTrigger]]
  ) -> [String] {
    var warnings: [String] = []
    for (mode, modeBindings) in bindings {
      var triggerToAction: [KeyboardTrigger: String] = [:]
      for (action, trigger) in modeBindings.sorted(by: { $0.key < $1.key }) {
        if let existing = triggerToAction[trigger] {
          let triggerStr = TriggerParser.normalize(trigger)
          warnings.append(
            "Conflict in \(mode.rawValue): '\(triggerStr)' is bound to both '\(existing)' and '\(action)'"
          )
        }
        triggerToAction[trigger] = action
      }
    }
    return warnings
  }

  static func build(
    defaults: [BindingMode: [String: KeyboardTrigger]],
    defaultWhichKey: [WhichKeyGroup],
    userOverrides: [BindingMode: [String: KeyboardTrigger]],
    userWhichKey: [WhichKeyGroup]?,
    resets: Set<BindingMode>,
    globalReset: Bool,
    passthroughProcesses: [String]?,
    sequenceOverrides: [String: KeySequence] = [:],
    sequenceTimeout: TimeInterval = 1.0
  ) -> KeybindingStore {
    let merged = merge(
      defaults: defaults,
      overrides: userOverrides,
      resets: resets,
      globalReset: globalReset
    )
    var warnings = detectConflicts(bindings: merged)
    var globalBindings = merged[.global] ?? [:]
    let trie = buildSequenceTrie(
      sequences: sequenceOverrides,
      flatBindings: &globalBindings,
      warnings: &warnings
    )
    var finalMerged = merged
    finalMerged[.global] = globalBindings
    return KeybindingStore(
      bindings: finalMerged,
      whichKeyGroups: userWhichKey ?? defaultWhichKey,
      passthroughProcesses: passthroughProcesses ?? defaultPassthroughProcesses,
      warnings: warnings,
      sequenceTrie: trie,
      sequenceTimeout: sequenceTimeout
    )
  }

  private static func buildSequenceTrie(
    sequences: [String: KeySequence],
    flatBindings: inout [String: KeyboardTrigger],
    warnings: inout [String]
  ) -> SequenceTrieNode {
    var root = SequenceTrieNode()
    for (action, seq) in sequences.sorted(by: { $0.key < $1.key }) {
      guard seq.triggers.count > 1 else { continue }
      guard seq.triggers.count <= KeySequence.maxDepth else {
        warnings.append(
          "Sequence for '\(action)' exceeds max depth of \(KeySequence.maxDepth), skipping")
        continue
      }
      insertIntoTrie(
        &root, triggers: seq.triggers, action: action, isUnconsumed: seq.prefix == .unconsumed)
    }
    for leaderTrigger in root.children.keys {
      for (action, trigger) in flatBindings where trigger == leaderTrigger {
        let triggerStr = TriggerParser.normalize(trigger)
        warnings.append(
          "'\(triggerStr)' is a sequence leader and also bound to '\(action)'; the standalone binding is unreachable"
        )
        flatBindings.removeValue(forKey: action)
      }
    }
    return root
  }

  private static func insertIntoTrie(
    _ node: inout SequenceTrieNode,
    triggers: [KeyboardTrigger],
    action: String,
    isUnconsumed: Bool
  ) {
    guard let first = triggers.first else { return }
    if node.children[first] == nil {
      node.children[first] = SequenceTrieNode()
    }
    if triggers.count == 1 {
      guard var child = node.children[first] else { return }
      child.action = action
      child.isUnconsumed = isUnconsumed
      node.children[first] = child
    } else {
      guard var child = node.children[first] else { return }
      insertIntoTrie(
        &child, triggers: Array(triggers.dropFirst()), action: action,
        isUnconsumed: isUnconsumed)
      node.children[first] = child
    }
  }
}
