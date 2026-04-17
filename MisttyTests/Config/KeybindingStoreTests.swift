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
      passthroughProcesses: nil
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
        "split-horizontal": KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "d")
      ]
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil
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
        "new-tab": KeyboardTrigger(prefix: nil, modifiers: [], key: "__unbind__")
      ]
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil
    )
    XCTAssertNil(store.trigger(for: "new-tab", in: .global))
  }

  func test_resetMode() {
    let overrides: [BindingMode: [String: KeyboardTrigger]] = [
      .windowMode: [
        "zoom": KeyboardTrigger(prefix: nil, modifiers: [], key: "x")
      ]
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [.windowMode],
      globalReset: false,
      passthroughProcesses: nil
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
        "new-tab": KeyboardTrigger(prefix: nil, modifiers: [.cmd], key: "n")
      ]
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: true,
      passthroughProcesses: nil
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
      ]
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
      WhichKeyGroup(
        name: "custom",
        bindings: [
          WhichKeyNode(action: "do-thing", key: "x")
        ])
    ]
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: userGroups,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil
    )
    XCTAssertEqual(store.whichKeyGroups.count, 1)
    XCTAssertEqual(store.whichKeyGroups[0].name, "custom")
  }

  func test_passthroughProcesses() {
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: ["nvim", "kakoune"]
    )
    XCTAssertEqual(store.passthroughProcesses, ["nvim", "kakoune"])
  }

  func test_passthroughProcessesDefault() {
    let store = KeybindingStore.build(
      defaults: KeybindingStore.defaultBindings,
      defaultWhichKey: KeybindingStore.defaultWhichKeyGroups,
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil
    )
    XCTAssertEqual(store.passthroughProcesses, ["nvim", "neovim", "vim", "helix", "lazygit"])
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

  func test_sequenceTrieConstruction() {
    let sequences: [String: KeySequence] = [
      "navigate-left": KeySequence(
        prefix: nil,
        triggers: [
          KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a"),
          KeyboardTrigger(prefix: nil, modifiers: [], key: "h"),
        ]),
      "navigate-right": KeySequence(
        prefix: nil,
        triggers: [
          KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a"),
          KeyboardTrigger(prefix: nil, modifiers: [], key: "l"),
        ]),
    ]
    let store = KeybindingStore.build(
      defaults: [:],
      defaultWhichKey: [],
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil,
      sequenceOverrides: sequences
    )
    let leader = KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
    XCTAssertEqual(store.sequenceTrie.children.count, 1)
    let leaderNode = store.sequenceTrie.children[leader]
    XCTAssertNotNil(leaderNode)
    XCTAssertEqual(leaderNode!.children.count, 2)
    let hKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "h")
    let lKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "l")
    XCTAssertEqual(leaderNode!.children[hKey]?.action, "navigate-left")
    XCTAssertEqual(leaderNode!.children[lKey]?.action, "navigate-right")
  }

  func test_leaderShadowsStandalone() {
    let overrides: [BindingMode: [String: KeyboardTrigger]] = [
      .global: [
        "some-action": KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
      ]
    ]
    let sequences: [String: KeySequence] = [
      "navigate-left": KeySequence(
        prefix: nil,
        triggers: [
          KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a"),
          KeyboardTrigger(prefix: nil, modifiers: [], key: "h"),
        ])
    ]
    let store = KeybindingStore.build(
      defaults: [:],
      defaultWhichKey: [],
      userOverrides: overrides,
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil,
      sequenceOverrides: sequences
    )
    XCTAssertNil(store.trigger(for: "some-action", in: .global))
    XCTAssertTrue(
      store.warnings.contains { $0.contains("sequence leader") && $0.contains("some-action") })
    let leader = KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
    let hKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "h")
    XCTAssertNotNil(store.sequenceTrie.children[leader]?.children[hKey])
  }

  func test_sequenceTimeoutDefault() {
    let store = KeybindingStore.build(
      defaults: [:],
      defaultWhichKey: [],
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil
    )
    XCTAssertEqual(store.sequenceTimeout, 1.0)
  }

  func test_sequenceTimeoutCustom() {
    let store = KeybindingStore.build(
      defaults: [:],
      defaultWhichKey: [],
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil,
      sequenceTimeout: 2.5
    )
    XCTAssertEqual(store.sequenceTimeout, 2.5)
  }

  func test_unconsumedSequence() {
    let sequences: [String: KeySequence] = [
      "navigate-left": KeySequence(
        prefix: .unconsumed,
        triggers: [
          KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a"),
          KeyboardTrigger(prefix: nil, modifiers: [], key: "h"),
        ])
    ]
    let store = KeybindingStore.build(
      defaults: [:],
      defaultWhichKey: [],
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil,
      sequenceOverrides: sequences
    )
    let leader = KeyboardTrigger(prefix: nil, modifiers: [.ctrl], key: "a")
    let hKey = KeyboardTrigger(prefix: nil, modifiers: [], key: "h")
    XCTAssertEqual(store.sequenceTrie.children[leader]?.children[hKey]?.isUnconsumed, true)
  }

  func test_emptySequenceOverrides() {
    let store = KeybindingStore.build(
      defaults: [:],
      defaultWhichKey: [],
      userOverrides: [:],
      userWhichKey: nil,
      resets: [],
      globalReset: false,
      passthroughProcesses: nil,
      sequenceOverrides: [:]
    )
    XCTAssertTrue(store.sequenceTrie.children.isEmpty)
  }
}
