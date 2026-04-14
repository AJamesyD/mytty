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

  var isActive: Bool { store.activeSession?.id == session.id }

  var body: some View {
    DisclosureGroup(isExpanded: $isExpanded) {
      ForEach(session.tabs) { tab in
        let isActiveTab = isActive && session.activeTab?.id == tab.id
        HStack(spacing: 4) {
          if tab.hasBell {
            Circle()
              .fill(MisttyTheme.bellIndicator)
              .frame(width: 6, height: 6)
          }
          Text(tab.displayTitle)
            .font(.system(size: 12))
            .lineLimit(1)
            .help(tab.displayTitle)
          if tab.panes.count >= 2 {
            Image(systemName: "rectangle.split.2x1")
              .font(.system(size: 9))
              .foregroundStyle(MisttyTheme.tabCountBadge)
            Text("\(tab.panes.count)")
              .font(.system(size: 10, design: .monospaced))
              .foregroundStyle(MisttyTheme.tabCountBadge)
          }
          Spacer()
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
        .onTapGesture {
          store.activeSession = session
          session.activeTab = tab
        }
      }
    } label: {
      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 1.5)
          .fill(isActive ? MisttyTheme.sessionAccent : Color.clear)
          .frame(width: 3, height: 16)
        Text(session.name)
          .font(.system(size: 13))
          .fontWeight(isActive ? .semibold : .regular)
          .foregroundStyle(isActive ? .primary : .secondary)
          .lineLimit(1)
          .help(session.name)
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
        }
      }
      .contentShape(Rectangle())
      .onTapGesture { store.activeSession = session }
    }
    .padding(.top, 4)
  }
}
