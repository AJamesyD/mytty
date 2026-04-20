import XCTest

final class IPCNamingConventionTests: XCTestCase {
  func testAllMethodNamesFollowNounVerbConvention() throws {
    let url = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Mytty/Services/IPCListener.swift")
    let source = try String(contentsOf: url, encoding: .utf8)

    let regex = try NSRegularExpression(pattern: #"case "([^"]+)":"#)
    let matches = regex.matches(in: source, range: NSRange(source.startIndex..., in: source))

    let methods = matches.compactMap { match -> String? in
      guard let range = Range(match.range(at: 1), in: source) else { return nil }
      return String(source[range])
    }

    let systemMethods: Set<String> = ["initialize", "subscribe", "unsubscribe"]
    let conventionPattern = try NSRegularExpression(pattern: #"^[a-z]+\.[a-z]+(-[a-z]+)*$"#)

    let domainMethods = methods.filter { !systemMethods.contains($0) }
    XCTAssertGreaterThan(domainMethods.count, 30, "Expected 30+ IPC methods")

    for method in domainMethods {
      let range = NSRange(method.startIndex..., in: method)
      XCTAssertNotNil(
        conventionPattern.firstMatch(in: method, range: range),
        "Method '\(method)' does not match noun.verb convention (expected: noun.verb or noun.verb-word)"
      )
    }
  }
}
