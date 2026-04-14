enum SplitDirection: Sendable, Equatable, Codable {
  case horizontal, vertical

  var toggled: SplitDirection {
    switch self {
    case .horizontal: return .vertical
    case .vertical: return .horizontal
    }
  }
}
