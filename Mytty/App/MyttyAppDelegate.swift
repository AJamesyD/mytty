import AppKit

@MainActor
class MyttyAppDelegate: NSObject, NSApplicationDelegate {
  private var isApplyingChrome = false
  private var isInFullscreen = false
  private var chromeMode: ChromeMode = .default
  private var observers: [any NSObjectProtocol] = []

  private enum ChromeMode {
    case `default`
    case hidden
    case undecorated
  }

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
      window.setFrameAutosaveName("MyttyMainWindow")
      applyWindowChrome(window)

      self.observers.append(
        NotificationCenter.default.addObserver(
          forName: NSWindow.didUpdateNotification,
          object: window,
          queue: .main
        ) { [weak self] note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated {
            guard let self, !self.isApplyingChrome, !self.isInFullscreen,
              let window
            else { return }
            switch self.chromeMode {
            case .hidden:
              if window.titleVisibility == .hidden,
                window.titlebarAppearsTransparent,
                window.standardWindowButton(.closeButton)?.isHidden == true
              {
                return
              }
              self.isApplyingChrome = true
              self.applyWindowChrome(window)
              self.isApplyingChrome = false
            case .undecorated:
              if !window.styleMask.contains(.titled) { return }
              self.isApplyingChrome = true
              self.applyWindowChrome(window)
              self.isApplyingChrome = false
            case .default:
              break
            }
          }
        })

      self.observers.append(
        NotificationCenter.default.addObserver(
          forName: NSWindow.willEnterFullScreenNotification,
          object: window,
          queue: .main
        ) { [weak self] _ in
          MainActor.assumeIsolated {
            self?.isInFullscreen = true
          }
        })

      self.observers.append(
        NotificationCenter.default.addObserver(
          forName: NSWindow.didExitFullScreenNotification,
          object: window,
          queue: .main
        ) { [weak self] note in
          let window = note.object as? NSWindow
          MainActor.assumeIsolated {
            guard let self, let window else { return }
            self.isInFullscreen = false
            self.applyWindowChrome(window)
          }
        })
    }
  }

  func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    true
  }

  private func applyWindowChrome(_ window: NSWindow) {
    let wc = GhosttyAppManager.shared.windowConfig

    if !wc.decorations {
      window.styleMask.remove(.titled)
      chromeMode = .undecorated
    } else if wc.titlebarStyle == "hidden" {
      window.styleMask.insert(.fullSizeContentView)
      window.titleVisibility = .hidden
      window.titlebarAppearsTransparent = true
      window.tabbingMode = .disallowed
      window.standardWindowButton(.closeButton)?.isHidden = true
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
      window.standardWindowButton(.zoomButton)?.isHidden = true
      chromeMode = .hidden
    } else {
      chromeMode = .default
    }

    if wc.windowButtons == "hidden" {
      window.standardWindowButton(.closeButton)?.isHidden = true
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
      window.standardWindowButton(.zoomButton)?.isHidden = true
    }
  }
}
