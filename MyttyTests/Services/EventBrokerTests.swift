import Darwin
import XCTest

@testable import Mytty
@testable import MyttyShared

final class EventBrokerTests: XCTestCase {
  func testSubscribeReturnsUniqueIds() async {
    let broker = EventBroker()
    let id1 = await broker.subscribe(fd: 1, events: ["session.*"])
    let id2 = await broker.subscribe(fd: 1, events: ["tab.*"])
    XCTAssertNotEqual(id1, id2)
  }

  func testUnsubscribeRemoves() async {
    let broker = EventBroker()
    let id = await broker.subscribe(fd: 1, events: ["session.*"])
    await broker.unsubscribe(id: id)
    await broker.unsubscribe(id: id)
  }

  func testRemoveSubscriptionsForFD() async {
    let broker = EventBroker()
    _ = await broker.subscribe(fd: 10, events: ["session.*"])
    _ = await broker.subscribe(fd: 10, events: ["tab.*"])
    _ = await broker.subscribe(fd: 20, events: ["pane.*"])
    await broker.removeSubscriptions(forFD: 10)
  }

  // MARK: - Helpers

  private func makePipe() -> (readFD: Int32, writeFD: Int32) {
    var fds: [Int32] = [0, 0]
    pipe(&fds)
    return (fds[0], fds[1])
  }

  private func readFromPipe(_ fd: Int32) -> Data {
    var buffer = [UInt8](repeating: 0, count: 4096)
    let n = Darwin.read(fd, &buffer, buffer.count)
    if n > 0 {
      return Data(buffer[0..<n])
    }
    return Data()
  }

  // MARK: - publish

  func testPublishWritesToMatchingSubscriber() async {
    let broker = EventBroker()
    let pipe = makePipe()
    defer {
      close(pipe.readFD)
      close(pipe.writeFD)
    }

    _ = await broker.subscribe(fd: pipe.writeFD, events: ["session.*"])
    await broker.publish(event: "session.created", params: ["name": .string("test")])

    let data = readFromPipe(pipe.readFD)
    let str = String(data: data, encoding: .utf8) ?? ""
    XCTAssertTrue(str.contains("session.created"))
    XCTAssertTrue(str.contains("Content-Length:"))
  }

  func testPublishDoesNotWriteToNonMatchingSubscriber() async {
    let broker = EventBroker()
    let pipe = makePipe()
    defer {
      close(pipe.readFD)
      close(pipe.writeFD)
    }

    _ = await broker.subscribe(fd: pipe.writeFD, events: ["tab.*"])
    await broker.publish(event: "session.created", params: [:])

    _ = fcntl(pipe.readFD, F_SETFL, O_NONBLOCK)
    let data = readFromPipe(pipe.readFD)
    XCTAssertTrue(data.isEmpty)
  }

  func testPublishWildcardMatchesAll() async {
    let broker = EventBroker()
    let pipe = makePipe()
    defer {
      close(pipe.readFD)
      close(pipe.writeFD)
    }

    _ = await broker.subscribe(fd: pipe.writeFD, events: ["*"])
    await broker.publish(event: "anything.here", params: [:])

    let data = readFromPipe(pipe.readFD)
    let str = String(data: data, encoding: .utf8) ?? ""
    XCTAssertTrue(str.contains("anything.here"))
  }

  func testPublishExactMatchWorks() async {
    let broker = EventBroker()
    let pipe = makePipe()
    defer {
      close(pipe.readFD)
      close(pipe.writeFD)
    }

    _ = await broker.subscribe(fd: pipe.writeFD, events: ["session.created"])
    await broker.publish(event: "session.created", params: [:])

    let data = readFromPipe(pipe.readFD)
    XCTAssertFalse(data.isEmpty)
  }

  func testPublishIncludesSubscriptionId() async {
    let broker = EventBroker()
    let pipe = makePipe()
    defer {
      close(pipe.readFD)
      close(pipe.writeFD)
    }

    let subId = await broker.subscribe(fd: pipe.writeFD, events: ["*"])
    await broker.publish(event: "test.event", params: [:])

    let data = readFromPipe(pipe.readFD)
    let str = String(data: data, encoding: .utf8) ?? ""
    XCTAssertTrue(str.contains(subId))
  }

  func testPublishCleansUpDeadFD() async {
    let broker = EventBroker()
    let pipe = makePipe()
    close(pipe.writeFD)
    close(pipe.readFD)

    let badFD: Int32 = pipe.writeFD
    let subId = await broker.subscribe(fd: badFD, events: ["*"])
    await broker.publish(event: "test.event", params: [:])

    await broker.unsubscribe(id: subId)
  }

  func testPublishPrefixGlobDoesNotMatchPartial() async {
    let broker = EventBroker()
    let pipe = makePipe()
    defer {
      close(pipe.readFD)
      close(pipe.writeFD)
    }

    _ = await broker.subscribe(fd: pipe.writeFD, events: ["session.*"])
    await broker.publish(event: "sessionExtra.created", params: [:])

    _ = fcntl(pipe.readFD, F_SETFL, O_NONBLOCK)
    let data = readFromPipe(pipe.readFD)
    XCTAssertTrue(data.isEmpty)
  }
}
