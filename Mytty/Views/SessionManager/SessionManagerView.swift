import AppKit
import SwiftUI

struct SessionManagerView: View {
  @Bindable var vm: SessionManagerViewModel
  @Binding var isPresented: Bool
  @State private var queryText = ""

  var body: some View {
    VStack(spacing: 0) {
      FocusableTextField(
        text: $queryText,
        placeholder: "Search sessions, directories, hosts...",
        onComplete: {
          if let value = vm.completionValue() {
            queryText = value
          }
        },
        onMoveUp: { vm.moveUp() },
        onMoveDown: { vm.moveDown() },
        onConfirm: { flags in
          vm.confirmSelection(modifierFlags: flags)
          isPresented = false
        },
        onCancel: { isPresented = false }
      )
      .font(.title3)
      .padding(14)
      .onChange(of: queryText) { _, newValue in
        vm.updateQuery(newValue)
      }

      Divider()

      ScrollViewReader { proxy in
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(Array(vm.filteredItems.enumerated()), id: \.element.id) { index, item in
              HStack {
                VStack(alignment: .leading, spacing: 2) {
                  if case .newSession = item {
                    HStack(spacing: 4) {
                      Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                        .font(.system(size: 12))
                      Text(item.displayName)
                        .font(.system(size: 13))
                        .lineLimit(1)
                    }
                  } else {
                    let matchResult = vm.matchResults[item.id]
                    HighlightedText(
                      text: item.displayName,
                      indices: Set(matchResult?.displayNameIndices ?? [])
                    )
                    .font(.system(size: 13))
                    .lineLimit(1)
                  }
                  if let subtitle = item.subtitle {
                    let matchResult = vm.matchResults[item.id]
                    HighlightedText(
                      text: subtitle,
                      indices: Set(matchResult?.subtitleIndices ?? [])
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                  }
                }
                Spacer()
              }
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(
                index == vm.selectedIndex
                  ? MyttyTheme.selectedRowBackground : MyttyTheme.transparent,
                in: RoundedRectangle(cornerRadius: 6)
              )
              .id(index)
              .contentShape(Rectangle())
              .onTapGesture {
                vm.selectedIndex = index
                let flags = NSApp.currentEvent?.modifierFlags ?? []
                vm.confirmSelection(modifierFlags: flags)
                isPresented = false
              }
            }
          }
        }
        .frame(maxHeight: 360)
        .id(queryText)
        .onChange(of: vm.selectedIndex) { _, newValue in
          proxy.scrollTo(newValue, anchor: .center)
        }
      }
    }
    .frame(width: 560)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .shadow(color: MyttyTheme.sessionManagerShadow, radius: 20)
    .task { await vm.load() }
  }
}
