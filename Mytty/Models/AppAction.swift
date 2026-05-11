import SwiftUI

struct AppAction: Identifiable {
  let id: String
  let label: String
  let category: String
  let handler: @MainActor () -> Void
}

struct ActionRegistryKey: FocusedValueKey {
  typealias Value = [AppAction]
}

extension FocusedValues {
  var actionRegistry: [AppAction]? {
    get { self[ActionRegistryKey.self] }
    set { self[ActionRegistryKey.self] = newValue }
  }
}
