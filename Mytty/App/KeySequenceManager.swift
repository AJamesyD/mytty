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
  private(set) var pendingContinuations: [WhichKeyBinding]?
  private var trie = SequenceTrieNode()
  private var timeout: TimeInterval = 1.0
  private var timeoutTask: Task<Void, Never>?
  private var dispatch: ((String) -> Void)?
  private var surfaceForUnconsumed: (() -> ghostty_surface_t?)?
  private var showWhichKey: (([WhichKeyBinding]) -> Void)?
  private var hideWhichKey: (() -> Void)?
  private var whichKeyTask: Task<Void, Never>?

  func activate(
    trie: SequenceTrieNode,
    timeout: TimeInterval,
    dispatch: @escaping (String) -> Void,
    surfaceForUnconsumed: @escaping () -> ghostty_surface_t?,
    showWhichKey: (([WhichKeyBinding]) -> Void)? = nil,
    hideWhichKey: (() -> Void)? = nil
  ) {
    self.trie = trie
    self.timeout = timeout
    self.dispatch = dispatch
    self.surfaceForUnconsumed = surfaceForUnconsumed
    self.showWhichKey = showWhichKey
    self.hideWhichKey = hideWhichKey
  }

  func deactivate() {
    cancel()
    dispatch = nil
    surfaceForUnconsumed = nil
    showWhichKey = nil
    hideWhichKey = nil
    whichKeyTask?.cancel()
    whichKeyTask = nil
  }

  func reloadConfig(trie: SequenceTrieNode, timeout: TimeInterval) {
    cancel()
    self.trie = trie
    self.timeout = timeout
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    if Self.modifierKeycodes.contains(event.keyCode) {
      return event
    }

    guard let keyName = event.keyName else { return event }

    let mods = event.keyboardTriggerModifiers
    let trigger = KeyboardTrigger(prefix: nil, modifiers: mods, key: keyName)

    switch state {
    case .idle:
      guard let child = trie.children[trigger] else { return event }
      state = .pending(node: child, keys: [trigger])
      startTimeout()
      updatePendingDisplay(keys: [trigger])
      startWhichKeyDelay(for: child)
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
          let keyEvent = event.ghosttyKeyEvent(GHOSTTY_ACTION_PRESS)
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
      startWhichKeyDelay(for: child)
      return nil
    }
  }

  private func cancel() {
    state = .idle
    pendingDisplay = ""
    timeoutTask?.cancel()
    timeoutTask = nil
    whichKeyTask?.cancel()
    whichKeyTask = nil
    hideWhichKey?()
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

  private func startWhichKeyDelay(for node: SequenceTrieNode) {
    whichKeyTask?.cancel()
    hideWhichKey?()
    guard !node.children.isEmpty else { return }
    let bindings = continuations(from: node)
    whichKeyTask = Task {
      try? await Task.sleep(for: .milliseconds(500))
      guard !Task.isCancelled else { return }
      showWhichKey?(bindings)
    }
  }

  private func continuations(from node: SequenceTrieNode) -> [WhichKeyBinding] {
    node.children.compactMap { trigger, child in
      let label: String
      if let action = child.action {
        label = action
      } else {
        label = "..."
      }
      guard let key = trigger.key.first else { return nil }
      if child.action != nil {
        return WhichKeyBinding(key: key, action: .command(label: label, action: {}))
      }
      let subBindings = self.continuations(from: child)
      return WhichKeyBinding(key: key, action: .group(label: label, children: subBindings))
    }.sorted { String($0.key) < String($1.key) }
  }

  // macOS virtual keycodes for modifier-only keys (Cmd, Shift, Caps, Alt, Ctrl, Fn)
  private static let modifierKeycodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
}
