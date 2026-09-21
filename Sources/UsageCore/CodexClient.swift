import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public enum CodexClient {
    public static func executable(custom: String? = nil) -> URL? {
        if let custom, !custom.isEmpty {
            return FileManager.default.isExecutableFile(atPath: custom) ? URL(fileURLWithPath: custom) : nil
        }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex",
            "\(home)/Applications/Codex.app/Contents/Resources/codex",
            "/Applications/ChatGPT.app/Contents/Resources/codex"
        ]
        return candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
    /// Run off the main thread. Bounded, read-only RPC; raw responses/stderr are never exposed.
    public static func fetch(executable: URL, timeout: TimeInterval = 20) throws -> UsageSnapshot {
        let process = Process()
        let input = Pipe(), output = Pipe()
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [executable.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", environment["PATH"] ?? ""].joined(separator: ":")
        process.environment = environment
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { throw UsageError.startFailed }
        try? output.fileHandleForWriting.close()
        try? input.fileHandleForReading.close()
        defer {
            try? input.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            if process.isRunning {
                process.terminate()
                let deadline = ProcessInfo.processInfo.systemUptime + 0.75
                while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
                    Thread.sleep(forTimeInterval: 0.01)
                }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        func send(_ object: [String: Any]) throws {
            var bytes = try JSONSerialization.data(withJSONObject: object, options: [.withoutEscapingSlashes])
            bytes.append(0x0a)
            do { try input.fileHandleForWriting.write(contentsOf: bytes) } catch { throw UsageError.serviceUnavailable }
        }
        try send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "astra_bar", "title": "AstraBar", "version": "0.1.0"]
        ]])
        let deadline = ProcessInfo.processInfo.systemUptime + max(0.05, timeout)
        let fd = output.fileHandleForReading.fileDescriptor
        var pending = Data(), total = 0, initialized = false
        var bytes = [UInt8](repeating: 0, count: 65536)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let result = poll(&descriptor, 1, 100)
            if result < 0 {
                if errno == EINTR { continue }
                throw UsageError.serviceUnavailable
            }
            if result == 0 { continue }
            let count = read(fd, &bytes, bytes.count)
            if count == 0 { throw UsageError.serviceUnavailable }
            if count < 0 {
                if errno == EINTR { continue }
                throw UsageError.serviceUnavailable
            }
            total += count
            guard total <= 4 * 1024 * 1024 else { throw UsageError.invalidResponse }
            pending.append(contentsOf: bytes.prefix(count))
            while let newline = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if let id = message["id"] as? Int, id == 1 && !initialized {
                    guard message["error"] == nil, message["result"] != nil else { throw UsageError.serviceUnavailable }
                    initialized = true
                    try send(["method": "initialized", "params": [:]])
                    try send(["id": 2, "method": "account/rateLimits/read"])
                } else if let id = message["id"] as? Int, id == 2 && initialized {
                    return try UsageParser.live(line)
                } else if message["method"] != nil && message["id"] != nil {
                    // No interactive authentication, attestation, approval or other server requests.
                    throw UsageError.serviceUnavailable
                }
            }
        }
        throw UsageError.timedOut
    }
}
