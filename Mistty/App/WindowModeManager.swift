import AppKit
import SwiftUI

@MainActor @Observable
final class WindowModeManager {
  nonisolated(unsafe) private var monitor: Any?
  private(set) var isActive = false
  private var store: SessionStore?
  var onNeedExitCopyMode: () -> Void = {}

  func activate(store: SessionStore) {
    guard !isActive else { return }
    self.store = store
    isActive = true

    if store.activeSession?.activeTab?.isCopyModeActive == true {
      onNeedExitCopyMode()
    }

    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      guard let self else { return event }

      // Join-pick mode: number keys select target tab
      if store.activeSession?.activeTab?.windowModeState == .joinPick {
        if event.keyCode == 53 {  // Escape, back to normal window mode
          store.activeSession?.activeTab?.windowModeState = .normal
          return nil
        }
        if let chars = event.characters, let num = Int(chars), num >= 1, num <= 9 {
          self.joinPaneToTab(targetIndex: num - 1, store: store)
          return nil
        }
        return nil  // Consume all other keys in join-pick mode
      }

      // Cmd+Arrow to resize
      if event.modifierFlags.contains(.command) {
        switch event.keyCode {
        case 123:  // Cmd+Left, shrink horizontal
          self.resizeActivePane(delta: -0.05, along: .horizontal, store: store)
          return nil
        case 124:  // Cmd+Right, grow horizontal
          self.resizeActivePane(delta: 0.05, along: .horizontal, store: store)
          return nil
        case 126:  // Cmd+Up, shrink vertical
          self.resizeActivePane(delta: -0.05, along: .vertical, store: store)
          return nil
        case 125:  // Cmd+Down, grow vertical
          self.resizeActivePane(delta: 0.05, along: .vertical, store: store)
          return nil
        default: break
        }
      }

      switch event.keyCode {
      case 53:  // Escape, exit window mode
        store.activeSession?.activeTab?.windowModeState = .inactive
        self.deactivate()
        return nil
      case 123:  // Left arrow
        self.swapActivePane(.left, store: store)
        return nil
      case 124:  // Right arrow
        self.swapActivePane(.right, store: store)
        return nil
      case 126:  // Up arrow
        self.swapActivePane(.up, store: store)
        return nil
      case 125:  // Down arrow
        self.swapActivePane(.down, store: store)
        return nil
      case 6:  // z, zoom toggle
        self.toggleZoom(store: store)
        return nil
      case 11:  // b, break pane to new tab
        self.breakPaneToTab(store: store)
        return nil
      case 15:  // r, rotate split direction
        self.rotateActivePane(store: store)
        return nil
      case 46:  // m, join pane to tab
        guard let tab = store.activeSession?.activeTab else { return nil }
        tab.windowModeState = .joinPick
        return nil
      case 18, 19, 20, 21, 23:  // 1-5: standard layouts
        if let tab = store.activeSession?.activeTab, tab.panes.count >= 2 {
          let standardLayout: StandardLayout =
            switch event.keyCode {
            case 18: .evenHorizontal
            case 19: .evenVertical
            case 20: .mainHorizontal
            case 21: .mainVertical
            case 23: .tiled
            default: .evenHorizontal
            }
          tab.applyStandardLayout(standardLayout)
          tab.windowModeState = .inactive
          self.deactivate()
        }
        return nil
      default:
        return event
      }
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

  func joinPaneToTab(targetIndex: Int, store: SessionStore) {
    guard let session = store.activeSession,
      let sourceTab = session.activeTab,
      let pane = sourceTab.activePane
    else { return }
    let targetTabs = session.tabs.filter { $0.id != sourceTab.id }
    guard targetIndex < targetTabs.count else { return }
    let targetTab = targetTabs[targetIndex]

    // Exit window mode before modifying tabs
    sourceTab.windowModeState = .inactive
    deactivate()

    sourceTab.closePane(pane)
    if sourceTab.panes.isEmpty { session.closeTab(sourceTab) }
    targetTab.addExistingPane(pane, direction: .horizontal)
    session.activeTab = targetTab
  }

  func breakPaneToTab(store: SessionStore) {
    guard let session = store.activeSession,
      let tab = session.activeTab,
      let pane = tab.activePane,
      tab.panes.count > 1
    else { return }  // Don't break if it's the only pane

    tab.windowModeState = .inactive
    deactivate()

    tab.closePane(pane)
    if tab.panes.isEmpty { session.closeTab(tab) }
    session.addTabWithPane(pane)
  }

  func toggleZoom(store: SessionStore) {
    guard let tab = store.activeSession?.activeTab else { return }
    if tab.zoomedPane != nil {
      tab.zoomedPane = nil
    } else {
      tab.zoomedPane = tab.activePane
    }
  }

  func swapActivePane(_ direction: NavigationDirection, store: SessionStore) {
    guard let tab = store.activeSession?.activeTab,
      let current = tab.activePane
    else { return }
    tab.layout.swapPane(current, direction: direction)
  }

  func rotateActivePane(store: SessionStore) {
    guard let tab = store.activeSession?.activeTab,
      let pane = tab.activePane
    else { return }
    tab.layout.rotateDirection(containing: pane)
  }

  func resizeActivePane(delta: CGFloat, along direction: SplitDirection, store: SessionStore) {
    guard let tab = store.activeSession?.activeTab,
      let pane = tab.activePane
    else { return }
    tab.layout.resizeSplit(containing: pane, delta: delta, along: direction)
  }

  deinit {
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
  }
}
