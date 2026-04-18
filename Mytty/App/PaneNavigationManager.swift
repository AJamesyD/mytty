import AppKit
import GhosttyKit
import SwiftUI

private struct NavigationKey: Hashable {
  let key: String
  let modifiers: Set<KeyboardTrigger.Modifier>
}

private struct NavigationBinding {
  let direction: NavigationDirection
  let isUnconsumed: Bool
}

@MainActor @Observable
final class PaneNavigationManager {
  private var isActive = false
  private var store: SessionStore?
  private var navigationBindings: [NavigationKey: NavigationBinding] = [:]
  private var passthroughProcesses: [String] = KeybindingStore.defaultPassthroughProcesses
  var sequenceManager: KeySequenceManager?

  func activate(store: SessionStore) {
    guard !isActive else { return }
    self.store = store
    isActive = true

    loadBindings()

    TerminalSurfaceView.keyDispatch = { [weak self] event in
      self?.handleKeyDown(event) ?? event
    }
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if KeyEventDebug.enabled {
      KeyEventDebug.log("PaneNav.in", event)
    }

    if let sequenceManager, sequenceManager.handleKeyDown(event) == nil {
      if KeyEventDebug.enabled { KeyEventDebug.print("PaneNav: consumed by sequenceManager") }
      return nil
    }

    guard let key = event.keyName else { return event }

    let eventMods = event.keyboardTriggerModifiers
    let navKey = NavigationKey(key: key, modifiers: eventMods)
    guard let binding = navigationBindings[navKey] else { return event }
    let direction = binding.direction

    if binding.isUnconsumed,
      let surface = store?.activeSession?.activeTab?.activePane?.surfaceView.surface
    {
      let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)

      var flags = ghostty_binding_flags_e(0)
      if ghostty_surface_key_is_binding(surface, keyEvent, &flags) {
        return event
      }
    }

    guard let tab = store?.activeSession?.activeTab,
      let pane = tab.activePane
    else { return event }

    if pane.isPassthroughProcess(processes: passthroughProcesses) { return event }

    if let target = tab.layout.adjacentPane(from: pane, direction: direction) {
      tab.activePane = target
      DispatchQueue.main.async {
        target.surfaceView.window?.makeFirstResponder(target.surfaceView)
      }
      return nil
    }
    return event
  }

  func reloadConfig() {
    guard isActive else { return }
    loadBindings()
    let config = MyttyConfig.load().keybindingStore
    sequenceManager?.reloadConfig(trie: config.sequenceTrie, timeout: config.sequenceTimeout)
  }

  func deactivate() {
    guard isActive else { return }
    TerminalSurfaceView.keyDispatch = nil
    store = nil
    navigationBindings = [:]
    passthroughProcesses = KeybindingStore.defaultPassthroughProcesses
    isActive = false
  }

  private func loadBindings() {
    let keybindingStore = MyttyConfig.load().keybindingStore
    passthroughProcesses = keybindingStore.passthroughProcesses
    navigationBindings = [:]
    let actionToDirection: [String: NavigationDirection] = [
      "navigate-left": .left,
      "navigate-down": .down,
      "navigate-up": .up,
      "navigate-right": .right,
    ]
    for (action, direction) in actionToDirection {
      if let trigger = keybindingStore.trigger(for: action, in: .global) {
        let navKey = NavigationKey(key: trigger.key, modifiers: trigger.modifiers)
        navigationBindings[navKey] = NavigationBinding(
          direction: direction,
          isUnconsumed: trigger.prefix == .unconsumed
        )
      }
    }
  }
}

struct PaneNavigationModifier: ViewModifier {
  let store: SessionStore
  var sequenceManager: KeySequenceManager?
  @State private var manager = PaneNavigationManager()

  func body(content: Content) -> some View {
    content
      .onAppear {
        manager.sequenceManager = sequenceManager
        manager.activate(store: store)
      }
      .onDisappear {
        manager.deactivate()
      }
      .onReceive(NotificationCenter.default.publisher(for: .myttyConfigDidChange)) { _ in
        manager.reloadConfig()
      }
  }
}

extension View {
  func paneNavigation(
    store: SessionStore,
    sequenceManager: KeySequenceManager?
  ) -> some View {
    modifier(
      PaneNavigationModifier(
        store: store,
        sequenceManager: sequenceManager
      ))
  }
}
