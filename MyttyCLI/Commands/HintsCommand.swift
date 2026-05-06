import ArgumentParser
import Foundation
import MyttyShared

struct HintsCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "hints",
    abstract: "Control hints mode",
    subcommands: [Activate.self, Chrome.self]
  )

  struct Activate: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Activate terminal hints mode")

    func run() throws {
      let client = IPCClient()
      try client.connect()
      try client.initialize()
      do {
        _ = try client.callJSONRPC("hints.activate")
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }
    }
  }

  struct Chrome: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Activate chrome hints mode")

    func run() throws {
      let client = IPCClient()
      try client.connect()
      try client.initialize()
      do {
        _ = try client.callJSONRPC("hints.activate-chrome")
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }
    }
  }
}
