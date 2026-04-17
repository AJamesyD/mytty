import Darwin
import Foundation
import MyttyShared

actor EventBroker {
  struct Subscription: Sendable {
    let id: String
    let fd: Int32
    let patterns: [String]
  }

  private var subscriptions: [String: Subscription] = [:]

  func subscribe(fd: Int32, events: [String]) -> String {
    let id = UUID().uuidString
    subscriptions[id] = Subscription(id: id, fd: fd, patterns: events)
    return id
  }

  func unsubscribe(id: String) {
    subscriptions.removeValue(forKey: id)
  }

  func removeSubscriptions(forFD fd: Int32) {
    subscriptions = subscriptions.filter { $0.value.fd != fd }
  }

  func publish(event: String, params: [String: JSONValue]) {
    var deadSubscriptions: [String] = []

    for (id, sub) in subscriptions {
      guard matches(event: event, patterns: sub.patterns) else { continue }

      var merged = params
      merged["subscriptionId"] = .string(id)

      let notification = JSONRPCMessage.Notification(method: event, params: merged)
      guard let data = try? JSONEncoder().encode(notification) else { continue }

      if !writeNotification(fd: sub.fd, data: data) {
        deadSubscriptions.append(id)
      }
    }

    for id in deadSubscriptions {
      subscriptions.removeValue(forKey: id)
    }
  }

  private func matches(event: String, patterns: [String]) -> Bool {
    for pattern in patterns {
      if pattern == "*" || pattern == event { return true }
      if pattern.hasSuffix(".*") {
        let prefix = String(pattern.dropLast(2))
        if event.hasPrefix(prefix + ".") { return true }
      }
    }
    return false
  }

  private func writeNotification(fd: Int32, data: Data) -> Bool {
    let header = "Content-Length: \(data.count)\r\n\r\n"
    let headerData = Data(header.utf8)
    return writeAll(fd: fd, data: headerData) && writeAll(fd: fd, data: data)
  }

  private func writeAll(fd: Int32, data: Data) -> Bool {
    var offset = 0
    while offset < data.count {
      let n = data.withUnsafeBytes { ptr in
        Darwin.write(fd, ptr.baseAddress! + offset, data.count - offset)
      }
      if n < 0 && errno == EINTR { continue }
      if n <= 0 { return false }
      offset += n
    }
    return true
  }
}
