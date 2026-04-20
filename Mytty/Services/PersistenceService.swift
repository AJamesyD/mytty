import AppKit
import Foundation

@MainActor
final class PersistenceService {
  private let store: SessionStore
  private var debounceTask: DispatchWorkItem?
  private var observers: [any NSObjectProtocol] = []

  private static let saveURL: URL = {
    let dir = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/mytty", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("sessions.json")
  }()

  init(store: SessionStore) {
    self.store = store
  }

  func save() {
    let state = store.toPersistentState()
    do {
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
      let data = try encoder.encode(state)
      try data.write(to: Self.saveURL, options: .atomic)
    } catch {
      print("[PersistenceService] save failed: \(error)")
    }
  }

  func scheduleSave(delay: TimeInterval) {
    debounceTask?.cancel()
    let task = DispatchWorkItem { [weak self] in
      MainActor.assumeIsolated {
        self?.save()
      }
    }
    debounceTask = task
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: task)
  }

  func restore() {
    guard FileManager.default.fileExists(atPath: Self.saveURL.path) else { return }
    do {
      let data = try Data(contentsOf: Self.saveURL)
      let state = try JSONDecoder().decode(PersistentState.self, from: data)
      guard state.version == PersistentState.currentVersion else {
        print(
          "[PersistenceService] version mismatch: \(state.version) != \(PersistentState.currentVersion)"
        )
        return
      }
      guard !state.sessions.isEmpty else { return }
      store.restore(from: state)
    } catch {
      print("[PersistenceService] restore failed: \(error)")
    }
  }

  func startObserving() {
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.willTerminateNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.debounceTask?.cancel()
          self?.save()
        }
      })
    observers.append(
      NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification,
        object: nil, queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.scheduleSave(delay: 2)
        }
      })
  }
}
