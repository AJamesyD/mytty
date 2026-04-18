import AppKit

@MainActor
class MyttyAppDelegate: NSObject, NSApplicationDelegate {
  private var enforcedStyleMask: NSWindow.StyleMask?

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    UserDefaults.standard.set(false, forKey: "ApplePressAndHoldEnabled")
    UserDefaults.standard.set(false, forKey: "NSFullScreenMenuItemEverywhere")
    UserDefaults.standard.set(false, forKey: "NSAutoFillHeuristicControllerEnabled")
    UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

    DispatchQueue.main.async { [self] in
      guard let window = NSApplication.shared.windows.first else { return }
      applyWindowChrome(window)

      NotificationCenter.default.addObserver(
        forName: NSWindow.didUpdateNotification,
        object: window,
        queue: .main
      ) { [weak self] note in
        let window = note.object as? NSWindow
        MainActor.assumeIsolated {
          guard let self, let mask = self.enforcedStyleMask,
            let window, window.styleMask != mask
          else { return }
          window.styleMask = mask
        }
      }

      NotificationCenter.default.addObserver(
        forName: NSWindow.willEnterFullScreenNotification,
        object: window,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.enforcedStyleMask = nil
        }
      }

      NotificationCenter.default.addObserver(
        forName: NSWindow.didExitFullScreenNotification,
        object: window,
        queue: .main
      ) { [weak self] note in
        let window = note.object as? NSWindow
        MainActor.assumeIsolated {
          guard let self, let window else { return }
          self.applyWindowChrome(window)
        }
      }
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  private func applyWindowChrome(_ window: NSWindow) {
    let wc = GhosttyAppManager.shared.windowConfig
    if !wc.decorations || wc.titlebarStyle == "hidden" {
      window.styleMask.remove(.titled)
      enforcedStyleMask = window.styleMask
      if wc.titlebarStyle == "hidden" {
        window.isMovableByWindowBackground = true
        window.contentView?.wantsLayer = true
        window.contentView?.layer?.cornerRadius = 16
        window.contentView?.layer?.masksToBounds = true
      }
    }
    if wc.windowButtons == "hidden" || wc.titlebarStyle == "hidden" {
      window.standardWindowButton(.closeButton)?.isHidden = true
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
      window.standardWindowButton(.zoomButton)?.isHidden = true
    }
  }
}
