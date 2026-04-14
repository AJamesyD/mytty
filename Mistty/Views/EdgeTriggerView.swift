import AppKit
import SwiftUI

struct EdgeTriggerView: NSViewRepresentable {
  var dwellDuration: TimeInterval = 0.15
  var dismissDelay: TimeInterval = 0.3
  var onReveal: () -> Void
  var onDismiss: () -> Void

  func makeNSView(context: Context) -> NSView {
    let view = TriggerNSView()
    view.alphaValue = 0
    let area = NSTrackingArea(
      rect: .zero,
      options: [.mouseEnteredAndExited, .inVisibleRect, .activeInKeyWindow],
      owner: context.coordinator,
      userInfo: nil
    )
    view.addTrackingArea(area)
    return view
  }

  func updateNSView(_ nsView: NSView, context: Context) {
    context.coordinator.dwellDuration = dwellDuration
    context.coordinator.dismissDelay = dismissDelay
    context.coordinator.onReveal = onReveal
    context.coordinator.onDismiss = onDismiss
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(
      dwellDuration: dwellDuration,
      dismissDelay: dismissDelay,
      onReveal: onReveal,
      onDismiss: onDismiss
    )
  }

  final class TriggerNSView: NSView {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  }

  final class Coordinator: NSResponder {
    var dwellDuration: TimeInterval
    var dismissDelay: TimeInterval
    var onReveal: () -> Void
    var onDismiss: () -> Void
    private var dwellWork: DispatchWorkItem?
    private var dismissWork: DispatchWorkItem?

    init(
      dwellDuration: TimeInterval,
      dismissDelay: TimeInterval,
      onReveal: @escaping () -> Void,
      onDismiss: @escaping () -> Void
    ) {
      self.dwellDuration = dwellDuration
      self.dismissDelay = dismissDelay
      self.onReveal = onReveal
      self.onDismiss = onDismiss
      super.init()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func mouseEntered(with event: NSEvent) {
      dismissWork?.cancel()
      dismissWork = nil
      let work = DispatchWorkItem { [weak self] in
        self?.onReveal()
      }
      dwellWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + dwellDuration, execute: work)
    }

    override func mouseExited(with event: NSEvent) {
      dwellWork?.cancel()
      dwellWork = nil
      let work = DispatchWorkItem { [weak self] in
        self?.onDismiss()
      }
      dismissWork = work
      DispatchQueue.main.asyncAfter(deadline: .now() + dismissDelay, execute: work)
    }

    func cancelAll() {
      dwellWork?.cancel()
      dismissWork?.cancel()
      dwellWork = nil
      dismissWork = nil
    }
  }
}
