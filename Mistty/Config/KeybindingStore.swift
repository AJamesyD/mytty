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
  var bindings: [WhichKeyNode]
}

struct KeybindingStore: Sendable, Equatable {
  private(set) var bindings: [BindingMode: [String: KeyboardTrigger]] = [:]
  private(set) var whichKeyGroups: [WhichKeyGroup] = []
  private(set) var vimLikeProcesses: [String]
  private(set) var warnings: [String] = []

  static let defaultVimLikeProcesses = ["nvim", "vim", "helix", "lazygit"]

  static let defaultBindings: [BindingMode: [String: KeyboardTrigger]] = [
    .global: [
      "new-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "t"),
      "close-pane": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "w"),
      "split-horizontal": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "d"),
      "toggle-sidebar": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "s"),
      "navigate-left": KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "h"),
      "navigate-right": KeyboardTrigger(prefix: .unconsumed, modifiers: [.ctrl], key: "l"),
    ],
    .windowMode: [
      "zoom": KeyboardTrigger(prefix: nil, modifiers: [], key: "z"),
      "exit": KeyboardTrigger(prefix: nil, modifiers: [], key: "escape"),
      "swap-left": KeyboardTrigger(prefix: nil, modifiers: [], key: "left"),
    ],
    .copyMode: [
      "yank": KeyboardTrigger(prefix: nil, modifiers: [], key: "y"),
      "exit": KeyboardTrigger(prefix: nil, modifiers: [], key: "escape"),
      "cursor-up": KeyboardTrigger(prefix: nil, modifiers: [], key: "k"),
      "top": KeyboardTrigger(prefix: nil, modifiers: [], key: "gg"),
    ],
  ]

  static let defaultWhichKeyGroups: [WhichKeyGroup] = [
    WhichKeyGroup(name: "window", bindings: [
      WhichKeyNode(action: "zoom", key: "z"),
      WhichKeyNode(action: "swap-left", key: "h"),
    ]),
    WhichKeyGroup(name: "pane", bindings: [
      WhichKeyNode(action: "split-horizontal", key: "h"),
    ]),
  ]

  init(
    bindings: [BindingMode: [String: KeyboardTrigger]] = [:],
    whichKeyGroups: [WhichKeyGroup] = [],
    vimLikeProcesses: [String] = defaultVimLikeProcesses,
    warnings: [String] = []
  ) {
    self.bindings = bindings
    self.whichKeyGroups = whichKeyGroups
    self.vimLikeProcesses = vimLikeProcesses
    self.warnings = warnings
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
        if result[mode] == nil { result[mode] = [:] }
        for (action, trigger) in userBindings {
          result[mode]![action] = trigger
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
    vimLikeProcesses: [String]?
  ) -> KeybindingStore {
    let merged = merge(
      defaults: defaults,
      overrides: userOverrides,
      resets: resets,
      globalReset: globalReset
    )
    let warnings = detectConflicts(bindings: merged)
    return KeybindingStore(
      bindings: merged,
      whichKeyGroups: userWhichKey ?? defaultWhichKey,
      vimLikeProcesses: vimLikeProcesses ?? defaultVimLikeProcesses,
      warnings: warnings
    )
  }
}
