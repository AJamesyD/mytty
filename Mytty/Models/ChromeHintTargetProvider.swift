import Foundation

@MainActor
struct ChromeHintTargetProvider: HintTargetProvider {
  let providerID = "chrome"
  let store: SessionStore
  let elementFrames: [String: CGRect]
  let sidebarVisible: Bool

  func targets(in geometry: HintsGeometry) -> [any HintTarget] {
    var result: [any HintTarget] = []
    let activeSessionID = store.activeSession?.id
    let activeTabID = store.activeSession?.activeTab?.id
    let activePaneID = store.activeSession?.activeTab?.activePane?.id

    if sidebarVisible {
      for session in store.sessions {
        guard !session.isRenaming else { continue }
        guard session.id != activeSessionID else { continue }
        let key = "session-\(session.id)"
        guard let frame = elementFrames[key] else { continue }
        result.append(ChromeHintTarget(
          id: key,
          labelOrigin: CGPoint(x: frame.minX, y: frame.minY),
          displayText: session.name,
          chromeElement: .session(sessionID: session.id)
        ))
      }
      for session in store.sessions {
        guard session.isSidebarExpanded else { continue }
        for tab in session.tabs {
          guard !tab.isRenaming else { continue }
          let isActiveTab = session.id == activeSessionID && tab.id == activeTabID
          guard !isActiveTab else { continue }
          let key = "sidebar-tab-\(session.id)-\(tab.id)"
          guard let frame = elementFrames[key] else { continue }
          result.append(ChromeHintTarget(
            id: key,
            labelOrigin: CGPoint(x: frame.minX, y: frame.minY),
            displayText: tab.displayTitle,
            chromeElement: .tab(sessionID: session.id, tabID: tab.id)
          ))
        }
      }
    }

    // TODO: tabs visible in both sidebar and tab bar should share the same label.
    if let session = store.activeSession {
      for tab in session.tabs {
        guard !tab.isRenaming else { continue }
        guard tab.id != activeTabID else { continue }
        let key = "tabbar-tab-\(tab.id)"
        guard let frame = elementFrames[key] else { continue }
        result.append(ChromeHintTarget(
          id: key,
          labelOrigin: CGPoint(x: frame.minX, y: frame.minY),
          displayText: tab.displayTitle,
          chromeElement: .tab(sessionID: session.id, tabID: tab.id)
        ))
      }
    }

    if let tab = store.activeSession?.activeTab {
      for pane in tab.panes {
        guard pane.id != activePaneID else { continue }
        let key = "pane-\(pane.id)"
        guard let frame = elementFrames[key] else { continue }
        result.append(ChromeHintTarget(
          id: key,
          labelOrigin: CGPoint(x: frame.minX + 8, y: frame.minY + 8),
          displayText: "Pane \(pane.id)",
          chromeElement: .pane(paneID: pane.id)
        ))
      }
    }

    return result
  }
}
