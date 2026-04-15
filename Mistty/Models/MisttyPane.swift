import AppKit
import Foundation

@Observable
@MainActor
final class MisttyPane: Identifiable {
  let id: Int
  var directory: URL?
  var command: String?
  /// When true, use ghostty's command field (which forces wait-after-command).
  /// When false, send the command as initial input so the shell exits naturally.
  var useCommandField: Bool = true

  var processTitle: String?
  var workingDirectory: URL?
  var lastCommandResult: CommandResult?
  var progressState: ProgressState?

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

  var isRunningVimLike: Bool {
    guard let title = processTitle?.lowercased() else { return false }
    let vimNames = ["nvim", "neovim", "vim"]
    return vimNames.contains(where: { title == $0 || title.hasPrefix($0 + " ") })
  }

  init(id: Int) {
    self.id = id
  }

  /// The persistent terminal surface view for this pane.
  /// Created lazily on first access so the ghostty surface lives
  /// for the lifetime of the pane, surviving SwiftUI view rebuilds.
  @ObservationIgnored
  lazy var surfaceView: TerminalSurfaceView = {
    let view = TerminalSurfaceView(
      frame: .zero,
      workingDirectory: directory,
      command: useCommandField ? command : nil,
      initialInput: useCommandField ? nil : command
    )
    view.pane = self
    return view
  }()
}
