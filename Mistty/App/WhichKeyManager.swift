import AppKit
import SwiftUI

enum WhichKeyAction {
  case group(label: String, children: [WhichKeyBinding])
  case command(label: String, action: @MainActor () -> Void)
}

struct WhichKeyBinding: Identifiable {
  var id: Character { key }
  let key: Character
  let action: WhichKeyAction
}

@MainActor @Observable
final class WhichKeyManager {
  // NOTE: @ObservationIgnored prevents the @Observable macro from wrapping this
  // property with @ObservationTracked, which conflicts with nonisolated(unsafe)
  // on Swift 6.3. The monitor handle must be nonisolated for deinit access.
  @ObservationIgnored nonisolated(unsafe) private var monitor: Any?
  private(set) var isActive = false
  private(set) var currentBindings: [WhichKeyBinding] = []
  private(set) var breadcrumb: [String] = []
  private var rootBindings: [WhichKeyBinding] = []
  private var dismissTask: Task<Void, Never>?

  func activate(bindings: [WhichKeyBinding]) {
    guard !isActive else { return }
    rootBindings = bindings
    currentBindings = bindings
    breadcrumb = []
    isActive = true
    resetTimeout()

    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyDown(event) ?? event
    }
  }

  func deactivate() {
    guard isActive else { return }
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    isActive = false
    currentBindings = []
    rootBindings = []
    breadcrumb = []
    dismissTask?.cancel()
    dismissTask = nil
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if event.modifierFlags.intersection([.command, .option]).isEmpty == false {
      return event
    }
    guard let chars = event.charactersIgnoringModifiers,
      let key = chars.first
    else { return event }
    return handleKey(key) ? nil : event
  }

  /// Returns true if the key was consumed by which-key.
  func handleKey(_ key: Character) -> Bool {
    if key == "\u{1B}" {
      deactivate()
      return true
    }

    resetTimeout()

    guard let binding = currentBindings.first(where: { $0.key == key }) else {
      return false
    }

    switch binding.action {
    case .command(_, let action):
      deactivate()
      action()
    case .group(let label, let children):
      breadcrumb.append(label)
      currentBindings = children
    }
    return true
  }

  // NOTE: 3s matches macOS Dock's autohide-delay feel. Resets on each keypress
  // so navigating deep trees doesn't race the clock.
  private func resetTimeout() {
    dismissTask?.cancel()
    dismissTask = Task {
      try? await Task.sleep(for: .seconds(3))
      guard !Task.isCancelled else { return }
      deactivate()
    }
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }

  static func buildBindings(
    store: SessionStore,
    commands: TerminalCommands,
    groups: [WhichKeyGroup]
  ) -> [WhichKeyBinding] {
    var registry: [String: (label: String, action: @MainActor () -> Void)] = [
      "swap-left": ("Swap Left", {
        guard let tab = store.activeSession?.activeTab, let pane = tab.activePane else { return }
        tab.layout.swapPane(pane, direction: .left)
      }),
      "swap-down": ("Swap Down", {
        guard let tab = store.activeSession?.activeTab, let pane = tab.activePane else { return }
        tab.layout.swapPane(pane, direction: .down)
      }),
      "swap-up": ("Swap Up", {
        guard let tab = store.activeSession?.activeTab, let pane = tab.activePane else { return }
        tab.layout.swapPane(pane, direction: .up)
      }),
      "swap-right": ("Swap Right", {
        guard let tab = store.activeSession?.activeTab, let pane = tab.activePane else { return }
        tab.layout.swapPane(pane, direction: .right)
      }),
      "zoom": ("Zoom", {
        guard let tab = store.activeSession?.activeTab else { return }
        tab.zoomedPane = tab.zoomedPane != nil ? nil : tab.activePane
      }),
      "break-to-tab": ("Break to Tab", {
        guard let session = store.activeSession,
          let tab = session.activeTab,
          let pane = tab.activePane,
          tab.panes.count > 1
        else { return }
        tab.closePane(pane)
        if tab.panes.isEmpty { session.closeTab(tab) }
        session.addTabWithPane(pane)
      }),
      "rotate": ("Rotate", {
        guard let tab = store.activeSession?.activeTab, let pane = tab.activePane else { return }
        tab.layout.rotateDirection(containing: pane)
      }),
      "even-layout": ("Even Layout", {
        guard let tab = store.activeSession?.activeTab, tab.panes.count >= 2 else { return }
        tab.applyStandardLayout(.evenHorizontal)
      }),
      "split-vertical": ("Vertical Split", { commands.splitVertical() }),
      "split-horizontal": ("Horizontal Split", { commands.splitHorizontal() }),
      "close-pane": ("Close Pane", { commands.closePane() }),
      "new-session": ("New Session", {
        store.createSession(
          name: "New Session", directory: FileManager.default.homeDirectoryForCurrentUser)
      }),
      "session-manager": ("Session Manager", { commands.sessionManager() }),
      "close-session": ("Close Session", {
        guard let session = store.activeSession else { return }
        store.closeSession(session)
      }),
      "new-tab": ("New Tab", { commands.newTab() }),
      "close-tab": ("Close Tab", { commands.closeTab() }),
    ]
    for i in 1...9 {
      registry["focus-tab-\(i)"] = ("Tab \(i)", { commands.focusTab(i - 1) })
    }

    return groups.compactMap { group -> WhichKeyBinding? in
      let children = group.bindings.compactMap { node -> WhichKeyBinding? in
        guard let entry = registry[node.action],
          let key = node.key.first
        else { return nil }
        return WhichKeyBinding(
          key: key,
          action: .command(label: entry.label, action: entry.action)
        )
      }
      guard !children.isEmpty else { return nil }
      // Falls back to first character of name when key is empty (e.g. user-defined groups without explicit key)
      let groupKey = group.key.first ?? group.name.first ?? "?"
      let groupLabel = group.name.prefix(1).uppercased() + group.name.dropFirst()
      return WhichKeyBinding(
        key: groupKey,
        action: .group(label: groupLabel, children: children)
      )
    }
  }
}
