import AppKit
import GhosttyKit
import MisttyShared
import SwiftUI

struct ContentView: View {
  var store: SessionStore
  @AppStorage("sidebarVisible") var sidebarVisible = true
  @SceneStorage("sidebarWidth") var sidebarWidth: Double = 220
  @State var showingSessionManager = false
  @State var sessionManagerVM: SessionManagerViewModel?
  @State var eventMonitor: Any?
  @State var windowModeManager = WindowModeManager()
  @State var copyModeManager = CopyModeManager()
  @State var whichKeyManager = WhichKeyManager()

  var body: some View {
    contentWithNotifications
      .focusedSceneValue(\.terminalCommands, terminalCommands)
  }

  var terminalCommands: TerminalCommands {
    TerminalCommands(
      newTab: { store.activeSession?.addTab() },
      closeTab: { handleCloseTab() },
      nextTab: { store.activeSession?.nextTab() },
      prevTab: { store.activeSession?.prevTab() },
      focusTab: { index in
        guard let session = store.activeSession,
          index < session.tabs.count
        else { return }
        session.activeTab = session.tabs[index]
      },
      nextSession: { store.nextSession() },
      prevSession: { store.prevSession() },
      splitHorizontal: { splitPane(direction: .horizontal) },
      splitVertical: { splitPane(direction: .vertical) },
      closePane: { handleClosePane() },
      windowMode: { handleWindowMode() },
      copyMode: { handleCopyMode() },
      whichKey: { handleWhichKey() },
      sessionManager: { showingSessionManager = true },
      togglePopup: { name in handlePopupToggle(name: name) }
    )
  }

  var mainContent: some View {
    HStack(spacing: 0) {
      if sidebarVisible {
        SidebarView(
          store: store,
          width: Binding(
            get: { CGFloat(sidebarWidth) },
            set: { sidebarWidth = Double($0) }
          ))
        Rectangle()
          .fill(MisttyTheme.sidebarDivider)
          .frame(width: 1)
      }

      Group {
        if let session = store.activeSession,
          let tab = session.activeTab
        {
          VStack(spacing: 0) {
            if session.tabs.count > 1 {
              TabBarView(session: session)
              Divider()
            }
            let joinPickTabNames = session.tabs
              .filter { $0.id != tab.id }
              .map { $0.displayTitle }
            ZStack(alignment: .bottom) {
              if let zoomedPane = tab.zoomedPane {
                PaneView(
                  pane: zoomedPane,
                  isActive: true,
                  isWindowModeActive: tab.isWindowModeActive,
                  isZoomed: true,
                  copyModeState: (zoomedPane.id == tab.activePane?.id) ? tab.copyModeState : nil,
                  windowModeState: tab.windowModeState,
                  joinPickTabNames: joinPickTabNames,
                  paneCount: tab.panes.count,
                  onClose: { closePane(zoomedPane) },
                  onSelect: {}
                )
              } else {
                PaneLayoutView(
                  node: tab.layout.root,
                  activePane: tab.activePane,
                  isWindowModeActive: tab.isWindowModeActive,
                  copyModeState: tab.copyModeState,
                  copyModePaneID: tab.activePane?.id,
                  windowModeState: tab.windowModeState,
                  joinPickTabNames: joinPickTabNames,
                  paneCount: tab.panes.count,
                  onClosePane: { pane in closePane(pane) },
                  onSelectPane: { pane in tab.activePane = pane }
                )
              }
              if tab.windowModeState != .inactive {
                WindowModeHints(
                  isJoinPick: tab.windowModeState == .joinPick,
                  tabNames: joinPickTabNames,
                  paneCount: tab.panes.count
                )
                .padding(6)
                .allowsHitTesting(false)
              }
            }
          }
        } else {
          VStack(spacing: 12) {
            Text("No active session")
              .font(.title2)
              .foregroundStyle(.secondary)
            Text("Press ⌘J to open or create a session")
              .foregroundStyle(.tertiary)
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
      }
    }
    .onAppear {
      windowModeManager.onNeedExitCopyMode = { copyModeManager.exit() }
      copyModeManager.onNeedExitWindowMode = {
        store.activeSession?.activeTab?.windowModeState = .inactive
        windowModeManager.deactivate()
      }
      DispatchQueue.main.async {
        if let window = NSApplication.shared.keyWindow {
          _ = store.registerWindow(window)
        }
      }
    }
    .onDisappear {
      DispatchQueue.main.async { [store] in
        for tracked in store.trackedWindows where !tracked.window.isVisible {
          store.unregisterWindow(tracked.window)
        }
      }
      removeKeyMonitor()
      windowModeManager.deactivate()
      copyModeManager.deactivate()
      store.activeSession?.activeTab?.windowModeState = .inactive
      showingSessionManager = false
    }
  }

  @ViewBuilder
  var sessionManagerOverlay: some View {
    if showingSessionManager, let vm = sessionManagerVM {
      MisttyTheme.modalBackdrop
        .ignoresSafeArea()
        .onTapGesture { showingSessionManager = false }

      SessionManagerView(
        vm: vm,
        isPresented: $showingSessionManager
      )
    }
  }

  @ViewBuilder
  var popupOverlay: some View {
    if let session = store.activeSession,
      let popup = session.activePopup,
      popup.isVisible
    {
      GeometryReader { geometry in
        PopupOverlayView(
          popup: popup,
          onDismiss: {
            session.hideActivePopup()
            returnFocusToActivePane()
          },
          onClose: {
            session.closePopup(popup)
            returnFocusToActivePane()
          }
        )
        .frame(
          width: geometry.size.width * popup.definition.width,
          height: geometry.size.height * popup.definition.height
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }
}
