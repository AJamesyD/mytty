import Foundation

private actor Cache {
  var environment: [String: String]?

  func get() -> [String: String]? { environment }
  func set(_ env: [String: String]) { environment = env }
}

enum ShellEnvironment: Sendable {
  private static let cache = Cache()

  static func resolvedEnvironment() async -> [String: String] {
    if let cached = await cache.get() {
      return cached
    }
    let env = await resolve()
    await cache.set(env)
    return env
  }

  private static func resolve() async -> [String: String] {
    let fallback = ProcessInfo.processInfo.environment
    let shell = fallback["SHELL"] ?? "/bin/zsh"

    let process = Process()
    process.executableURL = URL(fileURLWithPath: shell)
    process.arguments = ["-l", "-c", "env -0"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()

    do {
      try process.run()
    } catch {
      return fallback
    }

    let exited = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        process.waitUntilExit()
        return true
      }
      group.addTask {
        try? await Task.sleep(nanoseconds: 10_000_000_000)
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      if !first && process.isRunning {
        process.terminate()
      }
      return first
    }

    guard exited, process.terminationStatus == 0 else {
      return fallback
    }

    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    guard let output = String(data: data, encoding: .utf8), !output.isEmpty else {
      return fallback
    }

    var result: [String: String] = [:]
    for entry in output.split(separator: "\0", omittingEmptySubsequences: true) {
      let pair = entry.split(separator: "=", maxSplits: 1)
      if pair.count == 2 {
        result[String(pair[0])] = String(pair[1])
      }
    }
    return result.isEmpty ? fallback : result
  }
}
