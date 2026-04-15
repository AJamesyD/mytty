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

struct MisttyConfig: Sendable, Equatable {
  var fontSize: Int = 13
  var fontFamily: String = "monospace"
  var cursorStyle: String = "block"
  var scrollbackLines: Int = 10000
  var sidebarMode: PanelMode = .pinned
  var tabBarMode: PanelMode = .pinned
  var hideTabBarWhenSingleTab: Bool = true
  var autoHideDwellMs: Int = 150
  var autoHideDismissDelayMs: Int = 300
  var autoHideShowHints: Bool = true
  var popups: [PopupDefinition] = []
  var ssh = SSHConfig()
  var keybindingStore: KeybindingStore = .init()

  static let `default` = MisttyConfig()

  static func parse(_ toml: String) throws -> MisttyConfig {
    let table = try TOMLTable(string: toml)
    var config = MisttyConfig()
    if let size = table["font_size"]?.int { config.fontSize = size }
    if let family = table["font_family"]?.string { config.fontFamily = family }
    if let cursor = table["cursor_style"]?.string { config.cursorStyle = cursor }
    if let scrollback = table["scrollback_lines"]?.int { config.scrollbackLines = scrollback }
    if let sidebarTable = table["sidebar"]?.table {
      if let modeStr = sidebarTable["mode"]?.string,
        let mode = PanelMode.fromConfig(modeStr)
      {
        config.sidebarMode = mode
      }
    }
    if table["sidebar"]?.table == nil, let visible = table["sidebar_visible"]?.bool {
      config.sidebarMode = visible ? .pinned : .hidden
    }
    if let tabBarTable = table["tab-bar"]?.table {
      if let modeStr = tabBarTable["mode"]?.string,
        let mode = PanelMode.fromConfig(modeStr)
      {
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
        vimLikeProcesses: nil
      )
    }

    var globalReset = false
    var resets: Set<BindingMode> = []
    var overrides: [BindingMode: [String: KeyboardTrigger]] = [:]
    var userWhichKey: [WhichKeyGroup]?
    var vimLikeProcesses: [String]?

    if let reset = kbTable["_reset"]?.bool, reset {
      globalReset = true
    }

    overrides[.global] = parseModeBindings(from: kbTable)

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
        groups.append(WhichKeyGroup(name: key, bindings: nodes))
      }
      userWhichKey = groups
    }

    if let procs = kbTable["vim-like-processes"]?.array {
      vimLikeProcesses = procs.compactMap { $0.string }
    }

    return KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: userWhichKey,
      resets: resets,
      globalReset: globalReset,
      vimLikeProcesses: vimLikeProcesses
    )
  }

  private static func parseModeBindings(from table: TOMLTable) -> [String: KeyboardTrigger] {
    var result: [String: KeyboardTrigger] = [:]
    for key in table.keys {
      if key.hasPrefix("_") { continue }
      if table[key]?.table != nil { continue }
      if key == "vim-like-processes" { continue }

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

  static func load() -> MisttyConfig {
    let configURL = FileManager.default
      .homeDirectoryForCurrentUser
      .appendingPathComponent(".config/mistty/config.toml")
    guard let contents = try? String(contentsOf: configURL, encoding: .utf8) else {
      return .default
    }
    return (try? parse(contents)) ?? .default
  }

  /// Escape a string for safe TOML serialization.
  private func tomlEscape(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "\"", with: "\\\"")
  }

  func save() throws {
    let configURL = FileManager.default
      .homeDirectoryForCurrentUser
      .appendingPathComponent(".config/mistty/config.toml")

    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var lines: [String] = []
    lines.append("font_size = \(fontSize)")
    lines.append("font_family = \"\(fontFamily)\"")
    lines.append("cursor_style = \"\(cursorStyle)\"")
    lines.append("scrollback_lines = \(scrollbackLines)")
    lines.append("")
    lines.append("[sidebar]")
    lines.append("mode = \"\(sidebarMode.configValue)\"")
    lines.append("")
    lines.append("[tab-bar]")
    lines.append("mode = \"\(tabBarMode.configValue)\"")
    lines.append("hide-when-single-tab = \(hideTabBarWhenSingleTab)")
    lines.append("")
    lines.append("[auto-hide]")
    lines.append("dwell-ms = \(autoHideDwellMs)")
    lines.append("dismiss-delay-ms = \(autoHideDismissDelayMs)")
    lines.append("show-hints = \(autoHideShowHints)")
    for popup in popups {
      lines.append("")
      lines.append("[[popup]]")
      lines.append("name = \"\(popup.name)\"")
      lines.append("command = \"\(popup.command)\"")
      if let shortcut = popup.shortcut {
        lines.append("shortcut = \"\(shortcut)\"")
      }
      lines.append("width = \(popup.width)")
      lines.append("height = \(popup.height)")
      lines.append("close_on_exit = \(popup.closeOnExit)")
    }
    if ssh.defaultCommand != "ssh" || !ssh.hosts.isEmpty {
      lines.append("")
      lines.append("[ssh]")
      lines.append("default_command = \"\(tomlEscape(ssh.defaultCommand))\"")
      for host in ssh.hosts {
        lines.append("")
        lines.append("[[ssh.host]]")
        if let hostname = host.hostname {
          lines.append("hostname = \"\(tomlEscape(hostname))\"")
        }
        if let regex = host.regex {
          lines.append("regex = \"\(tomlEscape(regex))\"")
        }
        lines.append("command = \"\(tomlEscape(host.command))\"")
      }
    }
    try lines.joined(separator: "\n").write(to: configURL, atomically: true, encoding: .utf8)
  }
}
