import AppKit
import Foundation
import GhosttyKit

enum KeySequenceState {
  case idle
  case pending(node: SequenceTrieNode, keys: [KeyboardTrigger])
}

@MainActor @Observable
final class KeySequenceManager {
  private(set) var state: KeySequenceState = .idle
  private(set) var pendingDisplay: String = ""
  private var trie: SequenceTrieNode = SequenceTrieNode()
  private var timeout: TimeInterval = 1.0
  private var timeoutTask: Task<Void, Never>?
  private var dispatch: ((String) -> Void)?
  private var isWindowModeActive: (() -> Bool)?
  private var isCopyModeActive: (() -> Bool)?
  private var surfaceForUnconsumed: (() -> ghostty_surface_t?)?

  func activate(
    trie: SequenceTrieNode,
    timeout: TimeInterval,
    dispatch: @escaping (String) -> Void,
    isWindowModeActive: @escaping () -> Bool,
    isCopyModeActive: @escaping () -> Bool,
    surfaceForUnconsumed: @escaping () -> ghostty_surface_t?
  ) {
    self.trie = trie
    self.timeout = timeout
    self.dispatch = dispatch
    self.isWindowModeActive = isWindowModeActive
    self.isCopyModeActive = isCopyModeActive
    self.surfaceForUnconsumed = surfaceForUnconsumed
  }

  func deactivate() {
    cancel()
    dispatch = nil
    isWindowModeActive = nil
    isCopyModeActive = nil
    surfaceForUnconsumed = nil
  }

  func reloadConfig(trie: SequenceTrieNode, timeout: TimeInterval) {
    cancel()
    self.trie = trie
    self.timeout = timeout
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if isWindowModeActive?() == true || isCopyModeActive?() == true {
      if case .pending = state { cancel() }
      return event
    }

    if Self.modifierKeycodes.contains(event.keyCode) {
      return event
    }

    let keyName: String
    if let name = Self.keycodeNames[event.keyCode] {
      keyName = name
    } else {
      guard let chars = event.characters(byApplyingModifiers: [])?.lowercased() else {
        return event
      }
      keyName = chars
    }

    let mods = modifiersFromEvent(event)
    let trigger = KeyboardTrigger(prefix: nil, modifiers: mods, key: keyName)

    switch state {
    case .idle:
      guard let child = trie.children[trigger] else { return event }
      state = .pending(node: child, keys: [trigger])
      startTimeout()
      updatePendingDisplay(keys: [trigger])
      return nil

    case .pending(let node, let keys):
      let escTrigger = KeyboardTrigger(prefix: nil, modifiers: [], key: "escape")
      if keyName == "escape" && node.children[escTrigger] == nil {
        cancel()
        return nil
      }

      guard let child = node.children[trigger] else {
        cancel()
        return nil
      }

      if let action = child.action {
        if child.isUnconsumed, let surface = surfaceForUnconsumed?() {
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
            cancel()
            return nil
          }
        }
        dispatch?(action)
        cancel()
        return nil
      }

      let newKeys = keys + [trigger]
      state = .pending(node: child, keys: newKeys)
      startTimeout()
      updatePendingDisplay(keys: newKeys)
      return nil
    }
  }

  private func cancel() {
    state = .idle
    pendingDisplay = ""
    timeoutTask?.cancel()
    timeoutTask = nil
  }

  private func startTimeout() {
    timeoutTask?.cancel()
    guard timeout > 0 else { return }
    let duration = timeout
    timeoutTask = Task {
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      guard !Task.isCancelled else { return }
      cancel()
    }
  }

  private func updatePendingDisplay(keys: [KeyboardTrigger]) {
    pendingDisplay = keys.map { TriggerParser.normalize($0) }.joined(separator: " > ") + " ..."
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

  // macOS virtual keycodes for modifier-only keys (Cmd, Shift, Caps, Alt, Ctrl, Fn)
  private static let modifierKeycodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

  private static let keycodeNames: [UInt16: String] = [
    53: "escape",
    123: "left",
    124: "right",
    125: "down",
    126: "up",
    36: "return",
    48: "tab",
    49: "space",
    51: "delete",
    115: "home",
    119: "end",
    116: "pageup",
    121: "pagedown",
  ]
}
