import Foundation

public struct PaneResponse: Codable, Sendable {
  public let id: Int
  public let directory: String?
  public let zoomed: Bool

  public init(id: Int, directory: String?, zoomed: Bool = false) {
    self.id = id
    self.directory = directory
    self.zoomed = zoomed
  }
}
