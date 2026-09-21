import Foundation

public enum LogReader {
    public static var defaultDirectory: URL {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        return home.appendingPathComponent("sessions")
    }
    /// Bounded local-only snapshots; no auth.json, no network, no copied conversations.
    public static func read(directory: URL, now: Date = Date(), maxFiles: Int = 24, tailBytes: Int = 512 * 1024) throws -> UsageSnapshot {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey]
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let iterator = fm.enumerator(at: directory, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            throw UsageError.noLogs
        }
        var candidates: [(URL, Date)] = [], visited = 0
        var bounded = false
        for case let file as URL in iterator {
            visited += 1
            if visited > 20000 { bounded = true; break }
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { iterator.skipDescendants(); continue }
            guard values.isRegularFile == true, file.pathExtension == "jsonl" else { continue }
            candidates.append((file, values.contentModificationDate ?? .distantPast))
        }
        guard !candidates.isEmpty else { throw UsageError.noLogs }
        let fileLimit = max(1, min(24, maxFiles)), byteLimit = max(256, min(512 * 1024, tailBytes))
        candidates.sort { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 > $1.1 }
        if candidates.count > fileLimit { bounded = true }
        var buckets: [String: QuotaBucket] = [:]
        let marker = Data("\"rate_limits\"".utf8)
        for (file, _) in candidates.prefix(fileLimit) {
            guard let handle = try? FileHandle(forReadingFrom: file) else { continue }
            defer { try? handle.close() }
            guard let size = try? handle.seekToEnd() else { continue }
            let offset = size > UInt64(byteLimit) ? size - UInt64(byteLimit) : 0
            if offset > 0 { bounded = true }
            try? handle.seek(toOffset: offset)
            guard let content = try? handle.read(upToCount: byteLimit) else { continue }
            var lines = content.split(separator: 0x0a, omittingEmptySubsequences: false)
            if offset > 0 && !lines.isEmpty { lines.removeFirst() }
            if content.last != 0x0a && !lines.isEmpty { lines.removeLast() }
            for line in lines.reversed() where line.range(of: marker) != nil {
                guard let bucket = UsageParser.logLine(Data(line), now: now) else { continue }
                if let previous = buckets[bucket.id], previous.observedAt >= bucket.observedAt { continue }
                buckets[bucket.id] = bucket
            }
        }
        guard !buckets.isEmpty else { throw UsageError.noQuota }
        var warnings = ["日志是历史快照，可能来自其他账号；不代表 ChatGPT 网页对话次数。"]
        if bounded { warnings.append("为降低磁盘开销，仅检查有界范围内的近期日志；未做全量历史扫描。") }
        return UsageSnapshot(buckets: buckets.values.sorted { $0.id < $1.id }, source: .localLogs, capturedAt: now, warnings: warnings)
    }
}
