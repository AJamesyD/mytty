import Foundation

@Observable
@MainActor
final class MyttyTab: Identifiable {
  let id: Int
  var title: String = "Shell"
  var tabTitle: String?
  var customTitle: String?

  @ObservationIgnored
  var titleDebounceTask: DispatchWorkItem?

  var displayTitle: String {
    customTitle ?? tabTitle ?? title
  }
  let directory: URL?
  var sessionID: Int = 0
  var sessionName: String = ""
  private(set) var panes: [MyttyPane] = []
  var activePane: MyttyPane?
  var hasBell = false
  var hasFailedCommand = false

  enum WindowModeState {
    case inactive, normal, joinPick
  }

  var windowModeState: WindowModeState = .inactive
  var isWindowModeActive: Bool { windowModeState != .inactive }
  var copyModeState: CopyModeState?
  var isCopyModeActive: Bool { copyModeState != nil }
  var zoomedPane: MyttyPane?
  var layout: PaneLayout

  /// Closure that generates the next unique pane ID.
  @ObservationIgnored
  private(set) var paneIDGenerator: () -> Int

  init(id: Int, directory: URL? = nil, exec: String? = nil, paneIDGenerator: @escaping () -> Int) {
    self.id = id
    self.directory = directory
    self.paneIDGenerator = paneIDGenerator
    let pane = MyttyPane(id: paneIDGenerator())
    pane.directory = directory
    pane.command = exec
    layout = PaneLayout(pane: pane)
    panes = [pane]
    activePane = pane
  }

  init(id: Int, existingPane pane: MyttyPane, paneIDGenerator: @escaping () -> Int) {
    self.id = id
    self.directory = pane.directory
    self.paneIDGenerator = paneIDGenerator
    layout = PaneLayout(pane: pane)
    panes = [pane]
    activePane = pane
  }

  func propagateIdentity() {
    for pane in panes {
      pane.sessionID = sessionID
      pane.sessionName = sessionName
      pane.tabID = id
    }
  }

  func splitActivePane(direction: SplitDirection) {
    guard let activePane else { return }
    let newPane = MyttyPane(id: paneIDGenerator())
    newPane.directory = directory
    newPane.sessionID = sessionID
    newPane.sessionName = sessionName
    newPane.tabID = id
    layout.split(pane: activePane, direction: direction, newPane: newPane)
    panes = layout.leaves
    self.activePane = layout.leaves.last
  }

  func addExistingPane(_ pane: MyttyPane, direction: SplitDirection) {
    guard let activePane else { return }
    pane.sessionID = sessionID
    pane.sessionName = sessionName
    pane.tabID = id
    layout.split(pane: activePane, direction: direction, newPane: pane)
    panes = layout.leaves
    self.activePane = pane
  }

  func closePane(_ pane: MyttyPane) {
    layout.remove(pane: pane)
    panes = layout.leaves
    if activePane?.id == pane.id { activePane = panes.last }
  }

  func applyStandardLayout(_ standardLayout: StandardLayout) {
    let currentPanes = layout.leaves
    guard currentPanes.count >= 2 else { return }
    zoomedPane = nil
    layout = PaneLayout(root: LayoutEngine.apply(standardLayout, to: currentPanes))
    panes = layout.leaves
  }

  func swapActivePane(direction: NavigationDirection) {
    guard let pane = activePane else { return }
    layout.swapPane(pane, direction: direction)
  }

  func toggleZoom() {
    zoomedPane = zoomedPane != nil ? nil : activePane
  }

  func rotateActivePane() {
    guard let pane = activePane else { return }
    layout.rotateDirection(containing: pane)
  }

  func replacePanes(_ newPanes: [MyttyPane]) {
    panes = newPanes
  }
}
