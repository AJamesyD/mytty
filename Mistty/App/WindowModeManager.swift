import AppKit
import SwiftUI

@MainActor @Observable
final class WindowModeManager {
  @ObservationIgnored nonisolated(unsafe) private var monitor: Any?
  private(set) var isActive = false
  private var store: SessionStore?
  private var actionLookup: [KeyboardTrigger: String] = [:]
  var onNeedExitCopyMode: () -> Void = {}

  func activate(store: SessionStore) {
    guard !isActive else { return }
    self.store = store
    let keybindingStore = MisttyConfig.load().keybindingStore
    actionLookup = keybindingStore.reverseLookup(in: .windowMode)
    isActive = true

    if store.activeSession?.activeTab?.isCopyModeActive == true {
      onNeedExitCopyMode()
    }

    monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      self?.handleKeyDown(event) ?? event
    }
  }

  func deactivate() {
    guard isActive else { return }
    if let monitor {
      NSEvent.removeMonitor(monitor)
    }
    monitor = nil
    store = nil
    actionLookup = [:]
    isActive = false
  }

  private static let keycodeNames: [UInt16: String] = [
    53: "escape",
    123: "left",
    124: "right",
    125: "down",
    126: "up",
    36: "return",
    48: "tab",
    49: "space",
    51: "delete",
  ]

  private func actionName(for event: NSEvent) -> String? {
    let key: String
    if let name = Self.keycodeNames[event.keyCode] {
      key = name
    } else {
      guard let chars = event.characters(byApplyingModifiers: [])?.lowercased() else { return nil }
      key = chars
    }
    var mods: Set<KeyboardTrigger.Modifier> = []
    if event.modifierFlags.contains(.command) { mods.insert(.cmd) }
    if event.modifierFlags.contains(.control) { mods.insert(.ctrl) }
    if event.modifierFlags.contains(.option) { mods.insert(.alt) }
    if event.modifierFlags.contains(.shift) { mods.insert(.shift) }
    let trigger = KeyboardTrigger(prefix: nil, modifiers: mods, key: key)
    return actionLookup[trigger]
  }

  func handleKeyDown(_ event: NSEvent) -> NSEvent? {
    guard let store else { return event }

    if store.activeSession?.activeTab?.windowModeState == .joinPick {
      if actionName(for: event) == "exit" {
        store.activeSession?.activeTab?.windowModeState = .normal
        return nil
      }
      if let chars = event.characters(byApplyingModifiers: []),
        let num = Int(chars), num >= 1, num <= 9
      {
        joinPaneToTab(targetIndex: num - 1, store: store)
        return nil
      }
      return nil
    }

    guard let action = actionName(for: event) else { return event }

    switch action {
    case "exit":
      store.activeSession?.activeTab?.windowModeState = .inactive
      deactivate()
    case "swap-left":
      swapActivePane(.left, store: store)
    case "swap-right":
      swapActivePane(.right, store: store)
    case "swap-up":
      swapActivePane(.up, store: store)
    case "swap-down":
      swapActivePane(.down, store: store)
    case "zoom":
      toggleZoom(store: store)
    case "break-to-tab":
      breakPaneToTab(store: store)
    case "rotate":
      rotateActivePane(store: store)
    case "join-pick":
      guard let tab = store.activeSession?.activeTab else { return nil }
      tab.windowModeState = .joinPick
    case "resize-left":
      resizeActivePane(delta: -0.05, along: .horizontal, store: store)
    case "resize-right":
      resizeActivePane(delta: 0.05, along: .horizontal, store: store)
    case "resize-up":
      resizeActivePane(delta: -0.05, along: .vertical, store: store)
    case "resize-down":
      resizeActivePane(delta: 0.05, along: .vertical, store: store)
    default:
      if action.hasPrefix("layout-") {
        if let tab = store.activeSession?.activeTab, tab.panes.count >= 2 {
          let layout: StandardLayout? = switch action {
          case "layout-even-horizontal": .evenHorizontal
          case "layout-even-vertical": .evenVertical
          case "layout-main-horizontal": .mainHorizontal
          case "layout-main-vertical": .mainVertical
          case "layout-tiled": .tiled
          default: nil
          }
          if let layout {
            tab.applyStandardLayout(layout)
            tab.windowModeState = .inactive
            deactivate()
          }
        }
      } else {
        return event
      }
    }
    return nil
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
