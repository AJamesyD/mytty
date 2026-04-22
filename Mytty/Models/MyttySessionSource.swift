import Foundation

struct MyttySessionSource: Sendable, Equatable {
  let name: String
  let command: String
  let action: Action
  let priority: Int
  let timeoutMs: Int
  let maxItems: Int
  var lastStatus: Status = .notRun

  enum Action: String, Sendable, Equatable {
    case createSession = "create-session"
    case focusSession = "focus-session"
  }

  enum Status: String, Sendable, Equatable, Codable {
    case ok, timeout, error
    case notRun = "not-run"
  }
}
