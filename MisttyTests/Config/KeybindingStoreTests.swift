import XCTest

@testable import Mistty

final class KeybindingStoreTests: XCTestCase {
  func test_defaultsOnly() {
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      vimLikeProcesses: nil
    )
    XCTAssertEqual(
      store.trigger(for: "new-tab", in: .global),
      KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "t")
    )
    XCTAssertEqual(
      store.trigger(for: "zoom", in: .windowMode),
      KeyboardTrigger(prefix: nil, modifiers: [], key: "z")
    )
    XCTAssertEqual(
      store.trigger(for: "top", in: .copyMode),
      KeyboardTrigger(prefix: nil, modifiers: [], key: "gg")
    )
  }

  func test_singleOverride() {
    let overrides: [BindingMode: [String: KeyboardTrigger]] = [
      .global: [
        "split-horizontal": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "d"),
      ],
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      vimLikeProcesses: nil
    )
    XCTAssertEqual(
      store.trigger(for: "split-horizontal", in: .global),
      KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "d")
    )
    XCTAssertEqual(
      store.trigger(for: "new-tab", in: .global),
      KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "t")
    )
  }

  func test_unbind() {
    let overrides: [BindingMode: [String: KeyboardTrigger]] = [
      .global: [
        "new-tab": KeyboardTrigger(prefix: nil, modifiers: [], key: "__unbind__"),
      ],
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      vimLikeProcesses: nil
    )
    XCTAssertNil(store.trigger(for: "new-tab", in: .global))
  }

  func test_resetMode() {
    let overrides: [BindingMode: [String: KeyboardTrigger]] = [
      .windowMode: [
        "zoom": KeyboardTrigger(prefix: nil, modifiers: [], key: "x"),
      ],
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [.windowMode],
      globalReset: false,
      vimLikeProcesses: nil
    )
    XCTAssertEqual(
      store.trigger(for: "zoom", in: .windowMode),
      KeyboardTrigger(prefix: nil, modifiers: [], key: "x")
    )
    XCTAssertNil(store.trigger(for: "exit", in: .windowMode))
    XCTAssertNotNil(store.trigger(for: "new-tab", in: .global))
  }

  func test_globalReset() {
    let overrides: [BindingMode: [String: KeyboardTrigger]] = [
      .global: [
        "new-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "n"),
      ],
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: true,
      vimLikeProcesses: nil
    )
    XCTAssertEqual(
      store.trigger(for: "new-tab", in: .global),
      KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "n")
    )
    XCTAssertNil(store.trigger(for: "close-pane", in: .global))
    XCTAssertNil(store.trigger(for: "zoom", in: .windowMode))
  }

  func test_conflictDetection() {
    let bindings: [BindingMode: [String: KeyboardTrigger]] = [
      .global: [
        "action-a": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "d"),
        "action-b": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "d"),
      ],
    ]
    let warnings = KeybindingStore.detectConflicts(bindings: bindings)
    XCTAssertEqual(warnings.count, 1)
    XCTAssertTrue(warnings[0].contains("action-a"))
    XCTAssertTrue(warnings[0].contains("action-b"))
  }

  func test_noConflictAcrossModes() {
    let trigger = KeyboardTrigger(prefix: nil, modifiers: [], key: "z")
    let bindings: [BindingMode: [String: KeyboardTrigger]] = [
      .windowMode: ["zoom": trigger],
      .copyMode: ["something": trigger],
    ]
    let warnings = KeybindingStore.detectConflicts(bindings: bindings)
    XCTAssertTrue(warnings.isEmpty)
  }

  func test_whichKeyOverride() {
    let userGroups = [
      WhichKeyGroup(name: "custom", bindings: [
        WhichKeyNode(action: "do-thing", key: "x"),
      ]),
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: userGroups,
      resets: [],
      globalReset: false,
      vimLikeProcesses: nil
    )
    XCTAssertEqual(store.whichKeyGroups.count, 1)
    XCTAssertEqual(store.whichKeyGroups[0].name, "custom")
  }

  func test_vimLikeProcesses() {
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      vimLikeProcesses: ["nvim", "kakoune"]
    )
    XCTAssertEqual(store.vimLikeProcesses, ["nvim", "kakoune"])
  }

  func test_vimLikeProcessesDefault() {
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      vimLikeProcesses: nil
    )
    XCTAssertEqual(store.vimLikeProcesses, ["nvim", "vim", "helix", "lazygit"])
  }

  func test_multiBindArray() throws {
    let toml = """
      [keybindings]
      toggle-sidebar = ["cmd+s", "cmd+shift+s"]
      """
    let config = try MisttyConfig.parse(toml)
    XCTAssertEqual(
      config.keybindingStore.trigger(for: "toggle-sidebar", in: .global),
      KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "s")
    )
  }
}
