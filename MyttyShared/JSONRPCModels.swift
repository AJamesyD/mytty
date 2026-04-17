import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let obj = try? container.decode([String: JSONValue].self) {
      self = .object(obj)
    } else if let arr = try? container.decode([JSONValue].self) {
      self = .array(arr)
    } else if let s = try? container.decode(String.self) {
      self = .string(s)
    } else if let i = try? container.decode(Int.self) {
      self = .int(i)
    } else if let d = try? container.decode(Double.self) {
      self = .double(d)
    } else if let b = try? container.decode(Bool.self) {
      self = .bool(b)
    } else if container.decodeNil() {
      self = .null
    } else {
      throw DecodingError.dataCorruptedError(
        in: container, debugDescription: "Unsupported JSON value")
    }
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let s): try container.encode(s)
    case .int(let i): try container.encode(i)
    case .double(let d): try container.encode(d)
    case .bool(let b): try container.encode(b)
    case .object(let o): try container.encode(o)
    case .array(let a): try container.encode(a)
    case .null: try container.encodeNil()
    }
  }
}

extension JSONValue: ExpressibleByStringLiteral {
  public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
  public init(integerLiteral value: Int) { self = .int(value) }
}

extension JSONValue: ExpressibleByBooleanLiteral {
  public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
  public init(dictionaryLiteral elements: (String, JSONValue)...) {
    self = .object(Dictionary(uniqueKeysWithValues: elements))
  }
}

extension JSONValue: ExpressibleByArrayLiteral {
  public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByNilLiteral {
  public init(nilLiteral: ()) { self = .null }
}

public enum JSONRPCMessage {
  public struct Request: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: JSONValue]?
    public let id: Int

    public init(method: String, params: [String: JSONValue]? = nil, id: Int) {
      self.jsonrpc = "2.0"
      self.method = method
      self.params = params
      self.id = id
    }
  }

  public struct Response: Codable, Sendable {
    public let jsonrpc: String
    public let result: JSONValue?
    public let error: ErrorPayload?
    public let id: Int

    public static func success(id: Int, result: JSONValue) -> Response {
      Response(jsonrpc: "2.0", result: result, error: nil, id: id)
    }

    public static func error(id: Int, code: Int, message: String) -> Response {
      Response(
        jsonrpc: "2.0", result: nil, error: ErrorPayload(code: code, message: message, data: nil),
        id: id)
    }
  }

  public struct Notification: Codable, Sendable {
    public let jsonrpc: String
    public let method: String
    public let params: [String: JSONValue]?

    public init(method: String, params: [String: JSONValue]? = nil) {
      self.jsonrpc = "2.0"
      self.method = method
      self.params = params
    }
  }

  public struct ErrorPayload: Codable, Sendable {
    public let code: Int
    public let message: String
    public let data: JSONValue?
  }
}
