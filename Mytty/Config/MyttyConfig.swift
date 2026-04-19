import Foundation
import TOMLKit

struct SSHHostOverride: Sendable, Equatable {
  var hostname: String?
  var regex: String?
  var command: String

  func matches(_ host: String) -> Bool {
    if let hostname { return hostname == host }
    if let regex, let re = try? Regex(regex) {
      return host.wholeMatch(of: re) != nil
    }
    return false
  }
}

struct SSHConfig: Sendable, Equatable {
  var defaultCommand: String = "ssh"
  var hosts: [SSHHostOverride] = []

  func resolveCommand(for host: String) -> String {
    for override in hosts where override.matches(host) {
      return override.command
    }
    return defaultCommand
  }
}

enum SidebarPosition: String, Sendable, Equatable {
  case left, right
}

struct MyttyConfig: Sendable, Equatable {
  var sidebarMode: PanelMode = .pinned
  var sidebarPosition: SidebarPosition = .left
  var sidebarShowTree: Bool = true
  var tabBarMode: PanelMode = .pinned
  var hideTabBarWhenSingleTab: Bool = true
  var autoHideDwellMs: Int = 150
  var autoHideDismissDelayMs: Int = 300
  var autoHideShowHints: Bool = true
  var popups: [PopupDefinition] = []
  var ssh = SSHConfig()
  var keybindingStore: KeybindingStore = .init()
  var parseError: String?

  static let `default` = MyttyConfig()

  // TODO: validate unknown keys. Currently unrecognized config keys (typos)
  // are silently ignored. Add a pass that collects unknown top-level and
  // section keys into keybindingStore.warnings.
  static func parse(_ toml: String) throws -> MyttyConfig {
    let table = try TOMLTable(string: toml)
    var config = MyttyConfig()
    if let sidebarTable = table["sidebar"]?.table {
      if let modeStr = sidebarTable["mode"]?.string,
        let mode = PanelMode.fromConfig(modeStr) {
        config.sidebarMode = mode
      }
      if let posStr = sidebarTable["position"]?.string {
        config.sidebarPosition = SidebarPosition(rawValue: posStr) ?? .left
      }
      if let showTree = sidebarTable["show-tree"]?.bool {
        config.sidebarShowTree = showTree
      }
    }
    if table["sidebar"]?.table == nil, let visible = table["sidebar_visible"]?.bool {
      config.sidebarMode = visible ? .pinned : .hidden
    }
    if let tabBarTable = table["tab-bar"]?.table {
      if let modeStr = tabBarTable["mode"]?.string,
        let mode = PanelMode.fromConfig(modeStr) {
        config.tabBarMode = mode
      }
      if let hide = tabBarTable["hide-when-single-tab"]?.bool {
        config.hideTabBarWhenSingleTab = hide
      }
    }
    if let autoHideTable = table["auto-hide"]?.table {
      if let dwell = autoHideTable["dwell-ms"]?.int { config.autoHideDwellMs = dwell }
      if let dismiss = autoHideTable["dismiss-delay-ms"]?.int {
        config.autoHideDismissDelayMs = dismiss
      }
      if let hints = autoHideTable["show-hints"]?.bool { config.autoHideShowHints = hints }
    }
    if let popupArray = table["popup"]?.array {
      config.popups = popupArray.compactMap { entry -> PopupDefinition? in
        guard let t = entry.table else { return nil }
        return PopupDefinition(
          name: t["name"]?.string ?? "",
          command: t["command"]?.string ?? "",
          shortcut: t["shortcut"]?.string,
          width: max(0.1, min(1.0, t["width"]?.double ?? 0.8)),
          height: max(0.1, min(1.0, t["height"]?.double ?? 0.8)),
          closeOnExit: t["close_on_exit"]?.bool ?? true
        )
      }
    }
    if let sshTable = table["ssh"]?.table {
      if let defaultCmd = sshTable["default_command"]?.string {
        config.ssh.defaultCommand = defaultCmd
      }
      if let hostArray = sshTable["host"]?.array {
        config.ssh.hosts = hostArray.compactMap { entry -> SSHHostOverride? in
          guard let t = entry.table else { return nil }
          return SSHHostOverride(
            hostname: t["hostname"]?.string,
            regex: t["regex"]?.string,
            command: t["command"]?.string ?? config.ssh.defaultCommand
          )
        }
      }
    }
    config.keybindingStore = Self.parseKeybindings(from: table)
    return config
  }

  private static func parseKeybindings(from table: TOMLTable) -> KeybindingStore {
    guard let kbTable = table["keybindings"]?.table else {
      return KeybindingStore.build(
        defaults: KeybindingStore.defaultBindings,
        defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
        userOverrides: [:],
        userWhichKey: nil,
        resets: [],
        globalReset: false,
        passthroughProcesses: nil
      )
    }

    var globalReset = false
    var resets: Set<BindingMode> = []
    var overrides: [BindingMode: [String: KeyboardTrigger]] = [:]
    var userWhichKey: [WhichKeyGroup]?
    var passthroughProcesses: [String]?
    var sequenceOverrides: [String: KeySequence] = [:]
    var sequenceTimeout: TimeInterval = 1.0

    if let reset = kbTable["_reset"]?.bool, reset {
      globalReset = true
    }

    if let timeout = kbTable["sequence-timeout"]?.double {
      sequenceTimeout = max(0.0, min(10.0, timeout))
    }

    let (globalSingle, globalSequences) = parseGlobalBindings(from: kbTable)
    overrides[.global] = globalSingle
    sequenceOverrides = globalSequences

    for (modeKey, mode) in [("window-mode", BindingMode.windowMode), ("copy-mode", .copyMode)] {
      if let modeTable = kbTable[modeKey]?.table {
        if let reset = modeTable["_reset"]?.bool, reset {
          resets.insert(mode)
        }
        overrides[mode] = parseModeBindings(from: modeTable)
      }
    }

    if let whichKeyTable = kbTable["which-key"]?.table {
      var groups: [WhichKeyGroup] = []
      for key in whichKeyTable.keys {
        guard let groupTable = whichKeyTable[key]?.table else { continue }
        var nodes: [WhichKeyNode] = []
        for nodeKey in groupTable.keys {
          guard let value = groupTable[nodeKey]?.string else { continue }
          nodes.append(WhichKeyNode(action: nodeKey, key: value))
        }
        groups.append(WhichKeyGroup(name: key, key: String(key.prefix(1)), bindings: nodes))
      }
      userWhichKey = groups
    }

    if let procs = kbTable["passthrough-processes"]?.array {
      passthroughProcesses = procs.compactMap { $0.string }
    }

    return KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: userWhichKey,
      resets: resets,
      globalReset: globalReset,
      passthroughProcesses: passthroughProcesses,
      sequenceOverrides: sequenceOverrides,
      sequenceTimeout: sequenceTimeout
    )
  }

  private static func parseModeBindings(from table: TOMLTable) -> [String: KeyboardTrigger] {
    var result: [String: KeyboardTrigger] = [:]
    for key in table.keys {
      if key.hasPrefix("_") { continue }
      if table[key]?.table != nil { continue }
      if key == "passthrough-processes" { continue }

      if let str = table[key]?.string {
        if str == "unbind" {
          result[key] = KeyboardTrigger(prefix: nil, modifiers: [], key: "__unbind__")
        } else if let trigger = try? TriggerParser.parse(str) {
          result[key] = trigger
        }
      } else if let arr = table[key]?.array, let first = arr.first?.string {
        if let trigger = try? TriggerParser.parse(first) {
          result[key] = trigger
        }
      }
    }
    return result
  }

  private static func parseGlobalBindings(
    from table: TOMLTable
  ) -> ([String: KeyboardTrigger], [String: KeySequence]) {
    var singles: [String: KeyboardTrigger] = [:]
    var sequences: [String: KeySequence] = [:]
    for key in table.keys {
      if key.hasPrefix("_") { continue }
      if table[key]?.table != nil { continue }
      if key == "passthrough-processes" || key == "sequence-timeout" { continue }

      let str: String
      if let s = table[key]?.string {
        str = s
      } else if let arr = table[key]?.array, let first = arr.first?.string {
        str = first
      } else {
        continue
      }

      if str == "unbind" {
        singles[key] = KeyboardTrigger(prefix: nil, modifiers: [], key: "__unbind__")
        continue
      }
      guard let seq = try? TriggerParser.parseSequence(str) else { continue }
      if seq.triggers.count == 1 {
        var trigger = seq.triggers[0]
        if let prefix = seq.prefix {
          trigger.prefix = prefix
        }
        singles[key] = trigger
      } else {
        sequences[key] = seq
      }
    }
    return (singles, sequences)
  }

  static let configFileURL = FileManager.default
    .homeDirectoryForCurrentUser
    .appendingPathComponent(".config/mytty/config.toml")

  static func load() -> MyttyConfig {
    guard let contents = try? String(contentsOf: configFileURL, encoding: .utf8) else {
      return .default
    }
    do {
      return try parse(contents)
    } catch {
      var config = MyttyConfig.default
      config.parseError = error.localizedDescription
      return config
    }
  }
}
