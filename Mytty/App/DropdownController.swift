import AppKit
import SwiftUI

@MainActor
class DropdownController: NSObject, NSWindowDelegate {
  private(set) var visible = false
  private var previousApp: NSRunningApplication?
  private let panel: DropdownPanel
  private var session: MyttySession?
  private let store: SessionStore

  init(store: SessionStore) {
    self.store = store
    self.panel = DropdownPanel()
    super.init()
    panel.delegate = self
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(applicationWillTerminate(_:)),
      name: NSApplication.willTerminateNotification,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(surfaceDidClose(_:)),
      name: .ghosttyCloseSurface,
      object: nil
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(hotkeyPressed),
      name: .myttyDropdownHotkeyPressed,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  func toggle() {
    if visible {
      animateOut()
    } else {
      animateIn()
    }
  }

  private func animateIn() {
    guard !visible else { return }
    visible = true

    let config = MyttyConfig.load()
    let position = config.dropdownPosition
    let sizeFraction = Double(config.dropdownSize) / 100.0

    if !NSApp.isActive {
      if let front = NSWorkspace.shared.frontmostApplication,
        front.bundleIdentifier != Bundle.main.bundleIdentifier
      {
        previousApp = front
      }
    }

    if session == nil {
      let home = FileManager.default.homeDirectoryForCurrentUser
      let s = store.createDetachedSession(name: "Dropdown", directory: home)
      session = s
      guard let pane = s.activeTab?.activePane else { return }
      // Set the panel frame before creating the hosting view so the terminal
      // surface initializes with the correct size instead of zero.
      guard
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
          ?? NSScreen.main
          ?? NSScreen.screens.first
      else { return }
      let visibleFrame = screen.visibleFrame
      let (initialFrame, _) = frames(
        for: position, size: sizeFraction, visibleFrame: visibleFrame)
      panel.setFrame(initialFrame, display: false)
      let hostingView = NSHostingView(rootView: PaneView(pane: pane, isActive: true))
      panel.contentView = hostingView
    }

    guard
      let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })
        ?? NSScreen.main
        ?? NSScreen.screens.first
    else { return }
    let visibleFrame = screen.visibleFrame
    let (initialFrame, finalFrame) = frames(
      for: position, size: sizeFraction, visibleFrame: visibleFrame)

    panel.setFrame(initialFrame, display: false)
    panel.alphaValue = 0
    panel.level = .popUpMenu
    panel.orderFrontRegardless()

    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.2
        context.timingFunction = .init(name: .easeIn)
        panel.animator().setFrame(finalFrame, display: true)
        panel.animator().alphaValue = 1
      },
      completionHandler: {
        MainActor.assumeIsolated { [self] in
          guard visible else { return }
          panel.level = .floating
          NSApp.activate()
          makeWindowKey(retries: 10)
        }
      })
  }

  private func animateOut() {
    guard visible else { return }
    visible = false

    if !panel.isOnActiveSpace {
      previousApp = nil
      panel.orderOut(self)
      return
    }

    if let prev = previousApp {
      previousApp = nil
      if !prev.isTerminated {
        prev.activate(options: [])
      }
    }

    let config = MyttyConfig.load()
    let position = config.dropdownPosition
    let sizeFraction = Double(config.dropdownSize) / 100.0
    guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
    let visibleFrame = screen.visibleFrame
    let (initialFrame, _) = frames(
      for: position, size: sizeFraction, visibleFrame: visibleFrame)

    panel.level = .popUpMenu

    NSAnimationContext.runAnimationGroup(
      { context in
        context.duration = 0.2
        context.timingFunction = .init(name: .easeOut)
        panel.animator().setFrame(initialFrame, display: true)
        panel.animator().alphaValue = 0
      },
      completionHandler: {
        MainActor.assumeIsolated { [self] in
          panel.orderOut(self)
        }
      })
  }

  private func frames(
    for position: DropdownPosition, size: Double, visibleFrame: NSRect
  ) -> (initial: NSRect, final: NSRect) {
    switch position {
    case .top:
      let h = visibleFrame.height * size
      let w = visibleFrame.width
      let initial = NSRect(x: visibleFrame.minX, y: visibleFrame.maxY, width: w, height: h)
      let dest = NSRect(x: visibleFrame.minX, y: visibleFrame.maxY - h, width: w, height: h)
      return (initial, dest)
    case .bottom:
      let h = visibleFrame.height * size
      let w = visibleFrame.width
      let initial = NSRect(x: visibleFrame.minX, y: visibleFrame.minY - h, width: w, height: h)
      let dest = NSRect(x: visibleFrame.minX, y: visibleFrame.minY, width: w, height: h)
      return (initial, dest)
    case .left:
      let w = visibleFrame.width * size
      let h = visibleFrame.height
      let initial = NSRect(x: visibleFrame.minX - w, y: visibleFrame.minY, width: w, height: h)
      let dest = NSRect(x: visibleFrame.minX, y: visibleFrame.minY, width: w, height: h)
      return (initial, dest)
    case .right:
      let w = visibleFrame.width * size
      let h = visibleFrame.height
      let initial = NSRect(x: visibleFrame.maxX, y: visibleFrame.minY, width: w, height: h)
      let dest = NSRect(x: visibleFrame.maxX - w, y: visibleFrame.minY, width: w, height: h)
      return (initial, dest)
    }
  }

  private func makeWindowKey(retries: UInt8 = 0) {
    guard visible else { return }
    guard let pane = session?.activeTab?.activePane else { return }

    panel.makeKeyAndOrderFront(nil)
    panel.makeFirstResponder(pane.surfaceView)

    // Force the surface to pick up the panel's actual size. The surface may
    // have been created before the hosting view completed layout.
    let surfaceView = pane.surfaceView
    if surfaceView.frame.size != .zero {
      surfaceView.setFrameSize(surfaceView.frame.size)
    }

    guard !panel.isKeyWindow, retries > 0 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(25)) { [self] in
      makeWindowKey(retries: retries - 1)
    }
  }

  // MARK: - NSWindowDelegate

  nonisolated func windowDidResignKey(_ notification: Notification) {
    Task { @MainActor in
      guard visible else { return }
      guard panel.attachedSheet == nil else { return }
      if NSApp.isActive {
        previousApp = nil
      }
      animateOut()
    }
  }

  // MARK: - Notifications

  @objc private func applicationWillTerminate(_ notification: Notification) {
    panel.orderOut(self)
  }

  @objc private func hotkeyPressed() {
    toggle()
  }

  @objc private func surfaceDidClose(_ notification: Notification) {
    guard let p = notification.payload(PanePayload.self), let closedPaneID = p.paneID else {
      return
    }
    guard let pane = session?.activeTab?.activePane, pane.id == closedPaneID else { return }
    session = nil
    panel.contentView = nil
  }
}
