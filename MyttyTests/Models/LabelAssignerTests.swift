import XCTest

@testable import Mytty

@MainActor
final class LabelAssignerTests: XCTestCase {

  private func makeTargets(count: Int) -> [any HintTarget] {
    (0..<count).map { i in
      TerminalHintTarget(
        id: "t\(i)",
        labelOrigin: .zero,
        displayText: "target-\(i)",
        matchType: .url,
        row: 0,
        colRange: i..<(i + 1)
      )
    }
  }

  func test_emptyTargets_returnsEmpty() {
    let result = LabelAssigner.assignLabels(targets: [], alphabet: "asdf")
    XCTAssertTrue(result.isEmpty)
  }

  func test_emptyAlphabet_returnsEmpty() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 3), alphabet: "")
    XCTAssertTrue(result.isEmpty)
  }

  func test_singleTarget_singleCharLabel() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 1), alphabet: "asdf")
    XCTAssertEqual(result.count, 1)
    XCTAssertEqual(result[0].label, "a")
  }

  func test_targetsEqualAlphabet_allSingleChar() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 3), alphabet: "asd")
    XCTAssertEqual(result.map(\.label), ["a", "s", "d"])
  }

  func test_targetsExceedAlphabet_allTwoChar() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 4), alphabet: "ab")
    XCTAssertEqual(result.map(\.label), ["aa", "ab", "ba", "bb"])
  }

  func test_targetsExceedAlphabetSquared_truncated() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 5), alphabet: "ab")
    XCTAssertEqual(result.count, 4)
  }

  func test_defaultAlphabet_nineTargets_singleChar() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 9), alphabet: "asdfghjkl")
    XCTAssertEqual(result.count, 9)
    for label in result {
      XCTAssertEqual(label.label.count, 1)
    }
  }

  func test_defaultAlphabet_tenTargets_allTwoChar() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 10), alphabet: "asdfghjkl")
    XCTAssertEqual(result.count, 10)
    for label in result {
      XCTAssertEqual(label.label.count, 2)
    }
    XCTAssertEqual(result[0].label, "aa")
  }

  func test_labelOrder_matchesTargetOrder() {
    let targets = makeTargets(count: 3)
    let result = LabelAssigner.assignLabels(targets: targets, alphabet: "xyz")
    for (i, label) in result.enumerated() {
      XCTAssertEqual(label.target.id, "t\(i)")
    }
  }

  func test_twoCharLabels_firstCharPartitions() {
    let result = LabelAssigner.assignLabels(targets: makeTargets(count: 4), alphabet: "ab")
    let aLabels = result.filter { $0.label.hasPrefix("a") }.map(\.label)
    let bLabels = result.filter { $0.label.hasPrefix("b") }.map(\.label)
    XCTAssertEqual(aLabels, ["aa", "ab"])
    XCTAssertEqual(bLabels, ["ba", "bb"])
  }

  func test_duplicateAlphabet_deduplicates() {
    let targets = makeTargets(count: 3)
    let labels = LabelAssigner.assignLabels(targets: targets, alphabet: "aab")
    XCTAssertEqual(labels.count, 3)
    XCTAssertEqual(labels[0].label, "aa")
    XCTAssertEqual(labels[1].label, "ab")
    XCTAssertEqual(labels[2].label, "ba")
  }

  func test_singleCharAlphabet_returnsEmpty() {
    let targets = makeTargets(count: 3)
    let labels = LabelAssigner.assignLabels(targets: targets, alphabet: "a")
    XCTAssertTrue(labels.isEmpty)
  }
}
