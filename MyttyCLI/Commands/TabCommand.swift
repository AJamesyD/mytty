import ArgumentParser
import Foundation
import MyttyShared

struct TabCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tab",
    abstract: "Manage tabs",
    subcommands: [
      Create.self,
      List.self,
      Get.self,
      Close.self,
      Rename.self,
      Move.self,
    ]
  )

  struct Create: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Create a new tab")

    @Option(name: .long, help: "Session ID")
    var session: Int

    @Option(name: .long, help: "Tab name")
    var name: String?

    @Option(name: .long, help: "Executable to run")
    var exec: String?

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

      var params: [String: JSONValue] = ["sessionId": .int(session)]
      if let name { params["name"] = .string(name) }
      if let exec { params["exec"] = .string(exec) }

      let data: Data
      do {
        let result = try client.callJSONRPC("tab.create", params: params)
        data = try JSONEncoder().encode(result)
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      switch format {
      case .json:
        formatter.printJSON(data)
      case .human:
        if let tab = try? JSONDecoder().decode(TabResponse.self, from: data) {
          formatter.printSingle([
            ("ID", "\(tab.id)"),
            ("Title", tab.title),
            ("Panes", "\(tab.paneCount)"),
          ])
        }
      }
    }
  }

  struct List: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "List tabs in a session")

    @Option(name: .long, help: "Session ID")
    var session: Int

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
        let result = try client.callJSONRPC("tab.list", params: ["sessionId": .int(session)])
        data = try JSONEncoder().encode(result)
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      switch format {
      case .json:
        formatter.printJSON(data)
      case .human:
        if let tabs = try? JSONDecoder().decode([TabResponse].self, from: data) {
          let rows = tabs.map { t in
            ["\(t.id)", t.title, "\(t.paneCount)"]
          }
          formatter.printTable(
            headers: ["ID", "TITLE", "PANES"],
            rows: rows
          )
        }
      }
    }
  }

  struct Get: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Get tab details")

    @Argument(help: "Tab ID")
    var id: Int

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
        let result = try client.callJSONRPC("tab.get", params: ["id": .int(id)])
        data = try JSONEncoder().encode(result)
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      switch format {
      case .json:
        formatter.printJSON(data)
      case .human:
        if let tab = try? JSONDecoder().decode(TabResponse.self, from: data) {
          formatter.printSingle([
            ("ID", "\(tab.id)"),
            ("Title", tab.title),
            ("Panes", "\(tab.paneCount)"),
            ("Pane IDs", tab.paneIds.map { "\($0)" }.joined(separator: ", ")),
          ])
        }
      }
    }
  }

  struct Close: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Close a tab")

    @Argument(help: "Tab ID")
    var id: Int

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

      do {
        _ = try client.callJSONRPC("tab.close", params: ["id": .int(id)])
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      formatter.printSuccess("Tab \(id) closed")
    }
  }

  struct Rename: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Rename a tab")

    @Argument(help: "Tab ID")
    var id: Int

    @Argument(help: "New name")
    var name: String

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
        let result = try client.callJSONRPC(
          "tab.rename", params: ["id": .int(id), "name": .string(name)])
        data = try JSONEncoder().encode(result)
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      switch format {
      case .json:
        formatter.printJSON(data)
      case .human:
        if let tab = try? JSONDecoder().decode(TabResponse.self, from: data) {
          formatter.printSingle([
            ("ID", "\(tab.id)"),
            ("Title", tab.title),
            ("Panes", "\(tab.paneCount)"),
          ])
        }
      }
    }
  }

  struct Move: ParsableCommand {
    static let configuration = CommandConfiguration(abstract: "Move a tab to a new position")

    @Argument(help: "Tab ID")
    var id: Int

    @Argument(help: "Destination index (0-based)")
    var toIndex: Int

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
        let result = try client.callJSONRPC(
          "tab.move", params: ["id": .int(id), "toIndex": .int(toIndex)])
        data = try JSONEncoder().encode(result)
      } catch {
        OutputFormatter.printError(error.localizedDescription)
        Foundation.exit(1)
      }

      switch format {
      case .json:
        formatter.printJSON(data)
      case .human:
        if let tab = try? JSONDecoder().decode(TabResponse.self, from: data) {
          formatter.printSingle([
            ("ID", "\(tab.id)"),
            ("Title", tab.title),
            ("Panes", "\(tab.paneCount)"),
          ])
        }
      }
    }
  }
}
