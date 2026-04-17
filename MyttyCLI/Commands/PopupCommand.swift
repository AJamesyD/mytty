import ArgumentParser
import Foundation
import MyttyShared

struct PopupCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "popup",
        abstract: "Manage popup windows",
        subcommands: [
            Open.self,
            Close.self,
            Toggle.self,
            List.self,
        ]
    )

    struct Open: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Open a popup window")

        @Option(name: .long, help: "Session ID (defaults to active session)")
        var session: Int?

        @Option(name: .long, help: "Popup name")
        var name: String?

        @Option(name: .long, help: "Command to execute")
        var exec: String?

        @Option(name: .long, help: "Width as fraction of window (0.0-1.0)")
        var width: Double = 0.8

        @Option(name: .long, help: "Height as fraction of window (0.0-1.0)")
        var height: Double = 0.8

        @Flag(name: .long, help: "Close popup when process exits")
        var closeOnExit: Bool = false

        @Flag(name: .long, help: "Keep popup open when process exits")
        var keepOnExit: Bool = false

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

            let sessionId = try resolveSessionId(session, client: client)
            let popupName = name ?? exec ?? "popup"
            guard let command = exec ?? name else {
                OutputFormatter.printError("Provide --name (from config) or --exec (ad-hoc command)")
                Foundation.exit(1)
            }

            let shouldCloseOnExit = closeOnExit || !keepOnExit

            let data: Data
            do {
                let result = try client.callJSONRPC("popup.open", params: [
                    "sessionId": .int(sessionId),
                    "name": .string(popupName),
                    "exec": .string(command),
                    "width": .double(width),
                    "height": .double(height),
                    "closeOnExit": .bool(shouldCloseOnExit),
                ])
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let popup = try? JSONDecoder().decode(PopupResponse.self, from: data) {
                    formatter.printSingle([
                        ("ID", "\(popup.id)"),
                        ("Name", popup.name),
                        ("Command", popup.command),
                        ("Visible", "\(popup.isVisible)"),
                        ("Pane ID", "\(popup.paneId)"),
                    ])
                }
            }
        }
    }

    struct Close: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Close a popup window")

        @Argument(help: "Popup ID")
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
                _ = try client.callJSONRPC("popup.close", params: ["id": .int(id)])
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            formatter.printSuccess("Popup \(id) closed")
        }
    }

    struct Toggle: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Toggle a named popup")

        @Argument(help: "Popup name (from config)")
        var name: String

        @Option(name: .long, help: "Session ID (defaults to active session)")
        var session: Int?

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

            let sessionId = try resolveSessionId(session, client: client)

            let data: Data
            do {
                let result = try client.callJSONRPC("popup.toggle", params: ["sessionId": .int(sessionId), "name": .string(name)])
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let popup = try? JSONDecoder().decode(PopupResponse.self, from: data) {
                    formatter.printSingle([
                        ("ID", "\(popup.id)"),
                        ("Name", popup.name),
                        ("Visible", "\(popup.isVisible)"),
                    ])
                } else {
                    formatter.printSuccess("Popup '\(name)' toggled")
                }
            }
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(abstract: "List popup windows")

        @Option(name: .long, help: "Session ID (defaults to active session)")
        var session: Int?

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

            let sessionId = try resolveSessionId(session, client: client)

            let data: Data
            do {
                let result = try client.callJSONRPC("popup.list", params: ["sessionId": .int(sessionId)])
                data = try JSONEncoder().encode(result)
            } catch {
                OutputFormatter.printError(error.localizedDescription)
                Foundation.exit(1)
            }

            switch format {
            case .json:
                formatter.printJSON(data)
            case .human:
                if let popups = try? JSONDecoder().decode([PopupResponse].self, from: data) {
                    let rows = popups.map { p in
                        ["\(p.id)", p.name, p.command, p.isVisible ? "visible" : "hidden", "\(p.paneId)"]
                    }
                    formatter.printTable(
                        headers: ["ID", "NAME", "COMMAND", "STATUS", "PANE"],
                        rows: rows
                    )
                }
            }
        }
    }
}

private func resolveSessionId(_ provided: Int?, client: IPCClient) throws -> Int {
    if let sid = provided { return sid }
    let result = try client.callJSONRPC("session.list")
    let data = try JSONEncoder().encode(result)
    guard let sessions = try? JSONDecoder().decode([SessionResponse].self, from: data),
          let first = sessions.first
    else {
        OutputFormatter.printError("No active session. Specify --session")
        Foundation.exit(1)
    }
    return first.id
}
