import Foundation
import UsageCore
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

signal(SIGPIPE, SIG_IGN)
let args = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let index = args.firstIndex(of: name), args.count > index + 1 else { return nil }
    return args[index + 1]
}
if args.contains("--help") {
    print("""
    astra-usage [--json] [--codex /path/to/codex]
    astra-usage --logs [--sessions /path/to/sessions] [--json]

    Read-only account/rateLimits/read; never starts a model turn.
    --logs explicitly selects local snapshots (not tied to the signed-in account).
    No access tokens, cookies, prompts, raw responses or email addresses are printed.
    """)
    exit(0)
}
do {
    let snapshot: UsageSnapshot
    if args.contains("--logs") {
        snapshot = try LogReader.read(directory: option("--sessions").map { URL(fileURLWithPath: $0) } ?? LogReader.defaultDirectory)
    } else {
        guard let cli = CodexClient.executable(custom: option("--codex")) else { throw UsageError.noCLI }
        snapshot = try CodexClient.fetch(executable: cli)
    }
    if args.contains("--json") {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        print(String(decoding: try encoder.encode(snapshot), as: UTF8.self))
    } else {
        print("AstraBar · \(snapshot.source.label)")
        for bucket in snapshot.buckets {
            print("\n\(bucket.displayName) [\(bucket.id)] · \(bucket.plan ?? "套餐未知")")
            for window in bucket.windows {
                let invalid = bucket.isStale() || window.isExpired()
                let remaining = String(format: "%.1f%%", window.remainingPercent)
                print("  \(window.label): \(invalid ? "待刷新，历史记录 " : "剩余 ")\(remaining)")
                if let reset = window.resetsAt { print("  重置: \(reset.formatted(date: .complete, time: .standard))") }
            }
        }
        if !snapshot.hasAstra { print("\nAstra 独立额度未返回；其他配额不等于 Astra 剩余次数。") }
        snapshot.warnings.forEach { print($0) }
    }
} catch {
    let text = (error as? UsageError)?.localizedDescription ?? "额度读取失败。"
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}
