import SwiftUI

struct TabBarView: View {
  @Bindable var session: MisttySession

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
  @Bindable var tab: MisttyTab
  let isActive: Bool
  let onSelect: () -> Void
  let onClose: () -> Void
  @State private var isEditing = false
  @State private var editText = ""
  @State private var isHovered = false
  @FocusState private var editFocused: Bool

  var body: some View {
    HStack(spacing: 4) {
      if tab.hasBell {
        Circle()
          .fill(MisttyTheme.bellIndicator)
          .frame(width: 6, height: 6)
      }

      if isEditing {
        TextField(
          "Tab name", text: $editText,
          onCommit: {
            tab.customTitle = editText.isEmpty ? nil : editText
            isEditing = false
          }
        )
        .textFieldStyle(.plain)
        .font(.system(size: 12))
        .focused($editFocused)
        .frame(maxWidth: 120)
        .onExitCommand { isEditing = false }
        .onAppear { editFocused = true }
        .onChange(of: editFocused) {
          if !editFocused && isEditing { isEditing = false }
        }
      } else {
        Text(tab.displayTitle)
          .font(.system(size: 12))
          .lineLimit(1)
          .onTapGesture(count: 2) {
            editText = tab.displayTitle
            isEditing = true
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
    .background(isActive ? MisttyTheme.activeTabBackground : MisttyTheme.inactiveTabBackground)
    .cornerRadius(6)
    .contextMenu {
      Button("Rename Tab") { editText = tab.displayTitle; isEditing = true }
      Button("Close Tab") { onClose() }
    }
    .onTapGesture { onSelect() }
    .onHover { isHovered = $0 }
    .onReceive(NotificationCenter.default.publisher(for: .misttyRenameTab)) { _ in
      if isActive {
        editText = tab.displayTitle
        isEditing = true
      }
    }
  }
}
