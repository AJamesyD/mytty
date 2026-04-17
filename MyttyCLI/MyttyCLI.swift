import ArgumentParser
import Foundation
import MyttyShared

@main
struct MyttyCLI: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "mytty-cli",
    abstract: "Control Mytty terminal emulator",
    subcommands: [
      SessionCommand.self,
      TabCommand.self,
      PaneCommand.self,
      WindowCommand.self,
      PopupCommand.self,
    ]
  )
}
