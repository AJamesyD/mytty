import AppKit

@MainActor @Observable
final class HintsModeManager {
  private(set) var state: HintsModeState = .inactive
  private var activeProvider: (any HintTargetProvider)?
  private var alphabet: String = "asdfghjkl"

  var isActive: Bool {
    if case .inactive = state { return false }
    return true
  }

  func activate(
    provider: any HintTargetProvider,
    geometry: HintsGeometry,
    alphabet: String = "asdfghjkl"
  ) {
    self.alphabet = alphabet
    self.activeProvider = provider
    let targets = provider.targets(in: geometry)
    let labels = LabelAssigner.assignLabels(targets: targets, alphabet: alphabet)
    state = .active(labels: labels, typed: "")
  }

  func deactivate() {
    state = .inactive
    activeProvider = nil
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard isActive else { return event }

    if event.keyName == "escape" {
      deactivate()
      return nil
    }

    if event.keyName == "delete" {
      if case .filtering(let labels, _, _) = state {
        state = .active(labels: labels, typed: "")
      }
      return nil
    }

    guard let chars = event.charactersIgnoringModifiers?.lowercased(),
      !chars.isEmpty
    else { return nil }

    let char = chars
    guard alphabet.contains(char) else { return nil }

    let allLabels: [HintLabel]
    let currentTyped: String
    switch state {
    case .active(let labels, let typed):
      allLabels = labels
      currentTyped = typed
    case .filtering(let labels, let typed, _):
      allLabels = labels
      currentTyped = typed
    default:
      return nil
    }

    let newTyped = currentTyped + char
    let remaining = allLabels.filter { $0.label.hasPrefix(newTyped) }

    if remaining.count == 1 {
      let label = remaining[0]
      let action = resolveAction(for: label, modifiers: event.modifierFlags)
      executeAction(label: label, action: action)
      deactivate()
    } else if remaining.isEmpty {
      deactivate()
    } else {
      state = .filtering(labels: allLabels, typed: newTyped, remaining: remaining)
    }
    return nil
  }

  func resolveAction(
    for label: HintLabel,
    modifiers: NSEvent.ModifierFlags
  ) -> HintAction {
    let available = label.target.availableActions
    if modifiers.contains(.shift) {
      if available.contains(.open) { return .open }
      if available.contains(.close) { return .close }
    }
    if modifiers.contains(.control) {
      if available.contains(.paste) { return .paste }
    }
    return label.target.defaultAction
  }

  private func executeAction(label: HintLabel, action: HintAction) {
    switch action {
    case .copy:
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(label.target.displayText, forType: .string)
    case .open:
      if let url = URL(string: label.target.displayText) {
        NSWorkspace.shared.open(url)
      }
    case .paste, .focus, .close:
      break
    }
  }
}
