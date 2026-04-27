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
        action: .command(label: "Action A") { [self] in
          flagSet = true
        }),
      WhichKeyBinding(
        key: "g",
        action: .group(
          label: "Group",
          children: [
            WhichKeyBinding(
              key: "x",
              action: .command(label: "Nested") { [self] in
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

  func test_unknownKey_ignored() {
    manager.activate(bindings: makeBindings())
    XCTAssertFalse(manager.handleKey("z"))
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 2)
  }

  func test_doubleActivate_ignored() {
    let bindings = makeBindings()
    manager.activate(bindings: bindings)
    manager.activate(bindings: [
      WhichKeyBinding(key: "q", action: .command(label: "Other") {})
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
                  WhichKeyBinding(key: "x", action: .command(label: "Leaf") {})
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
      WhichKeyBinding(key: "a", action: .command(label: "Cont") {})
    ]
    manager.showContinuations(bindings)
    XCTAssertTrue(manager.isActive)
    XCTAssertEqual(manager.currentBindings.count, 1)
    XCTAssertEqual(manager.currentBindings.first?.key, "a")
    XCTAssertTrue(manager.breadcrumb.isEmpty)
  }
}
