import XCTest

@testable import Mytty

@MainActor
final class TerminalHintTargetProviderTests: XCTestCase {

  private let defaultGeometry = HintsGeometry.terminal(
    rows: 1, cols: 80, cellWidth: 8, cellHeight: 16, offsetX: 0, offsetY: 0
  )

  private func provider(
    lines: [String],
    types: Set<TerminalMatchType> = Set(TerminalMatchType.allCases)
  ) -> TerminalHintTargetProvider {
    TerminalHintTargetProvider(
      lineReader: { row in row < lines.count ? lines[row] : nil },
      enabledTypes: types
    )
  }

  // MARK: - Pattern Tests (findMatches)

  func test_urlMatch() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "visit https://example.com today",
      types: Set(TerminalMatchType.allCases)
    )
    let urls = matches.filter { $0.type == .url }
    XCTAssertEqual(urls.count, 1)
    XCTAssertEqual(urls[0].text, "https://example.com")
  }

  func test_urlTrimsTrailingPunctuation() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "see https://example.com.",
      types: [.url]
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].text, "https://example.com")
  }

  func test_pathMatch_absolute() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "check /usr/local/bin",
      types: [.path]
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].type, .path)
  }

  func test_pathMatch_relative() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "edit ./src/main.swift",
      types: [.path]
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].type, .path)
  }

  func test_hashMatch() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "commit abc1234 merged",
      types: [.hash]
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].type, .hash)
    XCTAssertEqual(matches[0].text, "abc1234")
  }

  func test_hashExcludesCSSColor() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "color: #aabbccdd;",
      types: [.hash]
    )
    XCTAssertEqual(matches.count, 0)
  }

  func test_ipMatch() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "host 192.168.1.1 up",
      types: [.ip]
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].type, .ip)
    XCTAssertEqual(matches[0].text, "192.168.1.1")
  }

  func test_ipRejectsInvalidOctets() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "bad 999.999.999.999 addr",
      types: [.ip]
    )
    XCTAssertEqual(matches.count, 0)
  }

  func test_linenumMatch() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "error at foo.swift:42",
      types: [.linenum]
    )
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].type, .linenum)
    XCTAssertEqual(matches[0].text, "foo.swift:42")
  }

  // MARK: - Integration Tests (targets)

  func test_overlapResolution_longerWins() {
    let p = provider(lines: ["open https://example.com/path/to/file"])
    let targets = p.targets(in: defaultGeometry)
    let types = targets.compactMap { ($0 as? TerminalHintTarget)?.matchType }
    XCTAssertEqual(types, [.url])
  }

  func test_multipleMatchesOnOneLine() {
    let p = provider(lines: ["https://a.com and https://b.com"])
    let targets = p.targets(in: defaultGeometry)
    XCTAssertEqual(targets.count, 2)
    let cols = targets.compactMap { ($0 as? TerminalHintTarget)?.colRange.lowerBound }
    XCTAssertEqual(cols, cols.sorted())
  }

  func test_disabledType_excluded() {
    let allExceptURL = Set(TerminalMatchType.allCases).subtracting([.url])
    let p = provider(lines: ["visit https://example.com"], types: allExceptURL)
    let targets = p.targets(in: defaultGeometry)
    let urlTargets = targets.compactMap { ($0 as? TerminalHintTarget) }.filter {
      $0.matchType == .url
    }
    XCTAssertEqual(urlTargets.count, 0)
  }

  func test_emptyLine_noMatches() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "", types: Set(TerminalMatchType.allCases))
    XCTAssertTrue(matches.isEmpty)
  }

  func test_noMatchesInLine() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "just some plain text", types: Set(TerminalMatchType.allCases))
    XCTAssertTrue(matches.isEmpty)
  }

  func test_wideCharacters_offsetColumns() {
    let line = "\u{65E5}\u{672C} https://a.com"
    let matches = TerminalHintTargetProvider.findMatches(in: line, types: [.url])
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].colStart, 5)
  }

  func test_urlPreservesBalancedParens() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "https://en.wikipedia.org/wiki/Foo_(bar)", types: [.url])
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].text, "https://en.wikipedia.org/wiki/Foo_(bar)")
  }

  func test_urlTrimsUnmatchedClosingParen() {
    let matches = TerminalHintTargetProvider.findMatches(
      in: "(https://example.com)", types: [.url])
    XCTAssertEqual(matches.count, 1)
    XCTAssertEqual(matches[0].text, "https://example.com")
  }
}
