import Foundation

public enum MyttyIPC {
  public static let serviceName = "com.mytty.cli-service"
  public static let errorDomain = "com.mytty.error"
  public static let protocolVersion = "1.0"

  public static var socketPath: String {
    guard let appSupport = FileManager.default.urls(
      for: .applicationSupportDirectory, in: .userDomainMask
    ).first else {
      return "/tmp/mytty.sock"
    }
    return appSupport.appendingPathComponent("Mytty/mytty.sock").path
  }

  // 16 MB
  public static let maxMessageSize: UInt32 = 16 * 1024 * 1024

  public enum ErrorCode: Int {
    case entityNotFound = 1
    case invalidArgument = 2
    case operationFailed = 3
    case notSupported = 4
  }

  public static func error(_ code: ErrorCode, _ message: String) -> NSError {
    NSError(
      domain: errorDomain,
      code: code.rawValue,
      userInfo: [NSLocalizedDescriptionKey: message]
    )
  }

  public enum JSONRPCErrorCode {
    public static let parseError = -32700
    public static let invalidRequest = -32600
    public static let methodNotFound = -32601
    public static let invalidParams = -32602

    public static let entityNotFound = 1001
    public static let invalidArgument = 1002
    public static let operationFailed = 1003
    public static let notSupported = 1004
  }
}
