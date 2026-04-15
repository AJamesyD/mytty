import Foundation

@MainActor
final class GitDetectionService {
  static let shared = GitDetectionService()

  private var pendingTasks: [Int: DispatchWorkItem] = [:]

  func detectGitInfo(for pane: MisttyPane) {
    pendingTasks[pane.id]?.cancel()
    let task = DispatchWorkItem { [weak self] in
      self?.run(for: pane)
    }
    pendingTasks[pane.id] = task
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: task)
  }

  private func run(for pane: MisttyPane) {
    guard let dir = pane.workingDirectory else {
      pane.gitBranch = nil
      pane.gitDirty = false
      return
    }
    let dirPath = dir.path
    Task.detached {
      let branch = await self.runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: dirPath)
      let dirty = await self.runGit(["diff", "--quiet"], in: dirPath) == nil
      await MainActor.run {
        pane.gitBranch = branch
        pane.gitDirty = dirty
      }
    }
  }

  private nonisolated func runGit(_ args: [String], in directory: String) async -> String? {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = URL(fileURLWithPath: directory)
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do {
      try process.run()
    } catch {
      return nil
    }
    let timer = DispatchWorkItem { process.terminate() }
    DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: timer)
    process.waitUntilExit()
    timer.cancel()
    guard process.terminationStatus == 0 else { return nil }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
