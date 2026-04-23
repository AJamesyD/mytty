import AppKit

@MainActor
struct TerminalHintTargetProvider: HintTargetProvider {
  let providerID = "terminal"

  private let lineReader: (Int) -> String?
  private let enabledTypes: Set<TerminalMatchType>

  init(
    lineReader: @escaping (Int) -> String?,
    enabledTypes: Set<TerminalMatchType> = Set(TerminalMatchType.allCases)
  ) {
    self.lineReader = lineReader
    self.enabledTypes = enabledTypes
  }

  func targets(in geometry: HintsGeometry) -> [any HintTarget] {
    guard
      case .terminal(let rows, _, let cellWidth, let cellHeight, let offsetX, let offsetY) =
        geometry
    else {
      return []
    }
    var results: [TerminalHintTarget] = []
    var nextID = 0
    for row in 0..<rows {
      guard let line = lineReader(row) else { continue }
      let matches = Self.findMatches(in: line, types: enabledTypes)
      for match in matches {
        let origin = CGPoint(
          x: offsetX + CGFloat(match.colStart) * cellWidth,
          y: offsetY + CGFloat(row) * cellHeight
        )
        results.append(
          TerminalHintTarget(
            id: "hint-\(nextID)",
            labelOrigin: origin,
            displayText: match.text,
            matchType: match.type,
            row: row,
            colRange: match.colStart..<match.colEnd
          ))
        nextID += 1
      }
    }
    return results
  }

  // MARK: - Match Finding

  struct Match {
    let text: String
    let type: TerminalMatchType
    let colStart: Int
    let colEnd: Int
    let patternIndex: Int
  }

  static func findMatches(
    in line: String,
    types: Set<TerminalMatchType>
  ) -> [Match] {
    var all: [Match] = []
    let nsLine = line as NSString
    let fullRange = NSRange(location: 0, length: nsLine.length)

    for (patternIndex, type) in TerminalMatchType.allCases.enumerated() {
      guard types.contains(type) else { continue }
      guard let regex = Self.regex(for: type) else { continue }
      let results = regex.matches(in: line, range: fullRange)
      for result in results {
        guard let swiftRange = Range(result.range, in: line) else { continue }
        var text = String(line[swiftRange])

        switch type {
        case .url:
          text = Self.trimTrailingPunctuation(text)
          let trimmedEnd = line.index(swiftRange.lowerBound, offsetBy: text.count)
          let trimmedRange = swiftRange.lowerBound..<trimmedEnd
          let cols = Self.columnRange(of: trimmedRange, in: line)
          all.append(
            Match(
              text: text, type: type, colStart: cols.start, colEnd: cols.end,
              patternIndex: patternIndex))
          continue
        case .ip:
          let octets = text.split(separator: ".")
          let valid = octets.allSatisfy { Int($0).map({ $0 >= 0 && $0 <= 255 }) ?? false }
          if !valid { continue }
        case .path, .hash, .linenum:
          break
        }

        let cols = Self.columnRange(of: swiftRange, in: line)
        all.append(
          Match(
            text: text, type: type, colStart: cols.start, colEnd: cols.end,
            patternIndex: patternIndex))
      }
    }

    return resolveOverlaps(all)
  }

  // MARK: - Regex Patterns

  // swiftlint:disable:next force_try
  private static let urlRegex = try! NSRegularExpression(
    pattern: #"https?://[^\s<>"{}|\\^\x60\[\]]+"#
  )
  // swiftlint:disable:next force_try
  private static let pathRegex = try! NSRegularExpression(
    pattern: #"(?:/[\w.-]+/[\w./-]+|(?:\.\.?)?/[\w./-]+\.\w+)"#
  )
  // swiftlint:disable:next force_try
  private static let hashRegex = try! NSRegularExpression(
    pattern: #"(?<!#)\b[0-9a-f]{7,40}\b"#
  )
  // swiftlint:disable:next force_try
  private static let ipRegex = try! NSRegularExpression(
    pattern: #"\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b"#
  )
  // swiftlint:disable:next force_try
  private static let linenumRegex = try! NSRegularExpression(
    pattern: #"[\w./+-]+:\d+"#
  )

  private static func regex(for type: TerminalMatchType) -> NSRegularExpression? {
    switch type {
    case .url: urlRegex
    case .path: pathRegex
    case .hash: hashRegex
    case .ip: ipRegex
    case .linenum: linenumRegex
    }
  }

  private static func trimTrailingPunctuation(_ text: String) -> String {
    var result = text
    // Strip trailing punctuation, but preserve balanced parentheses.
    // Wikipedia URLs like https://en.wikipedia.org/wiki/Foo_(bar) are common.
    while let last = result.last, ".,;:!?'\">[]\n".contains(last) {
      result.removeLast()
    }
    // Only strip trailing ) if unmatched
    while result.last == ")" {
      let opens = result.filter { $0 == "(" }.count
      let closes = result.filter { $0 == ")" }.count
      if closes > opens {
        result.removeLast()
      } else {
        break
      }
    }
    return result
  }

  // MARK: - Column Helpers

  private static func columnRange(
    of range: Range<String.Index>,
    in line: String
  ) -> (start: Int, end: Int) {
    var col = 0
    var startCol = 0
    for (index, char) in zip(line.indices, line) {
      if index == range.lowerBound { startCol = col }
      if index == range.upperBound { return (startCol, col) }
      col += displayWidth(of: char)
    }
    return (startCol, col)
  }

  private static func displayWidth(of char: Character) -> Int {
    for scalar in char.unicodeScalars {
      let v = scalar.value
      if (0x1100...0x115F).contains(v) || (0x2E80...0x303E).contains(v)
        || (0x3040...0x33BF).contains(v) || (0x3400...0x4DBF).contains(v)
        || (0x4E00...0x9FFF).contains(v) || (0xF900...0xFAFF).contains(v)
        || (0xFE30...0xFE6F).contains(v) || (0xFF01...0xFF60).contains(v)
        || (0xFFE0...0xFFE6).contains(v) || (0x20000...0x2FFFF).contains(v)
        || (0x30000...0x3FFFF).contains(v) || (0x2600...0x27BF).contains(v)
        || (0x1F300...0x1FAFF).contains(v) || (0x1F900...0x1F9FF).contains(v)
      {
        return 2
      }
    }
    return 1
  }

  // MARK: - Overlap Resolution

  private static func resolveOverlaps(_ matches: [Match]) -> [Match] {
    let sorted = matches.sorted {
      if $0.colStart != $1.colStart { return $0.colStart < $1.colStart }
      let len0 = $0.colEnd - $0.colStart
      let len1 = $1.colEnd - $1.colStart
      if len0 != len1 { return len0 > len1 }
      return $0.patternIndex < $1.patternIndex
    }
    var result: [Match] = []
    var lastEnd = -1
    for match in sorted {
      if match.colStart >= lastEnd {  // swiftlint:disable:this for_where
        result.append(match)
        lastEnd = match.colEnd
      }
    }
    return result
  }
}
