import Foundation

@Observable
@MainActor
final class PopupState: Identifiable {
  let id: Int
  let definition: PopupDefinition
  let pane: MyttyPane
  var isVisible: Bool

  init(id: Int, definition: PopupDefinition, pane: MyttyPane, isVisible: Bool = true) {
    self.id = id
    self.definition = definition
    self.pane = pane
    self.isVisible = isVisible
  }
}
