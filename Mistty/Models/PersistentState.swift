import Foundation

struct PersistentState: Codable {
  static let currentVersion = 1
  let version: Int
  var activeSessionIndex: Int?
  var sessions: [PersistentSession]
}

struct PersistentSession: Codable {
  let name: String
  let directory: URL
  var sshCommand: String?
  var activeTabIndex: Int?
  var tabs: [PersistentTab]
}

struct PersistentTab: Codable {
  var customTitle: String?
  var directory: URL?
  var activePaneIndex: Int?
  var layout: PersistentLayoutNode
}

struct PersistentPane: Codable {
  var directory: URL?
  var command: String?
  var useCommandField: Bool
}

indirect enum PersistentLayoutNode: Codable {
  case leaf(PersistentPane)
  case split(SplitDirection, PersistentLayoutNode, PersistentLayoutNode, CGFloat)
}
