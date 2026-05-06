import Foundation

public protocol MyttyServiceProtocol {
  // MARK: - Sessions

  @MainActor func createSession(name: String, directory: String?, exec: String?) async throws
    -> Data
  @MainActor func listSessions() async throws -> Data
  @MainActor func getSession(id: Int) async throws -> Data
  @MainActor func closeSession(id: Int) async throws -> Data
  @MainActor func renameSession(id: Int, name: String) async throws -> Data

  // MARK: - Tabs

  @MainActor func createTab(sessionId: Int, name: String?, exec: String?) async throws -> Data
  @MainActor func listTabs(sessionId: Int) async throws -> Data
  @MainActor func getTab(id: Int) async throws -> Data
  @MainActor func closeTab(id: Int) async throws -> Data
  @MainActor func renameTab(id: Int, name: String) async throws -> Data
  @MainActor func moveTab(id: Int, toIndex: Int) async throws -> Data
  @MainActor func rotateTab(id: Int) async throws -> Data
  @MainActor func applyTabLayout(id: Int, name: String) async throws -> Data

  // MARK: - Panes

  @MainActor func createPane(tabId: Int, direction: String?) async throws -> Data
  @MainActor func listPanes(tabId: Int) async throws -> Data
  @MainActor func getPane(id: Int) async throws -> Data
  @MainActor func closePane(id: Int) async throws -> Data
  @MainActor func focusPane(id: Int) async throws -> Data
  @MainActor func focusPaneByDirection(direction: String, sessionId: Int) async throws -> Data
  @MainActor func resizePane(id: Int, direction: String, amount: Int) async throws -> Data
  @MainActor func activePane() async throws -> Data
  /// Use paneId 0 as sentinel for "active pane".
  @MainActor func sendKeys(paneId: Int, keys: String) async throws -> Data
  /// Use paneId 0 as sentinel for "active pane".
  @MainActor func runCommand(paneId: Int, command: String) async throws -> Data
  /// Use paneId 0 as sentinel for "active pane".
  @MainActor func getText(paneId: Int) async throws -> Data
  @MainActor func paneAtEdge(direction: String, sessionId: Int) async throws -> Data
  @MainActor func paneSetVar(paneId: Int, key: String, value: String?) async throws -> Data
  @MainActor func paneGetVar(paneId: Int, key: String) async throws -> Data
  @MainActor func swapPane(id: Int, direction: String) async throws -> Data
  @MainActor func zoomPane(id: Int, state: String) async throws -> Data
  @MainActor func breakPaneToTab(id: Int) async throws -> Data
  @MainActor func joinPane(id: Int, tabId: Int) async throws -> Data

  // MARK: - Windows

  @MainActor func listWindows() async throws -> Data
  @MainActor func getWindow(id: Int) async throws -> Data
  @MainActor func closeWindow(id: Int) async throws -> Data
  @MainActor func focusWindow(id: Int) async throws -> Data

  // MARK: - Popups

  @MainActor func openPopup(
    sessionId: Int,
    name: String,
    exec: String,
    width: Double,
    height: Double,
    closeOnExit: Bool
  ) async throws -> Data
  @MainActor func closePopup(id: Int) async throws -> Data
  @MainActor func togglePopup(sessionId: Int, name: String) async throws -> Data
  @MainActor func listPopups(sessionId: Int) async throws -> Data

  // MARK: - Sources

  @MainActor func listSources() async throws -> Data

  // MARK: - Hints

  @MainActor func activateHints() async throws -> Data
  @MainActor func activateChromeHints() async throws -> Data
}
