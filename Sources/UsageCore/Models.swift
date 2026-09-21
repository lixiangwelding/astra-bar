import Foundation
import CoreFoundation

public enum UsageSource: String, Codable, Sendable {
    case live, localLogs
    public var label: String { self == .live ? "官方接口" : "本地日志 · 账号未核验" }
}

public struct QuotaWindow: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let usedPercent: Double
    public let minutes: Int?
    public let resetsAt: Date?
    public var remainingPercent: Double { max(0, 100 - usedPercent) }
    public var isWeekly: Bool { minutes == 10080 }
    public func isExpired(at date: Date = Date()) -> Bool { resetsAt.map { $0 <= date } ?? false }
    public var label: String {
        guard let minutes else { return "周期未知" }
        if minutes == 10080 { return "每周额度" }
        if minutes % 1440 == 0 { return "\(minutes / 1440) 天额度" }
        if minutes % 60 == 0 { return "\(minutes / 60) 小时额度" }
        return "\(minutes) 分钟额度"
    }
}

public struct QuotaBucket: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String?
    public let plan: String?
    public let windows: [QuotaWindow]
    public let observedAt: Date
    public var isAstra: Bool {
        id.lowercased().contains("astra") || (name?.lowercased().contains("astra") ?? false)
    }
    public var displayName: String { id == "codex" ? "Codex 总额度" : name ?? id }
    public var shortName: String {
        if id == "codex" { return "Codex" }
        if isAstra { return "Astra" }
        return String(displayName.prefix(14))
    }
    public var preferredWindow: QuotaWindow? { windows.first(where: \.isWeekly) ?? windows.first }
    public func isStale(at now: Date = Date()) -> Bool {
        now.timeIntervalSince(observedAt) > 600 || observedAt.timeIntervalSince(now) > 120
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public let buckets: [QuotaBucket]
    public let source: UsageSource
    public let capturedAt: Date
    public let warnings: [String]
    public init(buckets: [QuotaBucket], source: UsageSource, capturedAt: Date, warnings: [String] = []) {
        self.buckets = buckets; self.source = source; self.capturedAt = capturedAt; self.warnings = warnings
    }
    public func selected(preferredID: String = "") -> QuotaBucket? {
        if let match = buckets.first(where: { $0.id == preferredID }) { return match }
        return buckets.first(where: \.isAstra) ?? buckets.first(where: { $0.id == "codex" }) ?? buckets.first
    }
    public var hasAstra: Bool { buckets.contains(where: \.isAstra) }
}

public enum UsageError: Error, LocalizedError {
    case noCLI, startFailed, timedOut, invalidResponse, serviceUnavailable, noLogs, noQuota
    public var errorDescription: String? {
        switch self {
        case .noCLI: return "未找到 Codex。请在设置中选择 codex 程序，或切换到本地日志模式。"
        case .startFailed: return "Codex 程序启动失败。请重新选择可执行程序。"
        case .timedOut: return "额度查询超时。请检查网络，稍后刷新。"
        case .invalidResponse: return "无法识别额度数据；当前客户端版本可能不兼容。"
        case .serviceUnavailable: return "官方额度查询失败。请检查 Codex 登录状态、订阅账号或网络后刷新。"
        case .noLogs: return "没有可读的会话日志。请选择 Codex 的 sessions 文件夹。"
        case .noQuota: return "没有可用的额度字段。不会将缺失数据显示成剩余 100%。"
        }
    }
}

public enum UsageParser {
    static func number(_ value: Any?) -> Double? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue.isFinite ? value.doubleValue : nil
    }
    static func text(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let clean = text.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
        let result = String(String.UnicodeScalarView(clean)).trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : String(result.prefix(120))
    }
    public static func window(_ value: Any?, slot: String) -> QuotaWindow? {
        guard let dict = value as? [String: Any],
              let used = number(dict["usedPercent"] ?? dict["used_percent"]), used >= 0 else { return nil }
        let duration = number(dict["windowDurationMins"] ?? dict["window_minutes"])
        let minutes = duration.flatMap { $0 > 0 && $0 < 5256000 && $0.rounded() == $0 ? Int($0) : nil }
        let reset = number(dict["resetsAt"] ?? dict["resets_at"])
        let resetsAt = reset.flatMap { $0 > 0 && $0 < 4102444800 ? Date(timeIntervalSince1970: $0) : nil }
        return QuotaWindow(id: slot, usedPercent: min(100, used), minutes: minutes, resetsAt: resetsAt)
    }
    public static func bucket(_ dict: [String: Any], fallbackID: String? = nil, at date: Date) -> QuotaBucket? {
        // Missing identity remains unknown; it is never silently relabelled Codex/Astra.
        let id = text(dict["limitId"] ?? dict["limit_id"]) ?? fallbackID ?? "unknown"
        let windows = ["primary", "secondary"].compactMap { window(dict[$0], slot: $0) }
            .sorted { ($0.minutes ?? Int.max) < ($1.minutes ?? Int.max) }
        guard !windows.isEmpty else { return nil }
        return QuotaBucket(id: id, name: text(dict["limitName"] ?? dict["limit_name"]),
                           plan: text(dict["planType"] ?? dict["plan_type"]), windows: windows, observedAt: date)
    }
    public static func live(_ data: Data, at date: Date = Date()) throws -> UsageSnapshot {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageError.invalidResponse
        }
        if root["error"] != nil { throw UsageError.serviceUnavailable }
        let result = root["result"] as? [String: Any] ?? root
        var buckets: [String: QuotaBucket] = [:]
        if let mapping = result["rateLimitsByLimitId"] as? [String: Any] {
            for key in mapping.keys.sorted() {
                if let dict = mapping[key] as? [String: Any], let b = bucket(dict, fallbackID: key, at: date) {
                    buckets[b.id] = b
                }
            }
        }
        if let dict = result["rateLimits"] as? [String: Any], let b = bucket(dict, at: date), buckets[b.id] == nil {
            buckets[b.id] = b
        }
        guard !buckets.isEmpty else { throw UsageError.noQuota }
        return UsageSnapshot(buckets: buckets.values.sorted { $0.id < $1.id }, source: .live, capturedAt: date)
    }
    public static func logLine(_ data: Data, now: Date = Date()) -> QuotaBucket? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              root["type"] as? String == "event_msg",
              let payload = root["payload"] as? [String: Any], payload["type"] as? String == "token_count",
              let limits = payload["rate_limits"] as? [String: Any],
              let timestamp = root["timestamp"] as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = formatter.date(from: timestamp) ?? ISO8601DateFormatter().date(from: timestamp)
        guard let date, date <= now.addingTimeInterval(120) else { return nil }
        return bucket(limits, at: date)
    }
}

public enum StatusText {
    public static func title(bucket: QuotaBucket?, source: UsageSource = .live, failed: Bool = false, now: Date = Date()) -> String {
        guard let bucket, let window = bucket.preferredWindow else { return "Astra —" }
        if failed || bucket.isStale(at: now) || window.isExpired(at: now) { return "\(bucket.shortName) —" }
        let mark = source == .localLogs ? "~" : ""
        return "\(bucket.shortName) \(mark)\(Int(window.remainingPercent.rounded(.down)))%"
    }
}
