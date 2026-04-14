import XCTest

@testable import Mistty

@MainActor
final class PanelStateTests: XCTestCase {
  func test_defaultState() {
    let state = PanelState()
    XCTAssertEqual(state.sidebarMode, .pinned)
    XCTAssertEqual(state.tabBarMode, .pinned)
    XCTAssertTrue(state.hideTabBarWhenSingleTab)
    XCTAssertFalse(state.isSidebarRevealed)
    XCTAssertFalse(state.isSidebarTempPinned)
  }

  func test_shouldShowSidebar_pinned() {
    let state = PanelState()
    state.sidebarMode = .pinned
    XCTAssertTrue(state.shouldShowSidebar)
    state.isSidebarRevealed = true
    XCTAssertTrue(state.shouldShowSidebar)
  }

  func test_shouldShowSidebar_autoHide_notRevealed() {
    let state = PanelState()
    state.sidebarMode = .autoHide
    state.isSidebarRevealed = false
    XCTAssertFalse(state.shouldShowSidebar)
  }

  func test_shouldShowSidebar_autoHide_revealed() {
    let state = PanelState()
    state.sidebarMode = .autoHide
    state.isSidebarRevealed = true
    XCTAssertTrue(state.shouldShowSidebar)
  }

  func test_shouldShowSidebar_hidden_notRevealed() {
    let state = PanelState()
    state.sidebarMode = .hidden
    state.isSidebarRevealed = false
    XCTAssertFalse(state.shouldShowSidebar)
  }

  func test_shouldShowTabBar_pinned_multipleTabs() {
    let state = PanelState()
    state.tabBarMode = .pinned
    XCTAssertTrue(state.shouldShowTabBar(tabCount: 3))
  }

  func test_shouldShowTabBar_pinned_singleTab_hideEnabled() {
    let state = PanelState()
    state.tabBarMode = .pinned
    state.hideTabBarWhenSingleTab = true
    XCTAssertFalse(state.shouldShowTabBar(tabCount: 1))
  }

  func test_shouldShowTabBar_pinned_singleTab_hideDisabled() {
    let state = PanelState()
    state.tabBarMode = .pinned
    state.hideTabBarWhenSingleTab = false
    XCTAssertTrue(state.shouldShowTabBar(tabCount: 1))
  }

  func test_shouldShowTabBar_autoHide_revealed() {
    let state = PanelState()
    state.tabBarMode = .autoHide
    state.isTabBarRevealed = true
    XCTAssertTrue(state.shouldShowTabBar(tabCount: 2))
  }

  func test_shouldShowTabBar_autoHide_notRevealed() {
    let state = PanelState()
    state.tabBarMode = .autoHide
    state.isTabBarRevealed = false
    XCTAssertFalse(state.shouldShowTabBar(tabCount: 2))
  }

  func test_sidebarIsPinned() {
    let state = PanelState()
    state.sidebarMode = .pinned
    XCTAssertTrue(state.sidebarIsPinned)
    state.sidebarMode = .autoHide
    XCTAssertFalse(state.sidebarIsPinned)
    state.sidebarMode = .hidden
    XCTAssertFalse(state.sidebarIsPinned)
  }

  func test_tabBarIsPinned_singleTab_hideEnabled() {
    let state = PanelState()
    state.tabBarMode = .pinned
    state.hideTabBarWhenSingleTab = true
    XCTAssertFalse(state.tabBarIsPinned(tabCount: 1))
  }

  func test_tabBarIsPinned_multipleTabs() {
    let state = PanelState()
    state.tabBarMode = .pinned
    XCTAssertTrue(state.tabBarIsPinned(tabCount: 2))
    state.tabBarMode = .autoHide
    XCTAssertFalse(state.tabBarIsPinned(tabCount: 2))
  }

  func test_panelMode_configRoundTrip() {
    for mode in PanelMode.allCases {
      XCTAssertEqual(PanelMode.fromConfig(mode.configValue), mode)
    }
  }

  func test_panelMode_fromConfig_invalid() {
    XCTAssertNil(PanelMode.fromConfig("bogus"))
  }
}
