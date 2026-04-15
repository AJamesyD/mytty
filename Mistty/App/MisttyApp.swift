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

  private var keybindings: KeybindingStore {
    MisttyConfig.load().keybindingStore
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
          .keyboardShortcut(from: keybindings.trigger(for: "increase-font-size", in: .global))

        Button("Decrease Font Size") {}
          .keyboardShortcut(from: keybindings.trigger(for: "decrease-font-size", in: .global))

        Divider()

        Button("Toggle Sidebar") {
          commands?.toggleSidebar()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "toggle-sidebar", in: .global))

        Button("Toggle Tab Bar") {
          commands?.toggleTabBar()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "toggle-tab-bar", in: .global))

        Button("New Tab") {
          commands?.newTab()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "new-tab", in: .global))

        Button("Split Pane Horizontally") {
          commands?.splitHorizontal()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "split-horizontal", in: .global))

        Button("Split Pane Vertically") {
          commands?.splitVertical()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "split-vertical", in: .global))

        Button("Session Manager") {
          commands?.sessionManager()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "session-manager", in: .global))

        Divider()

        Button("Close Pane") {
          commands?.closePane()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "close-pane", in: .global))

        Button("Close Tab") {
          commands?.closeTab()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "close-tab", in: .global))

        Button("Window Mode") {
          commands?.windowMode()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "window-mode", in: .global))

        Button("Copy Mode") {
          commands?.copyMode()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "copy-mode", in: .global))

        Button("Which-Key") {
          commands?.whichKey()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "which-key", in: .global))

        Divider()

        Button("Rename Tab") {
          NotificationCenter.default.post(name: .misttyRenameTab, object: nil)
        }
        .keyboardShortcut(from: keybindings.trigger(for: "rename-tab", in: .global))

        Button("Rename Session") {
          NotificationCenter.default.post(name: .misttyRenameSession, object: nil)
        }

        Divider()

        ForEach(1...9, id: \.self) { index in
          Button("Focus Tab \(index)") {
            commands?.focusTab(index - 1)
          }
          .keyboardShortcut(from: keybindings.trigger(for: "focus-tab-\(index)", in: .global))
        }

        Button("Next Tab") {
          commands?.nextTab()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "next-tab", in: .global))

        Button("Previous Tab") {
          commands?.prevTab()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "previous-tab", in: .global))

        Button("Previous Session") {
          commands?.prevSession()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "previous-session", in: .global))

        Button("Next Session") {
          commands?.nextSession()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "next-session", in: .global))

        Divider()

        Button("Previous Prompt") {
          commands?.jumpToPreviousPrompt()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "previous-prompt", in: .global))

        Button("Next Prompt") {
          commands?.jumpToNextPrompt()
        }
        .keyboardShortcut(from: keybindings.trigger(for: "next-prompt", in: .global))

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

extension View {
  @ViewBuilder
  fileprivate func keyboardShortcut(from trigger: KeyboardTrigger?) -> some View {
    if let shortcut = trigger?.toKeyboardShortcut() {
      self.keyboardShortcut(shortcut)
    } else {
      self
    }
  }
}
