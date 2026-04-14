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
      guard let self else { return event }
      // Pass through events with command/option modifiers (Cmd+Q, Cmd+W, etc.)
      if event.modifierFlags.intersection([.command, .option]).isEmpty == false {
        return event
      }
      guard let chars = event.charactersIgnoringModifiers,
        let key = chars.first
      else { return event }
      return self.handleKey(key) ? nil : event
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

  static func defaultBindings(store: SessionStore) -> [WhichKeyBinding] {
    [
      WhichKeyBinding(
        key: "w",
        action: .group(
          label: "Windows",
          children: [
            WhichKeyBinding(
              key: "h",
              action: .command(label: "Swap Left") {
                guard let tab = store.activeSession?.activeTab,
                  let pane = tab.activePane
                else { return }
                tab.layout.swapPane(pane, direction: .left)
              }),
            WhichKeyBinding(
              key: "j",
              action: .command(label: "Swap Down") {
                guard let tab = store.activeSession?.activeTab,
                  let pane = tab.activePane
                else { return }
                tab.layout.swapPane(pane, direction: .down)
              }),
            WhichKeyBinding(
              key: "k",
              action: .command(label: "Swap Up") {
                guard let tab = store.activeSession?.activeTab,
                  let pane = tab.activePane
                else { return }
                tab.layout.swapPane(pane, direction: .up)
              }),
            WhichKeyBinding(
              key: "l",
              action: .command(label: "Swap Right") {
                guard let tab = store.activeSession?.activeTab,
                  let pane = tab.activePane
                else { return }
                tab.layout.swapPane(pane, direction: .right)
              }),
            WhichKeyBinding(
              key: "z",
              action: .command(label: "Zoom") {
                guard let tab = store.activeSession?.activeTab else { return }
                tab.zoomedPane = tab.zoomedPane != nil ? nil : tab.activePane
              }),
            WhichKeyBinding(
              key: "b",
              action: .command(label: "Break to Tab") {
                guard let session = store.activeSession,
                  let tab = session.activeTab,
                  let pane = tab.activePane,
                  tab.panes.count > 1
                else { return }
                tab.closePane(pane)
                if tab.panes.isEmpty { session.closeTab(tab) }
                session.addTabWithPane(pane)
              }),
            WhichKeyBinding(
              key: "r",
              action: .command(label: "Rotate") {
                guard let tab = store.activeSession?.activeTab,
                  let pane = tab.activePane
                else { return }
                tab.layout.rotateDirection(containing: pane)
              }),
            WhichKeyBinding(
              key: "=",
              action: .command(label: "Even Layout") {
                guard let tab = store.activeSession?.activeTab,
                  tab.panes.count >= 2
                else { return }
                tab.applyStandardLayout(.evenHorizontal)
              }),
          ])),
      WhichKeyBinding(
        key: "p",
        action: .group(
          label: "Panes",
          children: [
            WhichKeyBinding(
              key: "v",
              action: .command(label: "Vertical Split") {
                NotificationCenter.default.post(name: .misttySplitVertical, object: nil)
              }),
            WhichKeyBinding(
              key: "h",
              action: .command(label: "Horizontal Split") {
                NotificationCenter.default.post(name: .misttySplitHorizontal, object: nil)
              }),
            WhichKeyBinding(
              key: "x",
              action: .command(label: "Close Pane") {
                NotificationCenter.default.post(name: .misttyClosePane, object: nil)
              }),
          ])),
      WhichKeyBinding(
        key: "s",
        action: .group(
          label: "Sessions",
          children: [
            WhichKeyBinding(
              key: "n",
              action: .command(label: "New Session") {
                store.createSession(
                  name: "New Session",
                  directory: FileManager.default.homeDirectoryForCurrentUser)
              }),
            WhichKeyBinding(
              key: "j",
              action: .command(label: "Session Manager") {
                NotificationCenter.default.post(name: .misttySessionManager, object: nil)
              }),
            WhichKeyBinding(
              key: "c",
              action: .command(label: "Close Session") {
                guard let session = store.activeSession else { return }
                store.closeSession(session)
              }),
          ])),
      WhichKeyBinding(
        key: "t",
        action: .group(
          label: "Tabs",
          children: [
            WhichKeyBinding(
              key: "n",
              action: .command(label: "New Tab") {
                NotificationCenter.default.post(name: .misttyNewTab, object: nil)
              }),
            WhichKeyBinding(
              key: "x",
              action: .command(label: "Close Tab") {
                NotificationCenter.default.post(name: .misttyCloseTab, object: nil)
              }),
          ]
            + (1...9).map { i in
              WhichKeyBinding(
                key: Character("\(i)"),
                action: .command(label: "Tab \(i)") {
                  NotificationCenter.default.post(
                    name: .misttyFocusTabByIndex,
                    object: nil,
                    userInfo: ["index": i - 1])
                })
            })),
    ]
  }
}
