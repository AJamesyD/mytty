import Foundation
import GhosttyKit
import SwiftUI

@main
struct MisttyApp: App {
  @State private var store = SessionStore()
  @State private var ipcListener: IPCListener?
  @State private var persistenceService: PersistenceService?
  @FocusedValue(\.terminalCommands) var commands

  init() {
    _ = GhosttyAppManager.shared
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
        .onAppear {
          if persistenceService == nil {
            let ps = PersistenceService(store: store)
            ps.restore()
            ps.startObserving()
            persistenceService = ps
          }
          if ipcListener == nil {
            let service = MisttyIPCService(store: store)
            let listener = IPCListener(service: service)
            listener.start()
            ipcListener = listener
          }
        }
    }
    .commands {
      CommandGroup(after: .toolbar) {
        Divider()

        Button("Increase Font Size") {}
          .keyboardShortcut("+", modifiers: .command)

        Button("Decrease Font Size") {}
          .keyboardShortcut("-", modifiers: .command)

        Divider()

        Button("Toggle Sidebar") {
          commands?.toggleSidebar()
        }
        .keyboardShortcut("s", modifiers: .command)

        Button("Toggle Tab Bar") {
          commands?.toggleTabBar()
        }
        .keyboardShortcut("t", modifiers: [.command, .shift])

        Button("New Tab") {
          commands?.newTab()
        }
        .keyboardShortcut("t", modifiers: .command)

        Button("Split Pane Horizontally") {
          commands?.splitHorizontal()
        }
        .keyboardShortcut("d", modifiers: .command)

        Button("Split Pane Vertically") {
          commands?.splitVertical()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button("Session Manager") {
          commands?.sessionManager()
        }
        .keyboardShortcut("j", modifiers: .command)

        Divider()

        Button("Close Pane") {
          commands?.closePane()
        }
        .keyboardShortcut("w", modifiers: .command)

        Button("Close Tab") {
          commands?.closeTab()
        }
        .keyboardShortcut("w", modifiers: [.command, .shift])

        Button("Window Mode") {
          commands?.windowMode()
        }
        .keyboardShortcut("x", modifiers: .command)

        Button("Copy Mode") {
          commands?.copyMode()
        }
        .keyboardShortcut("c", modifiers: [.command, .shift])

        Button("Which-Key") {
          commands?.whichKey()
        }
        .keyboardShortcut(.space, modifiers: .control)

        Divider()

        Button("Rename Tab") {
          NotificationCenter.default.post(name: .misttyRenameTab, object: nil)
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])

        Button("Rename Session") {
          NotificationCenter.default.post(name: .misttyRenameSession, object: nil)
        }

        Divider()

        ForEach(1...9, id: \.self) { index in
          Button("Focus Tab \(index)") {
            commands?.focusTab(index - 1)
          }
          .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: .command)
        }

        Button("Next Tab") {
          commands?.nextTab()
        }
        .keyboardShortcut("]", modifiers: .command)

        Button("Previous Tab") {
          commands?.prevTab()
        }
        .keyboardShortcut("[", modifiers: .command)

        Button("Previous Session") {
          commands?.prevSession()
        }
        .keyboardShortcut(.upArrow, modifiers: [.command, .shift])

        Button("Next Session") {
          commands?.nextSession()
        }
        .keyboardShortcut(.downArrow, modifiers: [.command, .shift])

        Divider()

        ForEach(Array(MisttyConfig.load().popups.enumerated()), id: \.offset) { _, popup in
          if let key = parseShortcutKey(popup.shortcut),
            let modifiers = parseShortcutModifiers(popup.shortcut)
          {
            Button("Toggle \(popup.name)") {
              commands?.togglePopup(popup.name)
            }
            .keyboardShortcut(key, modifiers: modifiers)
          }
        }
      }
    }

    Settings {
      SettingsView()
    }
  }

  /// Normalize shortcut string: lowercase, accept both "+" and "-" as separators.
  private func shortcutParts(_ shortcut: String?) -> [Substring]? {
    guard let shortcut else { return nil }
    let normalized = shortcut.lowercased().replacing("-", with: "+")
    let parts = normalized.split(separator: "+")
    return parts.isEmpty ? nil : parts
  }

  private func parseShortcutKey(_ shortcut: String?) -> KeyEquivalent? {
    guard let parts = shortcutParts(shortcut),
      let last = parts.last, last.count == 1, let char = last.first
    else { return nil }
    return KeyEquivalent(char)
  }

  private func parseShortcutModifiers(_ shortcut: String?) -> EventModifiers? {
    guard let parts = shortcutParts(shortcut) else { return nil }
    var modifiers: EventModifiers = []
    for part in parts.dropLast() {
      switch part {
      case "cmd", "command": modifiers.insert(.command)
      case "shift": modifiers.insert(.shift)
      case "opt", "option", "alt": modifiers.insert(.option)
      case "ctrl", "control": modifiers.insert(.control)
      default: break
      }
    }
    return modifiers.isEmpty ? nil : modifiers
  }
}

extension Notification.Name {
  static let misttyRenameTab = Notification.Name("misttyRenameTab")
  static let misttyRenameSession = Notification.Name("misttyRenameSession")
}
