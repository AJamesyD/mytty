import Foundation

@MainActor
final class GhosttyConfigWatcher {
  private struct WatchedFile {
    nonisolated(unsafe) var source: DispatchSourceFileSystemObject?
    nonisolated(unsafe) var fileDescriptor: Int32 = -1
    let path: String
  }

  private var watched: [WatchedFile] = []

  private static let paths: [String] = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return [
      home.appendingPathComponent(".config/ghostty/config").path,
      home.appendingPathComponent(".config/mytty/ghostty.conf").path,
    ]
  }()

  func start() {
    stop()
    watched = Self.paths.map { path in
      var w = WatchedFile(path: path)
      startWatching(&w)
      return w
    }
  }

  func stop() {
    for i in watched.indices {
      stopWatching(&watched[i])
    }
    watched = []
  }

  private func startWatching(_ w: inout WatchedFile) {
    guard FileManager.default.fileExists(atPath: w.path) else { return }
    w.fileDescriptor = open(w.path, O_EVTONLY)
    guard w.fileDescriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: w.fileDescriptor,
      eventMask: [.write, .rename, .delete],
      queue: .main
    )
    let path = w.path
    source.setEventHandler { [weak self] in
      self?.handleChange(path: path)
    }
    source.setCancelHandler {}
    source.resume()
    w.source = source
  }

  private func stopWatching(_ w: inout WatchedFile) {
    w.source?.cancel()
    w.source = nil
    if w.fileDescriptor >= 0 {
      close(w.fileDescriptor)
      w.fileDescriptor = -1
    }
  }

  private func handleChange(path: String) {
    guard let idx = watched.firstIndex(where: { $0.path == path }) else { return }
    let flags = watched[idx].source?.data ?? []
    if flags.contains(.rename) || flags.contains(.delete) {
      stopWatching(&watched[idx])
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        guard let self, idx < self.watched.count else { return }
        self.startWatching(&self.watched[idx])
        GhosttyAppManager.shared.reloadGhosttyConfig()
      }
      return
    }
    GhosttyAppManager.shared.reloadGhosttyConfig()
  }

  deinit {
    for var w in watched {
      w.source?.cancel()
      w.source = nil
      if w.fileDescriptor >= 0 {
        close(w.fileDescriptor)
        w.fileDescriptor = -1
      }
    }
  }
}
