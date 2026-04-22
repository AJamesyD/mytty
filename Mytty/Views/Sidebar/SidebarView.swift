import SwiftUI

struct SidebarView: View {
  @Bindable var store: SessionStore
  @Binding var width: CGFloat
  var showTree: Bool = true
  var position: SidebarPosition = .left

  var body: some View {
    List {
      ForEach(store.sessions) { session in
        SessionRowView(session: session, store: store, showTree: showTree)
      }
    }
    .listStyle(.sidebar)
    .frame(width: width)
    .overlay(alignment: position == .left ? .trailing : .leading) {
      SidebarDragHandle(width: $width, position: position)
    }
  }
}

struct SidebarDragHandle: View {
  @Binding var width: CGFloat
  var position: SidebarPosition = .left
  @GestureState private var dragStartWidth: CGFloat?

  var body: some View {
    MyttyTheme.transparent
      .frame(width: 6)
      .contentShape(Rectangle())
      .gesture(
        DragGesture()
          .updating($dragStartWidth) { _, state, _ in
            if state == nil { state = width }
          }
          .onChanged { value in
            guard let startWidth = dragStartWidth else { return }
            let delta =
              position == .left
              ? value.translation.width
              : -value.translation.width
            width = max(140, min(400, startWidth + delta))
          }
      )
      .onHover { hovering in
        if hovering {
          NSCursor.resizeLeftRight.push()
        } else {
          NSCursor.pop()
        }
      }
  }
}

struct SessionRowView: View {
  @Bindable var session: MyttySession
  @Bindable var store: SessionStore
  var showTree: Bool = true
  @State private var isExpanded = true
  @State private var isEditingSession = false
  @State private var editingTabID: Int?

  var isActive: Bool { store.activeSession?.id == session.id }

  var body: some View {
    Group {
      if showTree {
        treeContent
      } else {
        sessionLabel
      }
    }
    .listRowBackground(rowBackground)
    .padding(.top, 4)
    .onReceive(NotificationCenter.default.publisher(for: .myttyRenameSession)) { _ in
      if isActive {
        isEditingSession = true
      }
    }
  }

  var treeContent: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      ForEach(session.tabs) { tab in
        let isActiveTab = isActive && session.activeTab?.id == tab.id
        HStack(spacing: 4) {
          if tab.hasFailedCommand {
            Circle()
              .fill(MyttyTheme.commandFailedIndicator)
              .frame(width: 6, height: 6)
              .shadow(color: MyttyTheme.commandFailedIndicator, radius: 3)
              .accessibilityLabel("Command failed")
          } else if tab.hasBell {
            Circle()
              .fill(MyttyTheme.bellGlow)
              .frame(width: 6, height: 6)
              .shadow(color: MyttyTheme.bellGlow, radius: 3)
              .accessibilityLabel("Bell notification")
          }
          if editingTabID == tab.id {
            InlineEditableTextField(
              text: tab.displayTitle,
              placeholder: "Tab name",
              font: .system(size: 12),
              onSubmit: { newName in
                tab.customTitle = newName.isEmpty ? nil : newName
                editingTabID = nil
              },
              onCancel: { editingTabID = nil }
            )
          } else {
            Text(tab.displayTitle)
              .font(.system(size: 12))
              .lineLimit(1)
              .help(tab.displayTitle)
              .onTapGesture(count: 2) {
                editingTabID = tab.id
              }
          }
          if tab.panes.count >= 2 {
            Image(systemName: "rectangle.split.2x1")
              .font(.system(size: 9))
              .foregroundStyle(MyttyTheme.tabCountBadge)
              .accessibilityHidden(true)
            Text("\(tab.panes.count)")
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(MyttyTheme.tabCountBadge)
              .accessibilityLabel("\(tab.panes.count) panes")
          }
          Spacer()
          if let result = tab.activePane?.lastCommandResult {
            Image(systemName: result.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
              .font(.system(size: 9))
              .foregroundStyle(
                result.exitCode == 0
                  ? MyttyTheme.commandSuccessIndicator : MyttyTheme.commandFailedIndicator)
            if let duration = result.formattedDuration {
              Text(duration)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(.leading, 12)
        .padding(.vertical, 2)
        .background(
          isActiveTab
            ? MyttyTheme.selectedRowBackground
            : MyttyTheme.transparent,
          in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .contextMenu {
          Button("Rename Tab") {
            editingTabID = tab.id
          }
          Button("Close Tab") {
            session.closeTab(tab)
            if session.tabs.isEmpty { store.closeSession(session) }
          }
        }
        .onTapGesture {
          store.activeSession = session
          session.activeTab = tab
        }
      }
    } label: {
      sessionLabel
    }
  }

  var sessionLabel: some View {
    HStack(spacing: 6) {
      if isEditingSession {
        InlineEditableTextField(
          text: session.name,
          placeholder: "Session name",
          font: .system(size: 13),
          onSubmit: { newName in
            let resolvedName = newName.isEmpty ? session.directory.lastPathComponent : newName
            session.name = resolvedName
            for tab in session.tabs {
              tab.sessionName = resolvedName
              for pane in tab.panes { pane.sessionName = resolvedName }
            }
            for popup in session.popups { popup.pane.sessionName = resolvedName }
            isEditingSession = false
          },
          onCancel: { isEditingSession = false }
        )
      } else {
        Text(session.name)
          .font(.system(size: 13))
          .fontWeight(isActive ? .semibold : .regular)
          .foregroundStyle(isActive ? .primary : .secondary)
          .lineLimit(1)
          .help(session.name)
          .onTapGesture(count: 2) {
            isEditingSession = true
          }
      }
      if !showTree || !isExpanded || session.tabs.count >= 2 {
        Text("\(session.tabs.count)")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(MyttyTheme.tabCountBadge)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(
            Capsule()
              .fill(MyttyTheme.tabCountBadgeFill)
          )
          .accessibilityLabel("\(session.tabs.count) tabs")
      }
      if session.notificationCount > 0, let severity = session.notificationSeverity {
        let color: Color = severity == .commandFailed ? MyttyTheme.commandFailedIndicator : .red
        Text("\(session.notificationCount)")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.white)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Capsule().fill(color))
          .accessibilityLabel("\(session.notificationCount) notifications")
      }
    }
    .contentShape(Rectangle())
    .contextMenu {
      Button("Rename Session") {
        isEditingSession = true
      }
      Button("Close Session") { store.closeSession(session) }
    }
    .onTapGesture { store.activeSession = session }
  }

  var rowBackground: some View {
    HStack(spacing: 0) {
      MyttyTheme.sessionAccent
        .frame(width: 3)
        .opacity(isActive ? 1 : 0)
      MyttyTheme.transparent
    }
  }
}
