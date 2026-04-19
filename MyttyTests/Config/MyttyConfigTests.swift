import XCTest

@testable import Mytty

final class MyttyConfigTests: XCTestCase {
  func test_defaultConfig() {
    let config = MyttyConfig.default
    XCTAssertEqual(config.sidebarMode, .pinned)
    XCTAssertEqual(config.tabBarMode, .pinned)
  }

  func test_parsesValidTOML() throws {
    let toml = """
      [sidebar]
      mode = "auto-hide"
      position = "right"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.sidebarMode, .autoHide)
    XCTAssertEqual(config.sidebarPosition, .right)
  }

  func test_missingKeysUseDefaults() throws {
    let config = try MyttyConfig.parse("")
    XCTAssertEqual(config.sidebarMode, .pinned)
    XCTAssertEqual(config.tabBarMode, .pinned)
  }

  func test_invalidTOMLThrows() {
    XCTAssertThrowsError(try MyttyConfig.parse("x = !!!invalid"))
  }

  func test_parsesPopupDefinitions() throws {
    let toml = """
      [[popup]]
      name = "lazygit"
      command = "lazygit"
      shortcut = "cmd+shift+g"
      width = 0.8
      height = 0.8
      close_on_exit = true

      [[popup]]
      name = "btop"
      command = "btop"
      width = 0.9
      height = 0.9
      close_on_exit = false
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.popups.count, 2)
    XCTAssertEqual(config.popups[0].name, "lazygit")
    XCTAssertEqual(config.popups[0].command, "lazygit")
    XCTAssertEqual(config.popups[0].shortcut, "cmd+shift+g")
    XCTAssertEqual(config.popups[0].width, 0.8)
    XCTAssertEqual(config.popups[0].height, 0.8)
    XCTAssertTrue(config.popups[0].closeOnExit)
    XCTAssertEqual(config.popups[1].name, "btop")
    XCTAssertNil(config.popups[1].shortcut)
    XCTAssertFalse(config.popups[1].closeOnExit)
  }

  func test_noPopupsReturnsEmptyArray() throws {
    let config = try MyttyConfig.parse("")
    XCTAssertEqual(config.popups.count, 0)
  }

  func test_popupDefaultValues() throws {
    let toml = """
      [[popup]]
      name = "test"
      command = "test"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.popups[0].width, 0.8)
    XCTAssertEqual(config.popups[0].height, 0.8)
    XCTAssertTrue(config.popups[0].closeOnExit)
    XCTAssertNil(config.popups[0].shortcut)
  }

  func test_parsesSSHConfig() throws {
    let toml = """
      [ssh]
      default_command = "et"

      [[ssh.host]]
      hostname = "dev-box"
      command = "et"

      [[ssh.host]]
      regex = "prod-.*"
      command = "ssh"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.ssh.defaultCommand, "et")
    XCTAssertEqual(config.ssh.hosts.count, 2)
    XCTAssertEqual(config.ssh.hosts[0].hostname, "dev-box")
    XCTAssertNil(config.ssh.hosts[0].regex)
    XCTAssertEqual(config.ssh.hosts[0].command, "et")
    XCTAssertNil(config.ssh.hosts[1].hostname)
    XCTAssertEqual(config.ssh.hosts[1].regex, "prod-.*")
    XCTAssertEqual(config.ssh.hosts[1].command, "ssh")
  }

  func test_sshConfigDefaults() throws {
    let config = try MyttyConfig.parse("")
    XCTAssertEqual(config.ssh.defaultCommand, "ssh")
    XCTAssertTrue(config.ssh.hosts.isEmpty)
  }

  func test_sshCommandResolution_exactMatch() throws {
    let toml = """
      [[ssh.host]]
      hostname = "dev-box"
      command = "et"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.ssh.resolveCommand(for: "dev-box"), "et")
    XCTAssertEqual(config.ssh.resolveCommand(for: "other"), "ssh")
  }

  func test_sshCommandResolution_regexMatch() throws {
    let toml = """
      [[ssh.host]]
      regex = "prod-.*"
      command = "et"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.ssh.resolveCommand(for: "prod-web1"), "et")
    XCTAssertEqual(config.ssh.resolveCommand(for: "staging-web1"), "ssh")
  }

  func test_sshCommandResolution_firstMatchWins() throws {
    let toml = """
      [[ssh.host]]
      hostname = "prod-db"
      command = "ssh"

      [[ssh.host]]
      regex = "prod-.*"
      command = "et"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.ssh.resolveCommand(for: "prod-db"), "ssh")
    XCTAssertEqual(config.ssh.resolveCommand(for: "prod-web"), "et")
  }

  func test_parsesPanelConfig() throws {
    let toml = """
      [sidebar]
      mode = "auto-hide"

      [tab-bar]
      mode = "hidden"
      hide-when-single-tab = false

      [auto-hide]
      dwell-ms = 200
      dismiss-delay-ms = 400
      show-hints = false
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.sidebarMode, .autoHide)
    XCTAssertEqual(config.tabBarMode, .hidden)
    XCTAssertFalse(config.hideTabBarWhenSingleTab)
    XCTAssertEqual(config.autoHideDwellMs, 200)
    XCTAssertEqual(config.autoHideDismissDelayMs, 400)
    XCTAssertFalse(config.autoHideShowHints)
  }

  func test_panelConfigDefaults() throws {
    let config = try MyttyConfig.parse("")
    XCTAssertEqual(config.sidebarMode, .pinned)
    XCTAssertEqual(config.tabBarMode, .pinned)
    XCTAssertTrue(config.hideTabBarWhenSingleTab)
    XCTAssertEqual(config.autoHideDwellMs, 150)
    XCTAssertEqual(config.autoHideDismissDelayMs, 300)
    XCTAssertTrue(config.autoHideShowHints)
  }

  func test_backwardCompat_sidebarVisibleFalse() throws {
    let toml = """
      sidebar_visible = false
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.sidebarMode, .hidden)
  }

  func test_backwardCompat_sidebarVisibleTrue() throws {
    let toml = """
      sidebar_visible = true
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.sidebarMode, .pinned)
  }

  func test_sidebarTableOverridesLegacy() throws {
    let toml = """
      sidebar_visible = false

      [sidebar]
      mode = "pinned"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(config.sidebarMode, .pinned)
  }

  func test_parsesKeybindingsSection() throws {
    let toml = """
      [keybindings]
      split-horizontal = "cmd+shift+d"
      new-tab = "unbind"
      passthrough-processes = ["nvim", "kakoune"]

      [keybindings.window-mode]
      zoom = "x"

      [keybindings.which-key.window]
      zoom = "z"
      swap-left = "h"
      """
    let config = try MyttyConfig.parse(toml)
    XCTAssertEqual(
      config.keybindingStore.trigger(for: "split-horizontal", in: .global),
      KeyboardTrigger(prefix: nil, modifiers: [.cmd, .shift], key: "d")
    )
    XCTAssertNil(config.keybindingStore.trigger(for: "new-tab", in: .global))
    XCTAssertEqual(
      config.keybindingStore.trigger(for: "zoom", in: .windowMode),
      KeyboardTrigger(prefix: nil, modifiers: [], key: "x")
    )
    XCTAssertEqual(config.keybindingStore.whichKeyGroups.count, 1)
    XCTAssertEqual(config.keybindingStore.whichKeyGroups[0].name, "window")
    XCTAssertEqual(config.keybindingStore.passthroughProcesses, ["nvim", "kakoune"])
  }
}
