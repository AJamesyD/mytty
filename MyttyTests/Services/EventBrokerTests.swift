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
}
