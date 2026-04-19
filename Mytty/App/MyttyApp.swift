import SwiftUI

@main
struct MyttyApp: App {
  @NSApplicationDelegateAdaptor(MyttyAppDelegate.self) var appDelegate
  @State private var store = SessionStore()
  @State private var ipcListener: IPCListener?
  @State private var persistenceService: PersistenceService?
  @State private var config = MyttyConfig.load()
  @State private var dropdownController: DropdownController?
  @State private var hotkeyMonitor: GlobalHotkeyMonitor?
  @FocusedValue(\.terminalCommands) var commands

  init() {
    NSWindow.allowsAutomaticWindowTabbing = false
    _ = GhosttyAppManager.shared
  }

  var body: some Scene {
    WindowGroup {
      ContentView(store: store)
        .onReceive(NotificationCenter.default.publisher(for: .myttyConfigDidChange)) { _ in
          config = MyttyConfig.load()
          if let error = config.parseError {
            print("[Mytty] Config parse error: \(error)", to: &standardError)
          }
        }
        .onAppear {
          if persistenceService == nil {
            let ps = PersistenceService(store: store)
            ps.restore()
            ps.startObserving()
            persistenceService = ps
          }
          if ipcListener == nil {
            let service = MyttyIPCService(store: store)
            let listener = IPCListener(service: service)
            listener.start()
            ipcListener = listener
          }
          if dropdownController == nil {
            dropdownController = DropdownController(store: store)
            let monitor = GlobalHotkeyMonitor()
            monitor.enable()
            hotkeyMonitor = monitor
          }
        }
    }
    .commands {
      CommandGroup(replacing: .newItem) {
        Button("New Session") { commands?.sessionManager() }
          .keyboardShortcut("n")
        Divider()
        Button("Close Pane") { commands?.closePane() }
          .keyboardShortcut(from: config.keybindingStore.trigger(for: "close-pane", in: .global))
        Button("Close Tab") { commands?.closeTab() }
          .keyboardShortcut(from: config.keybindingStore.trigger(for: "close-tab", in: .global))
      }
      CommandGroup(replacing: .undoRedo) { EmptyView() }
      CommandGroup(replacing: .pasteboard) { EmptyView() }
      CommandGroup(replacing: .textEditing) { EmptyView() }
      CommandGroup(replacing: .printItem) { EmptyView() }
      CommandGroup(after: .toolbar) {
        Divider()

        // TODO: font size shortcuts (Cmd+/-, Cmd+0) are handled by libghostty
        // via keyDown. Adding menu items here would intercept them. Consider
        // migrating to AppKit menus (NSMenu) for full control over shortcut
        // routing, matching Ghostty's approach.

        Button("Toggle Sidebar") {
          commands?.toggleSidebar()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "toggle-sidebar", in: .global))

        Button("Toggle Tab Bar") {
          commands?.toggleTabBar()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "toggle-tab-bar", in: .global))

        Button("New Tab") {
          commands?.newTab()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "new-tab", in: .global))

        Button("Split Pane Horizontally") {
          commands?.splitHorizontal()
        }
        .keyboardShortcut(
          from: config.keybindingStore.trigger(for: "split-horizontal", in: .global))

        Button("Split Pane Vertically") {
          commands?.splitVertical()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "split-vertical", in: .global))

        Button("Session Manager") {
          commands?.sessionManager()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "session-manager", in: .global))

        Divider()

        Button("Window Mode") {
          commands?.windowMode()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "window-mode", in: .global))

        Button("Copy Mode") {
          commands?.copyMode()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "copy-mode", in: .global))

        Button("Which-Key") {
          commands?.whichKey()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "which-key", in: .global))

        Divider()

        Button("Rename Tab") {
          NotificationCenter.default.post(name: .myttyRenameTab, object: nil)
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "rename-tab", in: .global))

        Button("Rename Session") {
          NotificationCenter.default.post(name: .myttyRenameSession, object: nil)
        }

        Divider()

        ForEach(1...9, id: \.self) { index in
          Button("Focus Tab \(index)") {
            commands?.focusTab(index - 1)
          }
          .keyboardShortcut(
            from: config.keybindingStore.trigger(for: "focus-tab-\(index)", in: .global))
        }

        Button("Next Tab") {
          commands?.nextTab()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "next-tab", in: .global))

        Button("Previous Tab") {
          commands?.prevTab()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "previous-tab", in: .global))

        Button("Previous Session") {
          commands?.prevSession()
        }
        .keyboardShortcut(
          from: config.keybindingStore.trigger(for: "previous-session", in: .global))

        Button("Next Session") {
          commands?.nextSession()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "next-session", in: .global))

        Divider()

        Button("Previous Prompt") {
          commands?.jumpToPreviousPrompt()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "previous-prompt", in: .global))

        Button("Next Prompt") {
          commands?.jumpToNextPrompt()
        }
        .keyboardShortcut(from: config.keybindingStore.trigger(for: "next-prompt", in: .global))

        Divider()

        Button("Toggle Dropdown Terminal") {
          dropdownController?.toggle()
        }
        .keyboardShortcut("`", modifiers: .control)

        ForEach(Array(config.popups.enumerated()), id: \.offset) { _, popup in
          if let key = parseShortcutKey(popup.shortcut),
            let modifiers = parseShortcutModifiers(popup.shortcut) {
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

private struct StandardError: TextOutputStream {
  mutating func write(_ string: String) {
    FileHandle.standardError.write(Data(string.utf8))
  }
}
nonisolated(unsafe) private var standardError = StandardError()

extension Notification.Name {
  static let myttyRenameTab = Notification.Name("myttyRenameTab")
  static let myttyRenameSession = Notification.Name("myttyRenameSession")
  static let myttyConfigDidChange = Notification.Name("myttyConfigDidChange")
  static let myttyDropdownHotkeyPressed = Notification.Name("myttyDropdownHotkeyPressed")
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
