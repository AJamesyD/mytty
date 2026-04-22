import Foundation

struct MyttySessionSourceItem: Sendable, Equatable {
  let name: String
  let path: String?
  let subtitle: String?
  let dedupKey: String
}
