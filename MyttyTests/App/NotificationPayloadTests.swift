import XCTest

@testable import Mytty

final class NotificationPayloadTests: XCTestCase {
  func test_payload_returnsTypedValue() {
    let notification = Notification(
      name: .ghosttySetTitle, object: nil,
      userInfo: [Notification.payloadKey: SetTitlePayload(paneID: 42, title: "vim")])
    let p = notification.payload(SetTitlePayload.self)
    XCTAssertEqual(p?.paneID, 42)
    XCTAssertEqual(p?.title, "vim")
  }

  func test_payload_wrongType_returnsNil() {
    let notification = Notification(
      name: .ghosttySetTitle, object: nil,
      userInfo: [Notification.payloadKey: PanePayload(paneID: 1)])
    XCTAssertNil(notification.payload(SetTitlePayload.self))
  }

  func test_payload_missingPayload_returnsNil() {
    let notification = Notification(name: .ghosttySetTitle, object: nil, userInfo: nil)
    XCTAssertNil(notification.payload(SetTitlePayload.self))
  }

  func test_payload_emptyUserInfo_returnsNil() {
    let notification = Notification(name: .ghosttySetTitle, object: nil, userInfo: [:])
    XCTAssertNil(notification.payload(SetTitlePayload.self))
  }

  func test_payload_nilPaneID() {
    let notification = Notification(
      name: .ghosttyRingBell, object: nil,
      userInfo: [Notification.payloadKey: PanePayload(paneID: nil)])
    let p = notification.payload(PanePayload.self)
    XCTAssertNotNil(p)
    XCTAssertNil(p?.paneID)
  }
}
