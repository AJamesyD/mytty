import SwiftUI

struct CommandPaletteView: View {
  @Bindable var vm: CommandPaletteViewModel
  let keybindingStore: KeybindingStore
  @Binding var isPresented: Bool
  @State private var queryText = ""

  var body: some View {
    VStack(spacing: 0) {
      FocusableTextField(
        text: $queryText,
        placeholder: "Run action...",
        onMoveUp: { vm.moveUp() },
        onMoveDown: { vm.moveDown() },
        onConfirm: { _ in
          vm.selectedAction?.handler()
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
            ForEach(Array(vm.filteredActions.enumerated()), id: \.element.action.id) {
              index, entry in
              HStack {
                HighlightedText(
                  text: entry.action.label,
                  indices: Set(entry.matchIndices)
                )
                .font(.system(size: 13))
                .lineLimit(1)

                Spacer()

                if let trigger = keybindingStore.trigger(for: entry.action.id, in: .global) {
                  Text(trigger.displayLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
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
                vm.selectedAction?.handler()
                isPresented = false
              }
            }
          }
        }
        .frame(maxHeight: 360)
        .onChange(of: vm.selectedIndex) { _, newValue in
          proxy.scrollTo(newValue, anchor: .center)
        }
      }
    }
    .frame(width: 480)
    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    .shadow(color: MyttyTheme.sessionManagerShadow, radius: 20)
  }
}
