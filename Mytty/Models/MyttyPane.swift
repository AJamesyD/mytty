import AppKit
import Foundation

@Observable
@MainActor
final class MyttyPane: Identifiable {
  let id: Int
  var directory: URL?
  var command: String?
  /// When true, run the command in the shell without `exec` (shell stays alive after the command exits).
  /// When false, prefix the command with `exec` so the shell exits when the command finishes.
  var useCommandField: Bool = true
  @ObservationIgnored weak var tab: MyttyTab?
  @ObservationIgnored weak var session: MyttySession?

  var sessionID: Int { session?.id ?? tab?.session?.id ?? 0 }
  var sessionName: String { session?.name ?? tab?.session?.name ?? "" }
  var tabID: Int { tab?.id ?? -1 }

  var processTitle: String?
  var workingDirectory: URL?
  var lastCommandResult: CommandResult?
  var progressState: ProgressState?
  var vars: [String: String] = [:]
  var activeKeyTables: [String] = []
  var hoverUrl: String?

  @ObservationIgnored
  var progressExpiryTask: DispatchWorkItem?

  struct CommandResult {
    let exitCode: Int16
    let duration: UInt64

    var formattedDuration: String? {
      let seconds = duration / 1_000_000_000
      if seconds < 1 { return nil }
      if seconds < 60 { return "\(seconds)s" }
      let minutes = seconds / 60
      let remainingSeconds = seconds % 60
      if minutes < 60 {
        return remainingSeconds > 0 ? "\(minutes)m \(remainingSeconds)s" : "\(minutes)m"
      }
      let hours = minutes / 60
      let remainingMinutes = minutes % 60
      return remainingMinutes > 0 ? "\(hours)h \(remainingMinutes)m" : "\(hours)h"
    }
  }

  enum ProgressState {
    case set(progress: Int8)
    case error
    case indeterminate
    case pause
  }

  var isPassthroughProcess: Bool {
    isPassthroughProcess(processes: KeybindingStore.defaultPassthroughProcesses)
  }

  func isPassthroughProcess(processes: [String]) -> Bool {
    guard let title = processTitle?.lowercased() else { return false }
    return processes.contains(where: { title == $0 || title.hasPrefix($0 + " ") })
  }

  init(id: Int) {
    self.id = id
  }

  static func buildInitialInput(command: String?, useCommandField: Bool) -> String? {
    guard let command, !command.isEmpty else { return nil }
    return useCommandField ? command : "exec \(command)"
  }

  /// The persistent terminal surface view for this pane.
  /// Created lazily on first access so the ghostty surface lives
  /// for the lifetime of the pane, surviving SwiftUI view rebuilds.
  @ObservationIgnored
  lazy var surfaceView: TerminalSurfaceView = {
    let view = TerminalSurfaceView(
      frame: .zero,
      workingDirectory: directory,
      initialInput: Self.buildInitialInput(command: command, useCommandField: useCommandField),
      sessionID: sessionID,
      sessionName: sessionName,
      tabID: tabID,
      paneID: id
    )
    view.pane = self
    return view
  }()
}
