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

    do {
      try process.run()
    } catch {
      return ([], .error)
    }

    let maxBytes = 1_048_576
    let pid = process.processIdentifier
    let readHandle = pipe.fileHandleForReading

    return await withTaskCancellationHandler {
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

      let timedOut = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
          await Task.detached { process.waitUntilExit() }.value
          return false
        }
        group.addTask {
          try? await Task.sleep(for: .milliseconds(source.timeoutMs))
          guard !Task.isCancelled, process.isRunning else { return false }
          process.terminate()
          DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(500)) {
            if process.isRunning { kill(pid, SIGKILL) }
          }
          return true
        }
        let result = await group.next() ?? false
        group.cancelAll()
        return result
      }

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
