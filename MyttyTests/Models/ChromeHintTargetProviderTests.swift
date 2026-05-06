// swiftlint:disable force_unwrapping
import XCTest

@testable import Mytty

@MainActor
final class ChromeHintTargetProviderTests: XCTestCase {
  private var store: SessionStore!

  override func setUp() async throws {
    await MainActor.run {
      store = SessionStore()
    }
  }

  private let defaultGeometry = HintsGeometry.chrome(elementFrames: [:])

  private func makeFrames(for keys: [String]) -> [String: CGRect] {
    var frames: [String: CGRect] = [:]
    for (index, key) in keys.enumerated() {
      frames[key] = CGRect(x: 0, y: CGFloat(index * 30), width: 200, height: 24)
    }
    return frames
  }

  private func makeProvider(frames: [String: CGRect] = [:], sidebarVisible: Bool = true)
    -> ChromeHintTargetProvider
  {
    ChromeHintTargetProvider(store: store, elementFrames: frames, sidebarVisible: sidebarVisible)
  }

  // MARK: - Tests

  func test_emptyStore_returnsNoTargets() {
    let provider = makeProvider()
    let targets = provider.targets(in: defaultGeometry)
    XCTAssertEqual(targets.count, 0)
  }

  func test_sessionsWithFrames_returnsSessionTargets() {
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    // s2 is active (id=2), s1 (id=1) should appear
    let frames = makeFrames(for: ["session-1", "session-2"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let sessionTargets = targets.filter { $0.id.hasPrefix("session-") }
    XCTAssertEqual(sessionTargets.count, 1)
    XCTAssertEqual(sessionTargets[0].id, "session-1")
  }

  func test_skipsActiveSession() {
    let session = store.createSession(name: "active", directory: URL(fileURLWithPath: "/tmp"))
    let frames = makeFrames(for: ["session-\(session.id)"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let sessionTargets = targets.filter { $0.id.hasPrefix("session-") }
    XCTAssertEqual(sessionTargets.count, 0)
  }

  func test_skipsRenamingSession() {
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    let s2 = store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    // s2 is active; make s1 renaming
    store.sessions[0].isRenaming = true
    let frames = makeFrames(for: ["session-1", "session-\(s2.id)"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let sessionTargets = targets.filter { $0.id.hasPrefix("session-") }
    XCTAssertEqual(sessionTargets.count, 0)
  }

  func test_sidebarNotVisible_skipsSessionsAndSidebarTabs() {
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    let frames = makeFrames(for: ["session-1", "sidebar-tab-1-1"])
    let provider = makeProvider(frames: frames, sidebarVisible: false)
    let targets = provider.targets(in: defaultGeometry)
    let sessionTargets = targets.filter { $0.id.hasPrefix("session-") }
    let sidebarTabTargets = targets.filter { $0.id.hasPrefix("sidebar-tab-") }
    XCTAssertEqual(sessionTargets.count, 0)
    XCTAssertEqual(sidebarTabTargets.count, 0)
  }

  func test_expandedSessionTabs_returnsSidebarTabTargets() {
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    // s1 has id=1, its first tab has id=1; add a second tab
    store.sessions[0].addTab()
    // Create s2 so s1 is no longer active
    store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    // s1 tabs: id=1, id=2. Both should appear as sidebar-tab targets
    let frames = makeFrames(for: ["session-1", "sidebar-tab-1-1", "sidebar-tab-1-2"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let sidebarTabTargets = targets.filter { $0.id.hasPrefix("sidebar-tab-") }
    XCTAssertEqual(sidebarTabTargets.count, 2)
  }

  func test_collapsedSession_skipsSidebarTabs() {
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    store.sessions[0].addTab()
    store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    store.sessions[0].isSidebarExpanded = false
    let frames = makeFrames(for: ["sidebar-tab-1-1", "sidebar-tab-1-2"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let sidebarTabTargets = targets.filter { $0.id.hasPrefix("sidebar-tab-") }
    XCTAssertEqual(sidebarTabTargets.count, 0)
  }

  func test_skipsActiveTab() {
    let session = store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    // Active tab is the last added (id=2)
    let activeTabID = session.activeTab!.id
    let frames = makeFrames(for: [
      "sidebar-tab-\(session.id)-\(activeTabID)",
      "tabbar-tab-\(activeTabID)",
    ])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let matching = targets.filter { $0.id.contains("-\(activeTabID)") }
    XCTAssertEqual(matching.count, 0)
  }

  func test_skipsRenamingTab() {
    let session = store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    // Make the non-active tab renaming
    let nonActiveTab = session.tabs.first { $0.id != session.activeTab?.id }!
    nonActiveTab.isRenaming = true
    let frames = makeFrames(for: [
      "sidebar-tab-\(session.id)-\(nonActiveTab.id)",
      "tabbar-tab-\(nonActiveTab.id)",
    ])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    XCTAssertEqual(targets.count, 0)
  }

  func test_tabBarTabs_returnsTargets() {
    let session = store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    session.addTab()
    // Active tab is skipped; the first tab (id=1) should appear
    let nonActiveTab = session.tabs.first { $0.id != session.activeTab?.id }!
    let frames = makeFrames(for: ["tabbar-tab-\(nonActiveTab.id)"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let tabbarTargets = targets.filter { $0.id.hasPrefix("tabbar-tab-") }
    XCTAssertEqual(tabbarTargets.count, 1)
    XCTAssertEqual(tabbarTargets[0].id, "tabbar-tab-\(nonActiveTab.id)")
  }

  func test_panes_returnsTargets() {
    let session = store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.activeTab!
    tab.splitActivePane(direction: .horizontal)
    // tab has 2 panes; active pane is skipped
    let nonActivePane = tab.panes.first { $0.id != tab.activePane?.id }!
    let frames = makeFrames(for: ["pane-\(nonActivePane.id)"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let paneTargets = targets.filter { $0.id.hasPrefix("pane-") }
    XCTAssertEqual(paneTargets.count, 1)
    XCTAssertEqual(paneTargets[0].id, "pane-\(nonActivePane.id)")
  }

  func test_skipsActivePaneTarget() {
    let session = store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.activeTab!
    tab.splitActivePane(direction: .horizontal)
    let activePaneID = tab.activePane!.id
    let frames = makeFrames(for: ["pane-\(activePaneID)"])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let paneTargets = targets.filter { $0.id.hasPrefix("pane-") }
    XCTAssertEqual(paneTargets.count, 0)
  }

  func test_paneOriginOffset() {
    let session = store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    let tab = session.activeTab!
    tab.splitActivePane(direction: .horizontal)
    let nonActivePane = tab.panes.first { $0.id != tab.activePane?.id }!
    let frame = CGRect(x: 100, y: 200, width: 300, height: 400)
    let frames = ["pane-\(nonActivePane.id)": frame]
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)
    let paneTarget = targets.first { $0.id.hasPrefix("pane-") }!
    XCTAssertEqual(paneTarget.labelOrigin.x, 108)
    XCTAssertEqual(paneTarget.labelOrigin.y, 208)
  }

  func test_missingFrame_skipsElement() {
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    // s1 (id=1) is not active, but no frame provided for it
    let provider = makeProvider(frames: [:])
    let targets = provider.targets(in: defaultGeometry)
    XCTAssertEqual(targets.count, 0)
  }

  func test_spatialOrder() {
    // Create s1 with 2 tabs, then s2 (active)
    store.createSession(name: "s1", directory: URL(fileURLWithPath: "/tmp"))
    store.sessions[0].addTab()
    let s2 = store.createSession(name: "s2", directory: URL(fileURLWithPath: "/tmp"))
    s2.addTab()
    let activeTab = s2.activeTab!
    activeTab.splitActivePane(direction: .horizontal)

    let nonActiveTab = s2.tabs.first { $0.id != activeTab.id }!
    let nonActivePane = activeTab.panes.first { $0.id != activeTab.activePane?.id }!

    let frames = makeFrames(for: [
      "session-1",
      "sidebar-tab-1-1",
      "sidebar-tab-1-2",
      "tabbar-tab-\(nonActiveTab.id)",
      "pane-\(nonActivePane.id)",
    ])
    let provider = makeProvider(frames: frames)
    let targets = provider.targets(in: defaultGeometry)

    // Order: sessions, sidebar tabs, tabbar tabs, panes
    XCTAssertEqual(targets[0].id, "session-1")
    XCTAssertEqual(targets[1].id, "sidebar-tab-1-1")
    XCTAssertEqual(targets[2].id, "sidebar-tab-1-2")
    XCTAssertEqual(targets[3].id, "tabbar-tab-\(nonActiveTab.id)")
    XCTAssertEqual(targets[4].id, "pane-\(nonActivePane.id)")
  }
}
// swiftlint:enable force_unwrapping
