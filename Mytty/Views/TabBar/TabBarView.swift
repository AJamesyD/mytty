import SwiftUI

struct TabBarView: View {
  @Bindable var session: MyttySession

  var body: some View {
    HStack(spacing: 0) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 2) {
          ForEach(Array(session.tabs.enumerated()), id: \.element.id) { index, tab in
            TabBarItem(
              tab: tab,
              isActive: session.activeTab?.id == tab.id,
              onSelect: { session.activeTab = tab },
              onClose: { session.closeTab(tab) }
            )
            .draggable(String(tab.id))
            .dropDestination(for: String.self) { droppedIDs, _ in
              guard let idString = droppedIDs.first,
                let id = Int(idString)
              else { return false }
              session.moveTab(withID: id, toIndex: index)
              return true
            }
          }
        }
        .padding(.horizontal, 4)
      }

      Button(action: { session.addTab() }) {
        Image(systemName: "plus")
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .padding(.trailing, 4)
    }
    .frame(height: 36)
    .background(.bar)
  }
}

struct TabBarItem: View {
  @Bindable var tab: MyttyTab
  let isActive: Bool
  let onSelect: () -> Void
  let onClose: () -> Void
  @State private var isHovered = false

  var body: some View {
    HStack(spacing: 4) {
      if tab.hasFailedCommand {
        Circle()
          .fill(MyttyTheme.commandFailedIndicator)
          .frame(width: 6, height: 6)
          .shadow(color: MyttyTheme.commandFailedIndicator, radius: 3)
      } else if tab.hasBell {
        Circle()
          .fill(MyttyTheme.bellGlow)
          .frame(width: 6, height: 6)
          .shadow(color: MyttyTheme.bellGlow, radius: 3)
      }

      if tab.isRenaming {
        InlineEditableTextField(
          text: tab.displayTitle,
          placeholder: "Tab name",
          font: .system(size: 12),
          onSubmit: { newName in
            tab.customTitle = newName.isEmpty ? nil : newName
            tab.isRenaming = false
          },
          onCancel: { tab.isRenaming = false }
        )
        .frame(maxWidth: 120)
      } else {
        Text(tab.displayTitle)
          .font(.system(size: 12))
          .lineLimit(1)
      }

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

      Button(action: onClose) {
        Image(systemName: "xmark")
          .font(.system(size: 9))
      }
      .buttonStyle(.plain)
      .opacity(isActive || isHovered ? 1 : 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(isActive ? MyttyTheme.activeTabBackground : MyttyTheme.inactiveTabBackground)
    .cornerRadius(6)
    .overlay(alignment: .bottom) {
      if isActive {
        MyttyTheme.sessionAccent
          .frame(height: 2)
          .clipShape(RoundedRectangle(cornerRadius: 1))
      }
    }
    .contextMenu {
      Button("Rename Tab") {
        tab.isRenaming = true
      }
      Button("Close Tab") { onClose() }
    }
    .onTapGesture { onSelect() }
    .onHover { isHovered = $0 }
    .onReceive(NotificationCenter.default.publisher(for: .myttyRenameTab)) { _ in
      if isActive {
        tab.isRenaming = true
      }
    }
  }
}
