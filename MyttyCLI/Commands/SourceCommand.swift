import ArgumentParser
import Foundation
import MyttyShared

struct SourceCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "source",
    abstract: "Manage session sources",
    subcommands: [List.self]
  )

  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List configured session sources")

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    @Flag(name: .long, help: "Output as human-readable text")
    var human = false

    func run() throws {
      let format = OutputFormat.detect(forceJSON: json, forceHuman: human)
      let formatter = OutputFormatter(format: format)
      let client = IPCClient()
      try client.connect()
      try client.initialize()

      let data: Data
      do {
        let result = try client.callJSONRPC("source.list")
        data = try JSONEncoder().encode(result)
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      switch format {
      case .json:
        formatter.printJSON(data)
      case .human:
        if let sources = try? JSONDecoder().decode([SourceResponse].self, from: data) {
          if sources.isEmpty {
            print("No session sources configured")
          } else {
            let rows = sources.map { s in
              [s.name, s.lastStatus, "\(s.priority)"]
            }
            formatter.printTable(
              headers: ["NAME", "STATUS", "PRIORITY"],
              rows: rows
            )
          }
        }
      }
    }
  }
}
