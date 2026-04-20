import AppKit
import Foundation

struct FrecencyEntry: Codable {
  var frequency: Int
  var lastAccessed: Date
}

@MainActor
final class FrecencyService {
  private var entries: [String: FrecencyEntry] = [:]
  private let storageURL: URL
  private var saveTask: Task<Void, Never>?
  private var terminationObserver: (any NSObjectProtocol)?

  init(storageURL: URL? = nil) {
    self.storageURL = storageURL ?? Self.defaultStorageURL()
    load()
    terminationObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.willTerminateNotification,
      object: nil, queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated { self?.saveImmediately() }
    }
  }

  private static func defaultStorageURL() -> URL {
    guard
      let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory, in: .userDomainMask
      ).first
    else {
      return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("frecency.json")
    }
    let dir = appSupport.appendingPathComponent("com.mytty")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent("frecency.json")
  }

  func score(for key: String) -> Double {
    guard let entry = entries[key] else { return 0 }
    let hoursSinceAccess = -entry.lastAccessed.timeIntervalSinceNow / 3600
    let recencyWeight: Double
    switch hoursSinceAccess {
    case ..<1: recencyWeight = 4.0
    case ..<24: recencyWeight = 2.0
    case ..<168: recencyWeight = 1.0
    default: recencyWeight = 0.5
    }
    return Double(entry.frequency) * recencyWeight
  }

  func recordAccess(for key: String) {
    var entry = entries[key] ?? FrecencyEntry(frequency: 0, lastAccessed: Date())
    entry.frequency += 1
    entry.lastAccessed = Date()
    entries[key] = entry
    scheduleSave()
  }

  func setLastAccessed(for key: String, date: Date) {
    guard var entry = entries[key] else { return }
    entry.lastAccessed = date
    entries[key] = entry
    scheduleSave()
  }

  func saveImmediately() {
    saveTask?.cancel()
    saveTask = nil
    isDirty = false
    save()
  }

  private var isDirty = false

  private func scheduleSave() {
    if saveTask == nil {
      // First mutation since last save: persist immediately
      save()
      isDirty = false
      // Start a cooldown window; subsequent mutations within 5s are coalesced
      saveTask = Task { @MainActor in
        try? await Task.sleep(for: .seconds(5))
        guard !Task.isCancelled else { return }
        if self.isDirty {
          self.save()
          self.isDirty = false
        }
        self.saveTask = nil
      }
    } else {
      // Within cooldown window: mark dirty, will be saved when window expires
      isDirty = true
    }
  }

  private func load() {
    guard let data = try? Data(contentsOf: storageURL),
      let decoded = try? JSONDecoder().decode([String: FrecencyEntry].self, from: data)
    else { return }
    entries = decoded
  }

  private func save() {
    guard let data = try? JSONEncoder().encode(entries) else { return }
    try? data.write(to: storageURL, options: .atomic)
  }
}
