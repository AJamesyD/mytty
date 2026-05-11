import XCTest

@testable import Mytty

final class MenuSyncTests: XCTestCase {
  /// Actions that intentionally bypass the menu bar for key dispatch.
  /// Each entry documents WHY it's excluded.
  private static let noMenuItem: Set<String> = [
    // Dispatched via libghostty's "unconsumed key" callback through PaneNavigationManager.
    // Menu items would intercept the key before libghostty can decide whether to consume it.
    "navigate-left",
    "navigate-down",
    "navigate-up",
    "navigate-right",
    // Handled directly by libghostty's key processing (font rendering is internal to the terminal).
    "increase-font-size",
    "decrease-font-size",
  ]

  /// Actions that have menu items but use notification dispatch or interpolated IDs
  /// rather than the literal action("id") pattern.
  private static let alternativeMenuDispatch: Set<String> = [
    // Uses NotificationCenter.default.post(name: .myttyRenameTab) directly
    "rename-tab",
    // Registered via ForEach(1...9) with action("focus-tab-\(index)")
    "focus-tab-1", "focus-tab-2", "focus-tab-3", "focus-tab-4", "focus-tab-5",
    "focus-tab-6", "focus-tab-7", "focus-tab-8", "focus-tab-9",
  ]

  func testEveryGlobalBoundActionHasMenuItem() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Mytty/App/MyttyApp.swift")
    let source = try String(contentsOf: url, encoding: .utf8)

    let globalBindings = KeybindingStore.defaultBindings[.global]!.keys
    let excluded = Self.noMenuItem.union(Self.alternativeMenuDispatch)
    let needsMenuItem = Set(globalBindings).subtracting(excluded)

    var missing: [String] = []
    for actionID in needsMenuItem.sorted() {
      if !source.contains("action(\"\(actionID)\")") {
        missing.append(actionID)
      }
    }

    XCTAssertEqual(
      missing, [],
      "Actions with global keybindings but no menu item in MyttyApp.swift: \(missing). "
        + "Add a Button with .keyboardShortcut(from:) in MyttyApp.swift, "
        + "or add to MenuSyncTests.noMenuItem with a comment explaining the alternative dispatch path."
    )
  }
}
