import Foundation

@MainActor
@Observable
class CommandPaletteViewModel {
  private let actions: [AppAction]
  var query = ""
  var selectedIndex = 0
  private(set) var filteredActions: [(action: AppAction, matchIndices: [Int])] = []

  init(actions: [AppAction]) {
    self.actions = actions
    filteredActions = actions.map { ($0, []) }
  }

  func updateQuery(_ newQuery: String) {
    query = newQuery
    if newQuery.isEmpty {
      filteredActions = actions.map { ($0, []) }
    } else {
      filteredActions = actions.compactMap {
        action -> (action: AppAction, score: Double, indices: [Int])? in
        guard let match = FuzzyMatcher.match(query: newQuery, target: action.label) else {
          return nil
        }
        return (action: action, score: match.score, indices: match.matchedIndices)
      }
      .sorted { $0.score > $1.score }
      .map { ($0.action, $0.indices) }
    }
    selectedIndex = 0
  }

  func moveUp() {
    guard selectedIndex > 0 else { return }
    selectedIndex -= 1
  }

  func moveDown() {
    guard selectedIndex < filteredActions.count - 1 else { return }
    selectedIndex += 1
  }

  var selectedAction: AppAction? {
    guard selectedIndex < filteredActions.count else { return nil }
    return filteredActions[selectedIndex].action
  }
}
