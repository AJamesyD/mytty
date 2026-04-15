import SwiftUI

struct SidebarView: View {
  @Bindable var store: SessionStore
  @Binding var width: CGFloat

  var body: some View {
    List {
      ForEach(store.sessions) { session in
        SessionRowView(session: session, store: store)
      }
    }
    .listStyle(.sidebar)
    .frame(width: width)
    .overlay(alignment: .trailing) {
      SidebarDragHandle(width: $width)
    }
  }
}

struct SidebarDragHandle: View {
  @Binding var width: CGFloat

  var body: some View {
    Color.clear
      .frame(width: 6)
      .contentShape(Rectangle())
      .gesture(
        DragGesture(coordinateSpace: .global)
          .onChanged { value in
            width = max(140, min(400, value.location.x))
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
  @Bindable var session: MisttySession
  @Bindable var store: SessionStore
  @State private var isExpanded = true
  @State private var isEditingSession = false
  @State private var editingTabID: Int? = nil
  @State private var editText = ""
  @FocusState private var editFocused: Bool

  var isActive: Bool { store.activeSession?.id == session.id }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      ForEach(session.tabs) { tab in
        let isActiveTab = isActive && session.activeTab?.id == tab.id
        HStack(spacing: 4) {
          if tab.hasFailedCommand {
            Circle()
              .fill(MisttyTheme.commandFailedIndicator)
              .frame(width: 6, height: 6)
              .shadow(color: MisttyTheme.commandFailedIndicator, radius: 3)
              .accessibilityLabel("Command failed")
          } else if tab.hasBell {
            Circle()
              .fill(MisttyTheme.bellGlow)
              .frame(width: 6, height: 6)
              .shadow(color: MisttyTheme.bellGlow, radius: 3)
              .accessibilityLabel("Bell notification")
          }
          if editingTabID == tab.id {
            TextField(
              "Tab name", text: $editText,
              onCommit: {
                tab.customTitle = editText.isEmpty ? nil : editText
                editingTabID = nil
              }
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($editFocused)
            .onExitCommand { editingTabID = nil }
            .onAppear { editFocused = true }
            .onChange(of: editFocused) {
              if !editFocused { editingTabID = nil }
            }
          } else {
            Text(tab.displayTitle)
              .font(.system(size: 12))
              .lineLimit(1)
              .help(tab.displayTitle)
              .onTapGesture(count: 2) {
                editText = tab.displayTitle
                editingTabID = tab.id
              }
          }
          if tab.panes.count >= 2 {
            Image(systemName: "rectangle.split.2x1")
              .font(.system(size: 9))
              .foregroundStyle(MisttyTheme.tabCountBadge)
              .accessibilityHidden(true)
            Text("\(tab.panes.count)")
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(MisttyTheme.tabCountBadge)
              .accessibilityLabel("\(tab.panes.count) panes")
          }
          Spacer()
          if let result = tab.activePane?.lastCommandResult {
            Image(systemName: result.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
              .font(.system(size: 9))
              .foregroundStyle(
                result.exitCode == 0
                  ? MisttyTheme.commandSuccessIndicator : MisttyTheme.commandFailedIndicator)
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
            ? MisttyTheme.selectedRowBackground
            : Color.clear,
          in: RoundedRectangle(cornerRadius: 4)
        )
        .contentShape(Rectangle())
        .contextMenu {
          Button("Rename Tab") {
            editText = tab.displayTitle
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
      HStack(spacing: 6) {
        if isEditingSession {
          TextField(
            "Session name", text: $editText,
            onCommit: {
              session.name = editText.isEmpty ? session.directory.lastPathComponent : editText
              isEditingSession = false
            }
          )
          .textFieldStyle(.plain)
          .font(.system(size: 13))
          .focused($editFocused)
          .onExitCommand { isEditingSession = false }
          .onAppear { editFocused = true }
          .onChange(of: editFocused) {
            if !editFocused { isEditingSession = false }
          }
        } else {
          Text(session.name)
            .font(.system(size: 13))
            .fontWeight(isActive ? .semibold : .regular)
            .foregroundStyle(isActive ? .primary : .secondary)
            .lineLimit(1)
            .help(session.name)
            .onTapGesture(count: 2) {
              editText = session.name
              isEditingSession = true
            }
        }
        if !isExpanded || session.tabs.count >= 2 {
          Text("\(session.tabs.count)")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(MisttyTheme.tabCountBadge)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
              Capsule()
                .fill(MisttyTheme.tabCountBadge.opacity(0.15))
            )
            .accessibilityLabel("\(session.tabs.count) tabs")
        }
        if session.notificationCount > 0, let severity = session.notificationSeverity {
          let color: Color = severity == .commandFailed ? MisttyTheme.commandFailedIndicator : .red
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
          editText = session.name
          isEditingSession = true
        }
        Button("Close Session") { store.closeSession(session) }
      }
      .onTapGesture { store.activeSession = session }
    }
    .listRowBackground(
      HStack(spacing: 0) {
        MisttyTheme.sessionAccent
          .frame(width: 3)
          .opacity(isActive ? 1 : 0)
        Color.clear
      }
    )
    .padding(.top, 4)
    .onReceive(NotificationCenter.default.publisher(for: .misttyRenameSession)) { _ in
      if isActive {
        editText = session.name
        isEditingSession = true
      }
    }
  }
}
