#if os(macOS)
import SwiftUI
import AppKit
import ServiceManagement
import UsageCore

@MainActor
struct Dashboard: View {
    @ObservedObject var store: UsageStore
    private var selected: QuotaBucket? { store.selected }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let snapshot = store.snapshot, let bucket = selected {
                        if snapshot.buckets.count > 1 {
                            Picker("显示额度", selection: Binding(get: { bucket.id }, set: { store.selectedID = $0 })) {
                                ForEach(snapshot.buckets) { Text($0.displayName).tag($0.id) }
                            }
                            .pickerStyle(.menu)
                        }
                        HStack(spacing: 8) {
                            Text(bucket.displayName).font(.headline)
                            Spacer()
                            if let plan = bucket.plan { Text(plan.uppercased()).font(.caption.bold()).foregroundStyle(.secondary) }
                        }
                        ForEach(bucket.windows.sorted { ($0.isWeekly ? 0 : 1) < ($1.isWeekly ? 0 : 1) }) { window in
                            QuotaCard(window: window, stale: store.isStale, now: store.now)
                        }
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                            Text("数据时间 \(bucket.observedAt.formatted(date: .abbreviated, time: .standard))")
                        }.font(.caption2).foregroundStyle(.secondary)
                        if !snapshot.hasAstra {
                            Notice(text: "Astra 独立额度未公开\n当前结果没有明确标注 Astra 的配额。Codex 总额度、reserve 或 Spark 都不能当作 Astra 剩余次数。", symbol: "info.circle")
                        }
                        ForEach(snapshot.warnings, id: \.self) { Notice(text: $0, symbol: "doc.text.magnifyingglass") }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: store.busy ? "arrow.triangle.2.circlepath" : "gauge.with.dots.needle.0percent")
                                .font(.system(size: 36, weight: .light)).foregroundStyle(.secondary)
                            Text(store.busy ? "正在读取额度" : "暂未获取额度").font(.title3.weight(.semibold))
                            Text("只显示真实返回的数据。\n未知额度不会显示为 100%。")
                                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        }.frame(maxWidth: .infinity).padding(.vertical, 26)
                    }
                    if let error = store.error { Notice(text: error, symbol: "exclamationmark.triangle", warning: true) }
                    if let error = store.settingsError { Notice(text: error, symbol: "gearshape", warning: true) }
                }.padding(20)
            }
            Divider()
            footer.padding(.horizontal, 16).padding(.vertical, 12)
        }
        .frame(width: 360, height: 570)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkle").font(.system(size: 22, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text("AstraBar").font(.system(size: 19, weight: .semibold, design: .rounded))
                HStack(spacing: 5) {
                    Circle().fill(store.error != nil ? Color.orange : store.source == .live ? Color.green : Color.secondary).frame(width: 5, height: 5)
                    Text(store.source.label).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if store.busy { ProgressView().controlSize(.small).scaleEffect(0.8) }
            else {
                Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).help("刷新额度，每 60 秒自动刷新")
            }
        }
    }
    private var footer: some View {
        HStack {
            Menu {
                Button("官方接口（实时）") { store.changeSource(.live) }.disabled(store.busy)
                Button("本地日志（快照）") { store.changeSource(.localLogs) }.disabled(store.busy)
                Divider()
                Button("选择 Codex 程序…") { store.choosePath(directory: false) }.disabled(store.busy)
                Button("选择日志文件夹…") { store.choosePath(directory: true) }.disabled(store.busy)
                Button("恢复自动查找") { store.resetPaths() }.disabled(store.busy)
                Divider()
                Button(SMAppService.mainApp.status == .enabled ? "✓ 登录时启动" : "登录时启动") { store.toggleLogin() }
                Button("项目与帮助") { openURL("https://github.com/lixiangwelding/astra-bar") }
                Divider()
                Button("退出 AstraBar") { NSApp.terminate(nil) }.keyboardShortcut("q")
            } label: { Image(systemName: "gearshape") }
            .menuStyle(.borderlessButton).frame(width: 28)
            Text("不上传日志 · 不保存凭据").font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Button("用量页面 ↗") { openURL("https://chatgpt.com/codex/settings/usage") }
                .buttonStyle(.plain).font(.caption).foregroundStyle(Color.accentColor)
        }
    }
    private func openURL(_ string: String) {
        if let url = URL(string: string) { NSWorkspace.shared.open(url) }
    }
}

private struct QuotaCard: View {
    let window: QuotaWindow
    let stale: Bool
    let now: Date
    private var invalid: Bool { stale || window.isExpired(at: now) }
    private var tint: Color { invalid ? .secondary : window.remainingPercent <= 10 ? .orange : .accentColor }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                Spacer()
                if invalid {
                    Text(window.isExpired(at: now) ? "待刷新" : "已过期").font(.headline).foregroundStyle(.secondary)
                } else {
                    Text(window.remainingPercent, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: window.isWeekly ? 34 : 27, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("% 剩余").font(.caption).foregroundStyle(.secondary)
                }
            }
            ProgressView(value: invalid ? 0 : window.remainingPercent, total: 100).tint(tint)
                .accessibilityLabel("\(window.label)剩余")
            if invalid {
                Text("历史记录：剩余 \(window.remainingPercent.formatted(.number.precision(.fractionLength(1))))%；不是当前可用额度。")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let reset = window.resetsAt {
                HStack {
                    Text("重置 \(reset.formatted(date: .abbreviated, time: .shortened))")
                    Spacer()
                    if reset > now { Text(reset, style: .relative) }
                }.font(.caption2).foregroundStyle(.secondary)
            } else { Text("重置时间未提供").font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(16)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.05), lineWidth: 1))
    }
}

private struct Notice: View {
    let text: String
    let symbol: String
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol).foregroundStyle(warning ? Color.orange : Color.secondary)
            Text(text).fixedSize(horizontal: false, vertical: true).foregroundStyle(.secondary)
        }.font(.caption).lineSpacing(3)
    }
}
#endif
