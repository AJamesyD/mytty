import AppKit
import SwiftUI

enum WhichKeyAction {
  case group(label: String, children: [WhichKeyBinding])
  case command(label: String, shortcut: String?, action: @MainActor () -> Void)
}

struct WhichKeyBinding: Identifiable {
  var id: Character { key }
  let key: Character
  let action: WhichKeyAction
}

@MainActor @Observable
final class WhichKeyManager {
  private(set) var isActive = false
  private(set) var currentBindings: [WhichKeyBinding] = []
  private(set) var breadcrumb: [String] = []
  private var rootBindings: [WhichKeyBinding] = []
  private var bindingStack: [[WhichKeyBinding]] = []
  private var dismissTask: Task<Void, Never>?

  func activate(bindings: [WhichKeyBinding]) {
    guard !isActive else { return }
    rootBindings = bindings
    currentBindings = bindings
    breadcrumb = []
    bindingStack = []
    isActive = true
    resetTimeout()
  }

  func deactivate() {
    guard isActive else { return }
    isActive = false
    currentBindings = []
    rootBindings = []
    breadcrumb = []
    bindingStack = []
    dismissTask?.cancel()
    dismissTask = nil
  }

  func showContinuations(_ bindings: [WhichKeyBinding]) {
    currentBindings = bindings
    breadcrumb = []
    bindingStack = []
    isActive = true
    resetTimeout()
  }

  func hideContinuations() {
    isActive = false
    currentBindings = []
    breadcrumb = []
    bindingStack = []
    dismissTask?.cancel()
    dismissTask = nil
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard isActive else { return event }
    if event.modifierFlags.isDisjoint(with: [.command, .option]) == false {
      return event
    }
    guard let name = event.keyName else { return event }
    if name == "escape" {
      deactivate()
      return nil
    }
    if name == "delete" {
      if !breadcrumb.isEmpty {
        breadcrumb.removeLast()
        currentBindings = bindingStack.removeLast()
      }
      resetTimeout()
      return nil
    }
    // Multi-character keyName values (return, tab, space, arrows, etc.)
    // are not which-key bindings. Consume and ignore.
    guard name.count == 1, let key = name.first else { return nil }
    return handleKey(key) ? nil : event
  }

  /// Returns true if the key was consumed by which-key.
  func handleKey(_ key: Character) -> Bool {
    if key == "\u{1B}" {
      deactivate()
      return true
    }

    if key == "\u{7F}" {
      if !breadcrumb.isEmpty {
        breadcrumb.removeLast()
        currentBindings = bindingStack.removeLast()
      }
      resetTimeout()
      return true
    }

    resetTimeout()

    guard let binding = currentBindings.first(where: { $0.key == key }) else {
      return true
    }

    switch binding.action {
    case .command(_, _, let action):
      deactivate()
      action()
    case .group(let label, let children):
      bindingStack.append(currentBindings)
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

  static func buildBindings(
    registry: [AppAction],
    groups: [WhichKeyGroup],
    tabCount: Int,
    sessionCount: Int,
    paneCount: Int,
    keybindingStore: KeybindingStore
  ) -> [WhichKeyBinding] {
    let actionMap = Dictionary(uniqueKeysWithValues: registry.map { ($0.id, $0) })

    return groups.compactMap { group -> WhichKeyBinding? in
      let children = group.bindings.compactMap { node -> WhichKeyBinding? in
        if node.action.hasPrefix("focus-tab-"),
          let n = Int(node.action.dropFirst("focus-tab-".count)),
          n > tabCount
        {
          return nil
        }
        if node.action == "close-tab" && tabCount <= 1 { return nil }
        if node.action == "close-session" && sessionCount <= 1 { return nil }
        if node.action == "break-to-tab" && paneCount <= 1 { return nil }
        guard let action = actionMap[node.action],
          let key = node.key.first
        else { return nil }
        let shortcut = keybindingStore.trigger(for: node.action, in: .global)?.displayLabel
        return WhichKeyBinding(
          key: key,
          action: .command(label: action.label, shortcut: shortcut, action: action.handler)
        )
      }
      guard !children.isEmpty else { return nil }
      let groupKey = group.key.first ?? group.name.first ?? "?"
      let groupLabel = group.name.prefix(1).uppercased() + group.name.dropFirst()
      return WhichKeyBinding(
        key: groupKey,
        action: .group(label: groupLabel, children: children)
      )
    }
  }
}
