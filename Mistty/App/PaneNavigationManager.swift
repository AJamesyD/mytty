import AppKit
import SwiftUI

@MainActor @Observable
final class PaneNavigationManager {
  @ObservationIgnored nonisolated(unsafe) private var monitor: Any?
  private var isActive = false
  private var store: SessionStore?
  var isSessionManagerShowing: () -> Bool = { false }

  func activate(store: SessionStore) {
    guard !isActive else { return }
    self.store = store
    isActive = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }
      guard event.modifierFlags.contains(.control),
        let chars = event.charactersIgnoringModifiers?.lowercased()
      else { return event }

      let direction: NavigationDirection
      switch chars {
      case "h": direction = .left
      case "j": direction = .down
      case "k": direction = .up
      case "l": direction = .right
      default: return event
      }

      // Don't intercept if session manager, window mode, or copy mode is active
      guard !isSessionManagerShowing(),
        store.activeSession?.activeTab?.isWindowModeActive != true,
        store.activeSession?.activeTab?.isCopyModeActive != true
      else { return event }

      guard let tab = store.activeSession?.activeTab,
        let pane = tab.activePane
      else { return event }

      // If running neovim, let the keypress through for smart-splits
      if pane.isRunningVimLike { return event }

      // Navigate between MistTY panes, only consume if navigation succeeds
      if let target = tab.layout.adjacentPane(from: pane, direction: direction) {
        tab.activePane = target
        DispatchQueue.main.async {
          target.surfaceView.window?.makeFirstResponder(target.surfaceView)
        }
        return nil  // Consume the event
      }
      return event  // No adjacent pane, pass through to terminal
    }
  }

  func deactivate() {
    guard isActive else { return }
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    store = nil
    isActive = false
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
