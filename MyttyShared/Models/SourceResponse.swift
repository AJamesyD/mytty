import Foundation

public struct SourceResponse: Codable, Sendable {
  public let name: String
  public let command: String
  public let action: String
  public let priority: Int
  public let timeoutMs: Int
  public let maxItems: Int
  public let lastStatus: String

  enum CodingKeys: String, CodingKey {
    case name, command, action, priority
    case timeoutMs = "timeout_ms"
    case maxItems = "max_items"
    case lastStatus = "last_status"
  }

  public init(
    name: String, command: String, action: String, priority: Int,
    timeoutMs: Int, maxItems: Int, lastStatus: String
  ) {
    self.name = name
    self.command = command
    self.action = action
    self.priority = priority
    self.timeoutMs = timeoutMs
    self.maxItems = maxItems
    self.lastStatus = lastStatus
  }
}
