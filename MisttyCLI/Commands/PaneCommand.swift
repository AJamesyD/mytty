import ArgumentParser
import Foundation
import MisttyShared

struct PaneCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pane",
        abstract: "Manage panes",
        subcommands: [
            Create.self,
            List.self,
            Get.self,
            Close.self,
            Focus.self,
            Resize.self,
            Active.self,
            SendKeys.self,
            RunCommand.self,
            GetText.self,
        ]
    )

    struct Create: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Create a new pane")

        @Option(name: .long, help: "Tab ID")
        var tab: Int

        @Option(name: .long, help: "Split direction (horizontal or vertical)")
        var direction: String?

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

            var params: [String: JSONValue] = ["tabId": .int(tab)]
            if let direction { params["direction"] = .string(direction) }

            let data: Data
            do {
                let result = try client.callJSONRPC("pane.create", params: params)
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let pane = try? JSONDecoder().decode(PaneResponse.self, from: data) {
                    formatter.printSingle([
                        ("ID", "\(pane.id)"),
                        ("Directory", pane.directory ?? "-"),
                    ])
                }
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List panes in a tab")

        @Option(name: .long, help: "Tab ID")
        var tab: Int

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
                let result = try client.callJSONRPC("pane.list", params: ["tabId": .int(tab)])
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let panes = try? JSONDecoder().decode([PaneResponse].self, from: data) {
                    let rows = panes.map { p in
                        ["\(p.id)", p.directory ?? "-"]
                    }
                    formatter.printTable(
                        headers: ["ID", "DIRECTORY"],
                        rows: rows
                    )
                }
            }
        }
    }

    struct Get: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Get pane details")

        @Argument(help: "Pane ID")
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
                let result = try client.callJSONRPC("pane.get", params: ["id": .int(id)])
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let pane = try? JSONDecoder().decode(PaneResponse.self, from: data) {
                    formatter.printSingle([
                        ("ID", "\(pane.id)"),
                        ("Directory", pane.directory ?? "-"),
                    ])
                }
            }
        }
    }

    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Close a pane")

        @Argument(help: "Pane ID")
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
                _ = try client.callJSONRPC("pane.close", params: ["id": .int(id)])
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            formatter.printSuccess("Pane \(id) closed")
        }
    }

    struct Focus: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Focus a pane")

        @Argument(help: "Pane ID (omit when using --direction)")
        var id: Int?

        @Option(name: .long, help: "Focus direction (left, right, up, down)")
        var direction: String?

        @Option(name: .long, help: "Session ID for direction-based focus (0 = active)")
        var session: Int = 0

        @Flag(name: .long, help: "Output as JSON")
        var json = false

        @Flag(name: .long, help: "Output as human-readable text")
        var human = false

        func validate() throws {
            if id == nil && direction == nil {
                throw ValidationError("Provide either a pane ID or --direction")
            }
        }

        func run() throws {
            let format = OutputFormat.detect(forceJSON: json, forceHuman: human)
            let formatter = OutputFormatter(format: format)
            let client = IPCClient()
            try client.connect()
            try client.initialize()

            let data: Data
            do {
                if let direction {
                    let result = try client.callJSONRPC("pane.focusByDirection", params: ["direction": .string(direction), "sessionId": .int(session)])
                    data = try JSONEncoder().encode(result)
                } else if let id {
                    let result = try client.callJSONRPC("pane.focus", params: ["id": .int(id)])
                    data = try JSONEncoder().encode(result)
                } else {
                    OutputFormatter.printError("Provide either a pane ID or --direction")
                    Foundation.exit(1)
                }
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let pane = try? JSONDecoder().decode(PaneResponse.self, from: data) {
                    formatter.printSingle([
                        ("ID", "\(pane.id)"),
                        ("Directory", pane.directory ?? "-"),
                    ])
                } else {
                    formatter.printSuccess("Pane focused")
                }
            }
        }
    }

    struct Resize: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Resize a pane")

        @Argument(help: "Pane ID")
        var id: Int

        @Option(name: .long, help: "Resize direction (up, down, left, right)")
        var direction: String

        @Option(name: .long, help: "Amount to resize")
        var amount: Int = 1

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
                _ = try client.callJSONRPC("pane.resize", params: ["id": .int(id), "direction": .string(direction), "amount": .int(amount)])
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            formatter.printSuccess("Pane \(id) resized")
        }
    }

    struct Active: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Get the active pane")

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
                let result = try client.callJSONRPC("pane.active")
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let pane = try? JSONDecoder().decode(PaneResponse.self, from: data) {
                    formatter.printSingle([
                        ("ID", "\(pane.id)"),
                        ("Directory", pane.directory ?? "-"),
                    ])
                }
            }
        }
    }

    struct SendKeys: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "send-keys",
            abstract: "Send keys to a pane"
        )

        @Argument(help: "Keys to send")
        var keys: String

        @Option(name: .long, help: "Pane ID (0 = active pane)")
        var pane: Int = 0

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
                _ = try client.callJSONRPC("pane.sendKeys", params: ["paneId": .int(pane), "keys": .string(keys)])
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            formatter.printSuccess("Keys sent")
        }
    }

    struct RunCommand: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "run-command",
            abstract: "Run a command in a pane"
        )

        @Argument(help: "Command to run")
        var command: String

        @Option(name: .long, help: "Pane ID (0 = active pane)")
        var pane: Int = 0

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
                _ = try client.callJSONRPC("pane.runCommand", params: ["paneId": .int(pane), "command": .string(command)])
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            formatter.printSuccess("Command sent")
        }
    }

    struct GetText: ParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "get-text",
            abstract: "Get text content from a pane"
        )

        @Option(name: .long, help: "Pane ID (0 = active pane)")
        var pane: Int = 0

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
                let result = try client.callJSONRPC("pane.getText", params: ["paneId": .int(pane)])
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let text = String(data: data, encoding: .utf8) {
                    print(text)
                }
            }
        }
    }
}
