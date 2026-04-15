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
  @ObservationIgnored nonisolated(unsafe) private var monitor: Any?
  private var isActive = false
  private var store: SessionStore?
  private var navigationBindings: [NavigationKey: NavigationBinding] = [:]
  private var passthroughProcesses: [String] = KeybindingStore.defaultPassthroughProcesses
  var isSessionManagerShowing: () -> Bool = { false }

  func activate(store: SessionStore) {
    guard !isActive else { return }
    self.store = store
    isActive = true

    let keybindingStore = MisttyConfig.load().keybindingStore
    passthroughProcesses = keybindingStore.passthroughProcesses
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

    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyDown(event) ?? event
    }
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    // TODO: special keys (arrows, escape) return Unicode function chars here,
    // not names like "up". Matching only works for single-character keys for now.
    guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return event }

    let eventMods = modifiersFromEvent(event)
    let navKey = NavigationKey(key: chars, modifiers: eventMods)
    guard let binding = navigationBindings[navKey] else { return event }
    let direction = binding.direction

    if binding.isUnconsumed,
      let surface = store?.activeSession?.activeTab?.activePane?.surfaceView.surface
    {
      var keyEvent = ghostty_input_key_s()
      keyEvent.action = GHOSTTY_ACTION_PRESS
      keyEvent.keycode = UInt32(event.keyCode)
      keyEvent.mods = ghosttyMods(event.modifierFlags)
      keyEvent.consumed_mods = ghostty_input_mods_e(rawValue: 0)
      keyEvent.text = nil
      keyEvent.composing = false
      keyEvent.unshifted_codepoint = 0
      if let chars = event.characters(byApplyingModifiers: []),
        let codepoint = chars.unicodeScalars.first
      {
        keyEvent.unshifted_codepoint = codepoint.value
      }

      var flags = ghostty_binding_flags_e(0)
      if ghostty_surface_key_is_binding(surface, keyEvent, &flags) {
        return event
      }
    }

    guard !isSessionManagerShowing(),
      store?.activeSession?.activeTab?.isWindowModeActive != true,
      store?.activeSession?.activeTab?.isCopyModeActive != true
    else { return event }

    guard let tab = store?.activeSession?.activeTab,
      let pane = tab.activePane
    else { return event }

    if pane.vars["is-vim"] != nil { return event }
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

  func deactivate() {
    guard isActive else { return }
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    store = nil
    navigationBindings = [:]
    passthroughProcesses = KeybindingStore.defaultPassthroughProcesses
    isActive = false
  }

  private func modifiersFromEvent(_ event: NSEvent) -> Set<KeyboardTrigger.Modifier> {
    var mods: Set<KeyboardTrigger.Modifier> = []
    if event.modifierFlags.contains(.command) { mods.insert(.cmd) }
    if event.modifierFlags.contains(.control) { mods.insert(.ctrl) }
    if event.modifierFlags.contains(.option) { mods.insert(.alt) }
    if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
    return mods
  }

  private func ghosttyMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
    var raw: UInt32 = 0
    if flags.contains(.shift) { raw |= GHOSTTY_MODS_SHIFT.rawValue }
    if flags.contains(.control) { raw |= GHOSTTY_MODS_CTRL.rawValue }
    if flags.contains(.option) { raw |= GHOSTTY_MODS_ALT.rawValue }
    if flags.contains(.command) { raw |= GHOSTTY_MODS_SUPER.rawValue }
    if flags.contains(.capsLock) { raw |= GHOSTTY_MODS_CAPS.rawValue }
    return ghostty_input_mods_e(rawValue: raw)
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}

struct PaneNavigationModifier: ViewModifier {
  let store: SessionStore
  @Binding var showingSessionManager: Bool
  @State private var manager = PaneNavigationManager()

  func body(content: Content) -> some View {
    content
      .onAppear {
        manager.isSessionManagerShowing = { showingSessionManager }
        manager.activate(store: store)
      }
      .onDisappear {
        manager.deactivate()
      }
  }
}

extension View {
  func paneNavigation(store: SessionStore, showingSessionManager: Binding<Bool>) -> some View {
    modifier(PaneNavigationModifier(store: store, showingSessionManager: showingSessionManager))
  }
}
