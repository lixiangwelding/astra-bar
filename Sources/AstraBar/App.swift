#if os(macOS)
import AppKit
import SwiftUI
import Combine
import ServiceManagement
import UsageCore

@MainActor
final class UsageStore: ObservableObject {
    @Published var snapshot: UsageSnapshot?
    @Published var error: String?
    @Published var settingsError: String?
    @Published var busy = false
    @Published var now = Date()
    @Published var source: UsageSource
    @Published var selectedID: String {
        didSet { UserDefaults.standard.set(selectedID, forKey: "selectedBucket") }
    }
    private var lastAttempt = Date.distantPast
    private var timer: Timer?
    var selected: QuotaBucket? { snapshot?.selected(preferredID: selectedID) }
    var title: String { StatusText.title(bucket: selected, source: source, failed: error != nil, now: now) }
    var isStale: Bool { error != nil || (selected?.isStale(at: now) ?? true) }

    init() {
        source = UsageSource(rawValue: UserDefaults.standard.string(forKey: "source") ?? "live") ?? .live
        selectedID = UserDefaults.standard.string(forKey: "selectedBucket") ?? ""
    }
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.now = Date()
                if self.now.timeIntervalSince(self.lastAttempt) >= 60 { self.refresh() }
            }
        }
    }
    func refresh() {
        guard !busy else { return }
        busy = true; lastAttempt = Date()
        let mode = source
        let customCLI = UserDefaults.standard.string(forKey: "codexExecutable")
        let customLogs = UserDefaults.standard.string(forKey: "sessionsDirectory")
        Task {
            let result = await Task.detached(priority: .utility) {
                Result<UsageSnapshot, Error> {
                    if mode == .localLogs {
                        let directory = customLogs.map { URL(fileURLWithPath: $0) } ?? LogReader.defaultDirectory
                        return try LogReader.read(directory: directory)
                    }
                    guard let executable = CodexClient.executable(custom: customCLI) else { throw UsageError.noCLI }
                    return try CodexClient.fetch(executable: executable)
                }
            }.value
            busy = false; now = Date()
            switch result {
            case .success(let value): snapshot = value; error = nil
            case .failure(let value): error = (value as? UsageError)?.localizedDescription ?? "读取失败，请稍后刷新。"
            }
        }
    }
    func changeSource(_ newSource: UsageSource) {
        guard !busy else { return }
        source = newSource
        UserDefaults.standard.set(newSource.rawValue, forKey: "source")
        snapshot = nil; error = nil
        refresh()
    }
    func choosePath(directory: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = directory ? "选择 Codex 的 sessions 文件夹" : "选择 codex 可执行程序"
        panel.canChooseDirectories = directory; panel.canChooseFiles = !directory
        panel.allowsMultipleSelection = false; panel.showsHiddenFiles = true
        panel.directoryURL = directory ? LogReader.defaultDirectory.deletingLastPathComponent() : CodexClient.executable()?.deletingLastPathComponent()
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !directory && !FileManager.default.isExecutableFile(atPath: url.path) {
            settingsError = "请选择可执行文件，而不是文件夹或 .app。"; return
        }
        UserDefaults.standard.set(url.path, forKey: directory ? "sessionsDirectory" : "codexExecutable")
        snapshot = nil; error = nil; settingsError = nil; refresh()
    }
    func resetPaths() {
        guard !busy else { return }
        UserDefaults.standard.removeObject(forKey: "codexExecutable")
        UserDefaults.standard.removeObject(forKey: "sessionsDirectory")
        snapshot = nil; error = nil; refresh()
    }
    func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
            settingsError = nil
        } catch { settingsError = "登录启动设置未生效。请先把应用放入“应用程序”，并在系统设置中检查登录项。" }
        objectWillChange.send()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = UsageStore()
    private var item: NSStatusItem!
    private let popover = NSPopover()
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.50percent", accessibilityDescription: "额度")
            button.imagePosition = .imageLeading
            button.target = self; button.action = #selector(togglePopover)
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 360, height: 570)
        popover.contentViewController = NSHostingController(rootView: Dashboard(store: store))
        observation = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        updateStatus(); store.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wokeUp), name: NSWorkspace.didWakeNotification, object: nil)
        // Explicit UI verification mode; captures only this app's visible view, never the desktop.
        if CommandLine.arguments.contains("--smoke") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { self.togglePopover() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) {
                if let index = CommandLine.arguments.firstIndex(of: "--capture"), CommandLine.arguments.count > index + 1 {
                    self.captureView(path: CommandLine.arguments[index + 1])
                }
                print("ASTRABAR_UI_SMOKE_OK statusItem=\(self.item.button != nil) popover=\(self.popover.isShown)")
                NSApp.terminate(nil)
            }
        }
    }
    func updateStatus() {
        item?.button?.title = " " + store.title
        item?.button?.toolTip = "AstraBar · \(store.selected?.preferredWindow?.label ?? "额度未获取") · \(store.source.label)"
    }
    @objc func wokeUp() { store.refresh() }
    @objc func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
    private func captureView(path: String) {
        guard let view = popover.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            do { try png.write(to: URL(fileURLWithPath: path), options: .atomic); print("ASTRABAR_CAPTURE_OK") }
            catch { print("ASTRABAR_CAPTURE_FAILED") }
        }
    }
}

@main
@MainActor
enum AstraBarMain {
    static func main() {
        signal(SIGPIPE, SIG_IGN)
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
#else
import Foundation
@main enum AstraBarMain {
    static func main() { print("AstraBar requires macOS 13+. The astra-usage CLI and UsageCore tests also work on Linux.") }
}
#endif
