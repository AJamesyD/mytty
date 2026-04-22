import Foundation

enum SessionSourceRunner {
  static func run(
    source: MyttySessionSource,
    workingDirectory: URL,
    environment: [String: String] = [:]
  ) async -> (items: [MyttySessionSourceItem], status: MyttySessionSource.Status) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", source.command]
    process.currentDirectoryURL = workingDirectory

    var env = ProcessInfo.processInfo.environment
    for (key, value) in environment { env[key] = value }
    process.environment = env

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice

    // Set terminationHandler BEFORE run() to avoid the race where the
    // process exits before the handler is attached.
    let once = OnceResume()
    process.terminationHandler = { _ in
      once.resume(returning: false)
    }

    do {
      try process.run()
    } catch {
      return ([], .error)
    }

    let maxBytes = 1_048_576
    let pid = process.processIdentifier
    let readHandle = pipe.fileHandleForReading

    return await withTaskCancellationHandler {
      // Read stdout on a detached task to avoid blocking the cooperative pool
      let readTask = Task.detached { () -> Data in
        var buffer = Data()
        while true {
          let chunk = readHandle.availableData
          if chunk.isEmpty { break }
          buffer.append(chunk)
          if buffer.count >= maxBytes {
            return Data(buffer.prefix(maxBytes))
          }
        }
        return buffer
      }

      // Schedule timeout
      let timeoutWork = DispatchWorkItem {
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
          if process.isRunning { kill(pid, SIGKILL) }
        }
        once.resume(returning: true)
      }
      DispatchQueue.global().asyncAfter(
        deadline: .now() + .milliseconds(source.timeoutMs), execute: timeoutWork)

      // Wait for process exit (or timeout)
      let timedOut = await once.wait()
      timeoutWork.cancel()

      // Close the read end to unblock the reader if the process was killed
      try? readHandle.close()

      let stdoutData = await readTask.value
      let items = parseOutput(stdoutData, maxItems: source.maxItems)

      if timedOut {
        return (items, .timeout)
      }
      if stdoutData.count >= maxBytes {
        return (items, .error)
      }
      return (items, process.terminationStatus == 0 ? .ok : .error)
    } onCancel: {
      process.terminate()
      // Close the read end to unblock the reader
      try? readHandle.close()
      DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
        if process.isRunning { kill(pid, SIGKILL) }
      }
    }
  }

  // MARK: - Output parsing

  private static func parseOutput(_ data: Data, maxItems: Int) -> [MyttySessionSourceItem] {
    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else { return [] }

    if let items = try? JSONDecoder().decode([JSONItem].self, from: data) {
      return Array(items.prefix(maxItems).map { $0.toItem() })
    }

    let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }

    let jsonLineItems = lines.compactMap { line -> MyttySessionSourceItem? in
      guard let lineData = line.data(using: .utf8),
        let item = try? JSONDecoder().decode(JSONItem.self, from: lineData)
      else { return nil }
      return item.toItem()
    }
    if !jsonLineItems.isEmpty {
      return Array(jsonLineItems.prefix(maxItems))
    }

    if let item = try? JSONDecoder().decode(JSONItem.self, from: data) {
      return [item.toItem()]
    }

    return Array(
      lines.prefix(maxItems).map { line -> MyttySessionSourceItem in
        if line.hasPrefix("/") || line.hasPrefix("~") {
          let url = URL(fileURLWithPath: line)
          return MyttySessionSourceItem(
            name: url.lastPathComponent, path: line, subtitle: nil, dedupKey: line)
        }
        return MyttySessionSourceItem(name: line, path: nil, subtitle: nil, dedupKey: line)
      })
  }

  private struct JSONItem: Decodable {
    let name: String
    let path: String?
    let subtitle: String?
    let dedupKey: String?

    enum CodingKeys: String, CodingKey {
      case name, path, subtitle
      case dedupKey = "dedup_key"
    }

    func toItem() -> MyttySessionSourceItem {
      MyttySessionSourceItem(
        name: name,
        path: path,
        subtitle: subtitle,
        dedupKey: dedupKey ?? path ?? name
      )
    }
  }
}

// Ensures a continuation is resumed exactly once from multiple call sites.
// Handles the case where resume() is called before wait().
private final class OnceResume: @unchecked Sendable {
  private var continuation: CheckedContinuation<Bool, Never>?
  private var result: Bool?
  private let lock = NSLock()

  func resume(returning value: Bool) {
    lock.lock()
    guard result == nil else {
      lock.unlock()
      return
    }
    result = value
    let cont = continuation
    continuation = nil
    lock.unlock()
    cont?.resume(returning: value)
  }

  func wait() async -> Bool {
    await withCheckedContinuation { cont in
      lock.lock()
      if let value = result {
        lock.unlock()
        cont.resume(returning: value)
        return
      }
      continuation = cont
      lock.unlock()
    }
  }
}
