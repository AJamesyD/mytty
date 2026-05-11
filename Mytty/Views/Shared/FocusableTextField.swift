import AppKit
import SwiftUI

struct HighlightedText: View {
  let text: String
  let indices: Set<Int>

  var body: some View {
    if indices.isEmpty {
      Text(text)
    } else {
      text.enumerated().reduce(Text("")) { result, pair in
        let char = String(pair.element)
        return result
          + Text(char)
          .foregroundColor(indices.contains(pair.offset) ? .accentColor : .primary)
      }
    }
  }
}

/// An NSTextField wrapper that steals first responder on appear,
/// ensuring it gets keyboard input even when an NSView (like the terminal) has focus.
struct FocusableTextField: NSViewRepresentable {
  @Binding var text: String
  var placeholder: String
  var onComplete: (() -> Void)?
  var onMoveUp: (() -> Void)?
  var onMoveDown: (() -> Void)?
  var onConfirm: ((NSEvent.ModifierFlags) -> Void)?
  var onCancel: (() -> Void)?

  func makeNSView(context: Context) -> NSTextField {
    let field = NavigableTextField()
    field.onMoveUp = onMoveUp
    field.onMoveDown = onMoveDown
    field.placeholderString = placeholder
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.delegate = context.coordinator
    field.font = .systemFont(ofSize: 17)

    // Steal focus from the terminal on next run loop tick
    DispatchQueue.main.async {
      field.window?.makeFirstResponder(field)
    }

    return field
  }

  func updateNSView(_ nsView: NSTextField, context: Context) {
    if nsView.stringValue != text {
      nsView.stringValue = text
    }
    if let navigable = nsView as? NavigableTextField {
      navigable.onMoveUp = onMoveUp
      navigable.onMoveDown = onMoveDown
    }
    context.coordinator.onComplete = onComplete
    context.coordinator.onMoveUp = onMoveUp
    context.coordinator.onMoveDown = onMoveDown
    context.coordinator.onConfirm = onConfirm
    context.coordinator.onCancel = onCancel
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      text: $text,
      onComplete: onComplete,
      onMoveUp: onMoveUp,
      onMoveDown: onMoveDown,
      onConfirm: onConfirm,
      onCancel: onCancel
    )
  }

  private class NavigableTextField: NSTextField {
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?

    override func keyDown(with event: NSEvent) {
      if event.modifierFlags.contains(.control) {
        switch event.keyCode {
        case 38:
          onMoveDown?()
          return
        case 40:
          onMoveUp?()
          return
        default:
          break
        }
      }
      super.keyDown(with: event)
    }
  }

  class Coordinator: NSObject, NSTextFieldDelegate {
    var text: Binding<String>
    var onComplete: (() -> Void)?
    var onMoveUp: (() -> Void)?
    var onMoveDown: (() -> Void)?
    var onConfirm: ((NSEvent.ModifierFlags) -> Void)?
    var onCancel: (() -> Void)?

    init(
      text: Binding<String>,
      onComplete: (() -> Void)?,
      onMoveUp: (() -> Void)?,
      onMoveDown: (() -> Void)?,
      onConfirm: ((NSEvent.ModifierFlags) -> Void)?,
      onCancel: (() -> Void)?
    ) {
      self.text = text
      self.onComplete = onComplete
      self.onMoveUp = onMoveUp
      self.onMoveDown = onMoveDown
      self.onConfirm = onConfirm
      self.onCancel = onCancel
    }

    func controlTextDidChange(_ obj: Notification) {
      guard let field = obj.object as? NSTextField else { return }
      text.wrappedValue = field.stringValue
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector)
      -> Bool
    {
      if commandSelector == #selector(NSResponder.moveUp(_:)) {
        onMoveUp?()
        return true
      }
      if commandSelector == #selector(NSResponder.moveDown(_:)) {
        onMoveDown?()
        return true
      }
      if commandSelector == #selector(NSResponder.insertNewline(_:)) {
        onConfirm?(NSApp.currentEvent?.modifierFlags ?? [])
        return true
      }
      if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
        onCancel?()
        return true
      }
      if commandSelector == #selector(NSResponder.insertTab(_:)) {
        onComplete?()
        return true
      }
      if commandSelector == #selector(NSResponder.moveRight(_:)) {
        // Only complete if cursor is at the end
        if textView.selectedRange().location == textView.string.count {
          onComplete?()
          return true
        }
        return false
      }
      return false
    }
  }
}
