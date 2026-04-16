import AppKit
import Foundation

struct TrackedWindow {
  let id: Int
  let window: NSWindow
}

@Observable
@MainActor
final class SessionStore {
  private(set) var sessions: [MisttySession] = []
  var activeSession: MisttySession?

  private var nextSessionId = 1
  private var nextTabId = 1
  private var nextPaneId = 1
  private var nextWindowId = 1
  private var nextPopupId = 1
  private(set) var trackedWindows: [TrackedWindow] = []

  private func generateSessionID() -> Int {
    let id = nextSessionId
    nextSessionId += 1
    return id
  }

  private func generateTabID() -> Int {
    let id = nextTabId
    nextTabId += 1
    return id
  }

  private func generatePaneID() -> Int {
    let id = nextPaneId
    nextPaneId += 1
    return id
  }

  @discardableResult
  func createSession(name: String, directory: URL, exec: String? = nil) -> MisttySession {
    let session = MisttySession(
      id: generateSessionID(),
      name: name,
      directory: directory,
      exec: exec,
      tabIDGenerator: { [weak self] in
        guard let self else {
          assertionFailure("SessionStore was deallocated while sessions still exist")
          return 0
        }
        return self.generateTabID()
      },
      paneIDGenerator: { [weak self] in
        guard let self else {
          assertionFailure("SessionStore was deallocated while sessions still exist")
          return 0
        }
        return self.generatePaneID()
      },
      popupIDGenerator: { [weak self] in
        guard let self else {
          assertionFailure("SessionStore was deallocated while sessions still exist")
          return 0
        }
        return self.generatePopupID()
      }
    )
    sessions.append(session)
    activeSession = session
    return session
  }

  func createDetachedSession(name: String, directory: URL) -> MisttySession {
    MisttySession(
      id: generateSessionID(),
      name: name,
      directory: directory,
      tabIDGenerator: { [weak self] in
        guard let self else {
          assertionFailure("SessionStore was deallocated while sessions still exist")
          return 0
        }
        return self.generateTabID()
      },
      paneIDGenerator: { [weak self] in
        guard let self else {
          assertionFailure("SessionStore was deallocated while sessions still exist")
          return 0
        }
        return self.generatePaneID()
      },
      popupIDGenerator: { [weak self] in
        guard let self else {
          assertionFailure("SessionStore was deallocated while sessions still exist")
          return 0
        }
        return self.generatePopupID()
      }
    )
  }

  func closeSession(_ session: MisttySession) {
    sessions.removeAll { $0.id == session.id }
    if activeSession?.id == session.id { activeSession = sessions.last }
  }

  private func generatePopupID() -> Int {
    let id = nextPopupId
    nextPopupId += 1
    return id
  }

  // MARK: - Window registry

  private func generateWindowID() -> Int {
    let id = nextWindowId
    nextWindowId += 1
    return id
  }

  func registerWindow(_ window: NSWindow) -> Int {
    if let existing = trackedWindows.first(where: { $0.window === window }) {
      return existing.id
    }
    let id = generateWindowID()
    trackedWindows.append(TrackedWindow(id: id, window: window))
    return id
  }

  func unregisterWindow(_ window: NSWindow) {
    trackedWindows.removeAll { $0.window === window }
  }

  func trackedWindow(byId id: Int) -> TrackedWindow? {
    trackedWindows.first { $0.id == id }
  }

  // MARK: - Lookup helpers

  func session(byId id: Int) -> MisttySession? {
    sessions.first { $0.id == id }
  }

  func tab(byId id: Int) -> (session: MisttySession, tab: MisttyTab)? {
    for session in sessions {
      if let tab = session.tabs.first(where: { $0.id == id }) {
        return (session, tab)
      }
    }
    return nil
  }

  func pane(byId id: Int) -> (session: MisttySession, tab: MisttyTab, pane: MisttyPane)? {
    for session in sessions {
      for tab in session.tabs {
        if let pane = tab.panes.first(where: { $0.id == id }) {
          return (session, tab, pane)
        }
      }
    }
    return nil
  }

  func popup(byId id: Int) -> (session: MisttySession, popup: PopupState)? {
    for session in sessions {
      if let popup = session.popups.first(where: { $0.id == id }) {
        return (session, popup)
      }
    }
    return nil
  }

  func nextSession() {
    guard let current = activeSession,
      let index = sessions.firstIndex(where: { $0.id == current.id }),
      sessions.count > 1
    else { return }
    activeSession = sessions[(index + 1) % sessions.count]
  }

  func prevSession() {
    guard let current = activeSession,
      let index = sessions.firstIndex(where: { $0.id == current.id }),
      sessions.count > 1
    else { return }
    activeSession = sessions[(index - 1 + sessions.count) % sessions.count]
  }

  func activePaneInfo() -> (session: MisttySession, tab: MisttyTab, pane: MisttyPane)? {
    guard let session = activeSession,
      let tab = session.activeTab,
      let pane = tab.activePane
    else { return nil }
    return (session, tab, pane)
  }

  // MARK: - Persistence

  func toPersistentState() -> PersistentState {
    let activeIndex = activeSession.flatMap { active in
      sessions.firstIndex(where: { $0.id == active.id })
    }
    return PersistentState(
      version: PersistentState.currentVersion,
      activeSessionIndex: activeIndex,
      sessions: sessions.map { session in
        let activeTabIndex = session.activeTab.flatMap { active in
          session.tabs.firstIndex(where: { $0.id == active.id })
        }
        return PersistentSession(
          name: session.name,
          directory: session.directory,
          sshCommand: session.sshCommand,
          activeTabIndex: activeTabIndex,
          tabs: session.tabs.map { tab in
            let activePaneIndex = tab.activePane.flatMap { active in
              tab.panes.firstIndex(where: { $0.id == active.id })
            }
            return PersistentTab(
              customTitle: tab.customTitle,
              directory: tab.directory,
              activePaneIndex: activePaneIndex,
              layout: persistLayoutNode(tab.layout.root)
            )
          }
        )
      }
    )
  }

  func restore(from state: PersistentState) {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser

    // TODO: createSession and MisttyTab.init each create a throwaway default
    // tab+pane that gets replaced immediately. Add a restore-specific init path
    // that skips the default children to avoid wasting IDs.
    for persistedSession in state.sessions {
      let dir =
        fm.fileExists(atPath: persistedSession.directory.path)
        ? persistedSession.directory : home
      let session = createSession(name: persistedSession.name, directory: dir)
      session.sshCommand = persistedSession.sshCommand

      if !persistedSession.tabs.isEmpty {
        var restoredTabs: [MisttyTab] = []

        for persistedTab in persistedSession.tabs {
          let tab = MisttyTab(
            id: generateTabID(),
            directory: persistedTab.directory,
            paneIDGenerator: { [weak self] in self?.generatePaneID() ?? 0 }
          )
          tab.customTitle = persistedTab.customTitle

          let (rootNode, panes) = restoreLayoutNode(persistedTab.layout, home: home)
          tab.layout = PaneLayout(root: rootNode)
          tab.replacePanes(panes)
          tab.activePane =
            persistedTab.activePaneIndex.flatMap { idx in
              idx < panes.count ? panes[idx] : nil
            } ?? panes.first

          restoredTabs.append(tab)
        }

        session.replaceTabs(restoredTabs)
        session.activeTab =
          persistedSession.activeTabIndex.flatMap { idx in
            idx < restoredTabs.count ? restoredTabs[idx] : nil
          } ?? restoredTabs.first
      }
    }

    activeSession =
      state.activeSessionIndex.flatMap { idx in
        idx < sessions.count ? sessions[idx] : nil
      } ?? sessions.first
  }

  private func persistLayoutNode(_ node: PaneLayoutNode) -> PersistentLayoutNode {
    switch node {
    case .leaf(let pane):
      return .leaf(
        PersistentPane(
          directory: pane.workingDirectory ?? pane.directory,
          command: pane.command,
          useCommandField: pane.useCommandField
        ))
    case .empty:
      return .leaf(PersistentPane(directory: nil, command: nil, useCommandField: true))
    case .split(let dir, let a, let b, let ratio):
      return .split(dir, persistLayoutNode(a), persistLayoutNode(b), ratio)
    }
  }

  private func restoreLayoutNode(_ node: PersistentLayoutNode, home: URL) -> (
    PaneLayoutNode, [MisttyPane]
  ) {
    let fm = FileManager.default
    switch node {
    case .leaf(let persistedPane):
      let pane = MisttyPane(id: generatePaneID())
      let dir =
        persistedPane.directory.flatMap { fm.fileExists(atPath: $0.path) ? $0 : home } ?? home
      pane.directory = dir
      pane.command = persistedPane.command
      pane.useCommandField = persistedPane.useCommandField
      return (.leaf(pane), [pane])
    case .split(let direction, let left, let right, let ratio):
      let (leftNode, leftPanes) = restoreLayoutNode(left, home: home)
      let (rightNode, rightPanes) = restoreLayoutNode(right, home: home)
      return (.split(direction, leftNode, rightNode, ratio), leftPanes + rightPanes)
    }
  }
}
