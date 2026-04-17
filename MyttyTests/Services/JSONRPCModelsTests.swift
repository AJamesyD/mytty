import XCTest

@testable import MyttyShared

final class JSONRPCModelsTests: XCTestCase {
  func testJSONValueStringRoundTrip() throws {
    let value: JSONValue = .string("hello")
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }

  func testJSONValueIntRoundTrip() throws {
    let value: JSONValue = .int(42)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }

  func testJSONValueBoolRoundTrip() throws {
    let value: JSONValue = .bool(true)
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }

  func testJSONValueNullRoundTrip() throws {
    let value: JSONValue = .null
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }

  func testJSONValueObjectRoundTrip() throws {
    let value: JSONValue = .object(["name": .string("test"), "count": .int(3)])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }

  func testJSONValueArrayRoundTrip() throws {
    let value: JSONValue = .array([.string("a"), .int(1), .bool(false)])
    let data = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
    XCTAssertEqual(decoded, value)
  }

  func testJSONRPCRequestEncoding() throws {
    let request = JSONRPCMessage.Request(method: "session.list", params: nil, id: 1)
    let data = try JSONEncoder().encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(json?["jsonrpc"] as? String, "2.0")
    XCTAssertEqual(json?["method"] as? String, "session.list")
    XCTAssertEqual(json?["id"] as? Int, 1)
  }

  func testJSONRPCResponseSuccess() throws {
    let response = JSONRPCMessage.Response.success(id: 1, result: .string("ok"))
    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(JSONRPCMessage.Response.self, from: data)
    XCTAssertEqual(decoded.id, 1)
    XCTAssertEqual(decoded.result, .string("ok"))
    XCTAssertNil(decoded.error)
  }

  func testJSONRPCResponseError() throws {
    let response = JSONRPCMessage.Response.error(id: 2, code: 1001, message: "Not found")
    let data = try JSONEncoder().encode(response)
    let decoded = try JSONDecoder().decode(JSONRPCMessage.Response.self, from: data)
    XCTAssertEqual(decoded.id, 2)
    XCTAssertNil(decoded.result)
    XCTAssertEqual(decoded.error?.code, 1001)
    XCTAssertEqual(decoded.error?.message, "Not found")
  }

  func testJSONValueExpressibleByLiterals() throws {
    let str: JSONValue = "hello"
    XCTAssertEqual(str, .string("hello"))

    let num: JSONValue = 42
    XCTAssertEqual(num, .int(42))

    let bool: JSONValue = true
    XCTAssertEqual(bool, .bool(true))

    let null: JSONValue = nil
    XCTAssertEqual(null, .null)
  }
}
