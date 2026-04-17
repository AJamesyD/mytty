import Darwin
import Foundation
import MyttyShared

enum IPCClientError: LocalizedError, CustomStringConvertible {
    case connectionFailed(String)
    case remoteError(String)

    var description: String {
        switch self {
        case .connectionFailed(let message): return message
        case .remoteError(let message): return message
        }
    }

    var errorDescription: String? { description }
}

/// CLI-side IPC client using Unix domain sockets to communicate with the Mytty app.
final class IPCClient {
    private var socketFD: Int32 = -1
    private var nextRequestId: Int = 1

    /// Connect to the running Mytty app, launching it if needed.
    func connect() throws {
        if tryConnect() { return }

        // Launch the app
        let launchProcess = Process()
        launchProcess.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        launchProcess.arguments = ["-a", "Mytty"]
        try? launchProcess.run()
        launchProcess.waitUntilExit()

        // Retry with exponential backoff
        let delays: [UInt32] = [100_000, 200_000, 400_000, 800_000, 1_600_000]
        for delay in delays {
            usleep(delay)
            if tryConnect() { return }
        }

        throw IPCClientError.connectionFailed(
            "Could not connect to Mytty.app. Is it running?"
        )
    }

    private func tryConnect() -> Bool {
        let path = MyttyIPC.socketPath

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }

        // Set SO_NOSIGPIPE
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    _ = memcpy(dest, src.baseAddress!, src.count)
                }
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        if result != 0 {
            close(fd)
            return false
        }

        socketFD = fd
        return true
    }

    func callJSONRPC(_ method: String, params: [String: JSONValue]? = nil) throws -> JSONValue {
        let id = nextRequestId
        nextRequestId += 1
        let request = JSONRPCMessage.Request(method: method, params: params, id: id)
        let requestData = try JSONEncoder().encode(request)
        try writeContentLengthMessage(data: requestData)
        let responseData = try readContentLengthMessage()
        let response = try JSONDecoder().decode(JSONRPCMessage.Response.self, from: responseData)
        if let error = response.error {
            throw IPCClientError.remoteError("[\(error.code)] \(error.message)")
        }
        return response.result ?? .null
    }

    func initialize() throws {
        let result = try callJSONRPC("initialize", params: [
            "clientVersion": .string(MyttyIPC.protocolVersion),
            "clientName": "mytty-cli",
        ])
        _ = result
    }

    deinit {
        if socketFD >= 0 { close(socketFD) }
    }

    // MARK: - Content-Length Framing

    private func readContentLengthMessage() throws -> Data {
        var headerBytes = Data()
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A])
        while headerBytes.count < 256 {
            let byte = try readExact(count: 1)
            headerBytes.append(byte)
            if headerBytes.count >= 4, Data(headerBytes.suffix(4)) == separator {
                break
            }
        }
        guard headerBytes.count >= 4, Data(headerBytes.suffix(4)) == separator else {
            throw IPCClientError.connectionFailed("Invalid Content-Length header")
        }
        let headerStr = String(data: headerBytes.dropLast(4), encoding: .utf8) ?? ""
        guard headerStr.hasPrefix("Content-Length: "),
              let length = Int(headerStr.dropFirst("Content-Length: ".count)),
              length > 0, length <= MyttyIPC.maxMessageSize
        else {
            throw IPCClientError.connectionFailed("Invalid Content-Length value")
        }
        return try readExact(count: length)
    }

    private func writeContentLengthMessage(data: Data) throws {
        let header = "Content-Length: \(data.count)\r\n\r\n"
        try writeAll(data: Data(header.utf8))
        try writeAll(data: data)
    }

    // MARK: - Socket I/O Helpers

    private func readExact(count: Int) throws -> Data {
        var buffer = Data(count: count)
        var offset = 0
        while offset < count {
            let n = buffer.withUnsafeMutableBytes { ptr in
                Darwin.read(socketFD, ptr.baseAddress! + offset, count - offset)
            }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 {
                throw IPCClientError.connectionFailed("Read failed")
            }
            offset += n
        }
        return buffer
    }

    private func writeAll(data: Data) throws {
        var offset = 0
        while offset < data.count {
            let n = data.withUnsafeBytes { ptr in
                Darwin.write(socketFD, ptr.baseAddress! + offset, data.count - offset)
            }
            if n < 0 && errno == EINTR { continue }
            if n <= 0 {
                throw IPCClientError.connectionFailed("Write failed")
            }
            offset += n
        }
    }
}
