import AppKit

@MainActor @Observable
final class ModalKeyDispatcher {
  @ObservationIgnored nonisolated(unsafe) private var monitor: Any?
  @ObservationIgnored weak var window: NSWindow?

  var sessionManagerKeyHandler: ((NSEvent) -> NSEvent?)?
  var whichKeyHandler: ((NSEvent) -> NSEvent?)?
  var copyModeHandler: ((NSEvent) -> NSEvent?)?
  var windowModeHandler: ((NSEvent) -> NSEvent?)?

  func activate() {
    guard monitor == nil else { return }
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyDown(event) ?? event
    }
  }

  func deactivate() {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
  }

  private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard event.window === window else { return event }
    if let handler = sessionManagerKeyHandler, handler(event) == nil {
      return nil
    }
    if let handler = whichKeyHandler, handler(event) == nil {
      return nil
    }
    if let handler = copyModeHandler, handler(event) == nil {
      return nil
    }
    if let handler = windowModeHandler, handler(event) == nil {
      return nil
    }
    return event
  }
}
