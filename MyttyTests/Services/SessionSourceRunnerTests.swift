import XCTest

@testable import Mytty

final class SessionSourceRunnerTests: XCTestCase {
  private let workDir = URL(fileURLWithPath: "/tmp")

  private func makeSource(
    command: String,
    action: MyttySessionSource.Action = .createSession,
    priority: Int = 5,
    timeoutMs: Int = 2000,
    maxItems: Int = 200
  ) -> MyttySessionSource {
    MyttySessionSource(
      name: "test",
      command: command,
      action: action,
      priority: priority,
      timeoutMs: timeoutMs,
      maxItems: maxItems
    )
  }

  func testJSONArrayOutput() async {
    let json = #"[{"name":"a","path":"/a"},{"name":"b","path":"/b"}]"#
    let source = makeSource(command: "echo '\(json)'")
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].name, "a")
    XCTAssertEqual(items[0].path, "/a")
    XCTAssertEqual(items[1].name, "b")
  }

  func testJSONLinesOutput() async {
    let cmd = #"printf '{"name":"x","path":"/x"}\n{"name":"y","path":"/y"}\n'"#
    let source = makeSource(command: cmd)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].name, "x")
    XCTAssertEqual(items[1].name, "y")
  }

  func testSingleJSONObject() async {
    let cmd = #"echo '{"name":"solo","path":"/solo","subtitle":"sub"}'"#
    let source = makeSource(command: cmd)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].name, "solo")
    XCTAssertEqual(items[0].subtitle, "sub")
  }

  func testPlainTextPaths() async {
    let cmd = #"printf '/usr/local/bin\n/tmp/foo\n'"#
    let source = makeSource(command: cmd)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].name, "bin")
    XCTAssertEqual(items[0].path, "/usr/local/bin")
    XCTAssertEqual(items[1].name, "foo")
  }

  func testPlainTextNonPaths() async {
    let cmd = #"printf 'hello\nworld\n'"#
    let source = makeSource(command: cmd)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(items.count, 2)
    XCTAssertEqual(items[0].name, "hello")
    XCTAssertNil(items[0].path)
    XCTAssertEqual(items[1].name, "world")
  }

  func testTimeout() async {
    let source = makeSource(command: "sleep 5", timeoutMs: 200)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .timeout)
    XCTAssertTrue(items.isEmpty)
  }

  func testMaxItems() async {
    let cmd = #"printf 'a\nb\nc\nd\ne\n'"#
    let source = makeSource(command: cmd, maxItems: 3)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertEqual(items.count, 3)
    XCTAssertEqual(items[0].name, "a")
    XCTAssertEqual(items[2].name, "c")
  }

  func testEmptyOutput() async {
    let source = makeSource(command: "true")
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .ok)
    XCTAssertTrue(items.isEmpty)
  }

  func testNonZeroExitWithOutput() async {
    let cmd = #"printf '{"name":"fail","path":"/fail"}\n'; exit 1"#
    let source = makeSource(command: cmd)
    let (items, status) = await SessionSourceRunner.run(source: source, workingDirectory: workDir)
    XCTAssertEqual(status, .error)
    XCTAssertEqual(items.count, 1)
    XCTAssertEqual(items[0].name, "fail")
  }
}
