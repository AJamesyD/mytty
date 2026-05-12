import XCTest

@testable import Mytty

@MainActor
final class WhichKeyManagerTests: XCTestCase {

  private var manager: WhichKeyManager!
  private var flagSet = false

  private func makeBindings() -> [WhichKeyBinding] {
    [
      WhichKeyBinding(
        key: "a",
        action: .command(label: "Action A", shortcut: nil) { [self] in
          flagSet = true
        }),
      WhichKeyBinding(
        key: "g",
        action: .group(
          label: "Group",
          children: [
            WhichKeyBinding(
              key: "x",
              action: .command(label: "Nested", shortcut: nil) { [self] in
                flagSet = true
              })
          ])),
    ]
  }

  override func setUp() {
    manager = WhichKeyManager()
    flagSet = false
  }

  override func tearDown() {
    manager.deactivate()
    manager = nil
  }

  // MARK: - Tests

  func test_activate_setsIsActive() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 2)
  }

  func test_deactivate_clearsState() {
    manager.activate(bindings: makeBindings())
    manager.deactivate()
    XCTAssertFalse(manager.isActive)
    XCTAssertTrue(manager.currentBindings.isEmpty)
  }

  func test_escapeKey_deactivates() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.handleKey("\u{1B}"))
    XCTAssertFalse(manager.isActive)
  }

  func test_commandKey_executesAndDeactivates() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.handleKey("a"))
    XCTAssertTrue(flagSet)
    XCTAssertFalse(manager.isActive)
  }

  func test_groupKey_navigatesDeeper() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.handleKey("g"))
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 1)
    XCTAssertEqual(manager.currentBindings.first?.key, "x")
    XCTAssertEqual(manager.breadcrumb, ["Group"])
  }

  func test_unknownKey_consumed() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.handleKey("z"))
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 2)
  }

  func test_doubleActivate_ignored() {
    let bindings = makeBindings()
    manager.activate(bindings: bindings)
    manager.activate(bindings: [
      WhichKeyBinding(key: "q", action: .command(label: "Other", shortcut: nil) {})
    ])
    XCTAssertEqual(manager.currentBindings.count, 2)
    XCTAssertEqual(manager.currentBindings.first?.key, "a")
  }

  func test_breadcrumb_tracksPath() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.breadcrumb.isEmpty)
    _ = manager.handleKey("g")
    XCTAssertEqual(manager.breadcrumb, ["Group"])
  }

  func test_backspace_atRoot_consumesKey() {
    manager.activate(bindings: makeBindings())
    XCTAssertTrue(manager.handleKey("\u{7F}"))
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 2)
    XCTAssertTrue(manager.breadcrumb.isEmpty)
  }

  func test_backspace_whenNested_navigatesUp() {
    manager.activate(bindings: makeBindings())
    _ = manager.handleKey("g")
    _ = manager.handleKey("\u{7F}")
    XCTAssertTrue(manager.isActive)
    XCTAssertTrue(manager.breadcrumb.isEmpty)
    XCTAssertEqual(manager.currentBindings.count, 2)
  }

  func test_backspace_multiLevel_navigatesOneLevel() {
    let deepBindings: [WhichKeyBinding] = [
      WhichKeyBinding(
        key: "g",
        action: .group(
          label: "Group",
          children: [
            WhichKeyBinding(
              key: "h",
              action: .group(
                label: "SubGroup",
                children: [
                  WhichKeyBinding(key: "x", action: .command(label: "Leaf", shortcut: nil) {})
                ]))
          ]))
    ]
    manager.activate(bindings: deepBindings)
    _ = manager.handleKey("g")
    _ = manager.handleKey("h")
    XCTAssertEqual(manager.breadcrumb, ["Group", "SubGroup"])
    _ = manager.handleKey("\u{7F}")
    XCTAssertEqual(manager.breadcrumb, ["Group"])
    XCTAssertEqual(manager.currentBindings.count, 1)
    XCTAssertEqual(manager.currentBindings.first?.key, "h")
  }

  func test_backspace_afterNavigateUp_canReenter() {
    manager.activate(bindings: makeBindings())
    _ = manager.handleKey("g")
    _ = manager.handleKey("\u{7F}")
    _ = manager.handleKey("g")
    XCTAssertEqual(manager.breadcrumb, ["Group"])
    XCTAssertEqual(manager.currentBindings.count, 1)
  }

  func test_showContinuations_activatesAndSetsBindings() {
    let bindings: [WhichKeyBinding] = [
      WhichKeyBinding(key: "a", action: .command(label: "Cont", shortcut: nil) {})
    ]
    manager.showContinuations(bindings)
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 1)
    XCTAssertEqual(manager.currentBindings.first?.key, "a")
    XCTAssertTrue(manager.breadcrumb.isEmpty)
  }

  // MARK: - buildBindings tabCount filtering

  func test_buildBindings_filtersTabEntriesBeyondTabCount() {
    let registry = (1...9).map { i in
      AppAction(id: "focus-tab-\(i)", label: "Tab \(i)", category: "navigation") {}
    }
    let groups = [
      WhichKeyGroup(
        name: "tabs", key: "t",
        bindings: (1...9).map { WhichKeyNode(action: "focus-tab-\($0)", key: "\($0)") })
    ]
    let bindings = WhichKeyManager.buildBindings(
      registry: registry, groups: groups, tabCount: 3,
      sessionCount: 1, paneCount: 1, keybindingStore: KeybindingStore())
    guard case .group(_, let children) = bindings.first?.action else {
      XCTFail("Expected a group binding")
      return
    }
    XCTAssertEqual(children.count, 3)
  }

  func test_buildBindings_showsAllTabEntriesWhenTabCountIsHigher() {
    let registry = (1...9).map { i in
      AppAction(id: "focus-tab-\(i)", label: "Tab \(i)", category: "navigation") {}
    }
    let groups = [
      WhichKeyGroup(
        name: "tabs", key: "t",
        bindings: (1...5).map { WhichKeyNode(action: "focus-tab-\($0)", key: "\($0)") })
    ]
    let bindings = WhichKeyManager.buildBindings(
      registry: registry, groups: groups, tabCount: 9,
      sessionCount: 1, paneCount: 1, keybindingStore: KeybindingStore())
    guard case .group(_, let children) = bindings.first?.action else {
      XCTFail("Expected a group binding")
      return
    }
    XCTAssertEqual(children.count, 5)
  }

  func test_buildBindings_nonTabActionsUnaffectedByTabCount() {
    let registry = [
      AppAction(id: "new-tab", label: "New Tab", category: "tab") {},
      AppAction(id: "close-tab", label: "Close Tab", category: "tab") {},
      AppAction(id: "focus-tab-1", label: "Tab 1", category: "navigation") {},
    ]
    let groups = [
      WhichKeyGroup(
        name: "tabs", key: "t",
        bindings: [
          WhichKeyNode(action: "new-tab", key: "n"),
          WhichKeyNode(action: "close-tab", key: "c"),
          WhichKeyNode(action: "focus-tab-1", key: "1"),
        ])
    ]
    let bindings = WhichKeyManager.buildBindings(
      registry: registry, groups: groups, tabCount: 0,
      sessionCount: 1, paneCount: 1, keybindingStore: KeybindingStore())
    guard case .group(_, let children) = bindings.first?.action else {
      XCTFail("Expected a group binding")
      return
    }
    // new-tab remains; close-tab filtered (tabCount<=1), focus-tab-1 filtered (tabCount=0)
    XCTAssertEqual(children.count, 1)
  }
}
