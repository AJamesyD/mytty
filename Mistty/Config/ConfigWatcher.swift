import Foundation

@MainActor
final class ConfigWatcher {
  nonisolated(unsafe) private var source: DispatchSourceFileSystemObject?
  nonisolated(unsafe) private var fileDescriptor: Int32 = -1

  func start() {
    stop()
    let path = MisttyConfig.configFileURL.path
    fileDescriptor = open(path, O_EVTONLY)
    guard fileDescriptor >= 0 else { return }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fileDescriptor,
      eventMask: [.write, .rename, .delete],
      queue: .main
    )
    source.setEventHandler { [weak self] in
      self?.handleChange()
    }
    source.setCancelHandler {}
    source.resume()
    self.source = source
  }

  func stop() {
    source?.cancel()
    source = nil
    if fileDescriptor >= 0 {
      close(fileDescriptor)
      fileDescriptor = -1
    }
  }

  private func handleChange() {
    let flags = source?.data ?? []
    if flags.contains(.rename) || flags.contains(.delete) {
      stop()
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
        self?.start()
        NotificationCenter.default.post(name: .configDidChange, object: nil)
      }
      return
    }
    NotificationCenter.default.post(name: .configDidChange, object: nil)
  }

  deinit {
    source?.cancel()
    source = nil
    if fileDescriptor >= 0 {
      close(fileDescriptor)
      fileDescriptor = -1
    }
  }
}

extension Notification.Name {
  static let configDidChange = Notification.Name("configDidChange")
}
