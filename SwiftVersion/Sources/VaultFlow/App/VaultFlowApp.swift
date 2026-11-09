// VaultFlowApp.swift
// VaultFlow · Application entry point
//
// macOS 26 & 27: built against the macOS 27 SDK, deployment target 26.0, so the
// Liquid Glass materials, refreshed controls and new sidebar/toolbar styling are
// used automatically.
//
// The app is hosted by AppKit rather than by SwiftUI's `App`/`WindowGroup`
// lifecycle: on this toolchain (Swift 6.4 / macOS 27) every `WindowGroup` in
// this binary silently failed to create its window, and any second scene
// (`Settings`, `MenuBarExtra`) either suppressed the main window or crashed the
// runtime during key-path metadata lookup. An `NSWindow` built here plus
// `NSHostingView` gives identical SwiftUI content, a normal titled window,
// SwiftUI keyboard shortcuts (via `onKeyPress`) and a reliable menu bar item.

import SwiftUI
import AppKit
import Combine
import VaultFlowCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel(url: AppDelegate.vaultURLOverride())
    let statusItem = StatusItemController()
    /// NSMenuItem targets are weak, so the actions object must be retained here.
    var mainMenuActions: MainMenuActions?
    private var mainWindow: NSWindow?
    private var isTerminating = false

    /// Test hook: `VF_VAULT_PATH` points the app at a different vault file so
    /// UI verification runs never touch the real vault.
    static func vaultURLOverride() -> URL {
        if let override = ProcessInfo.processInfo.environment["VF_VAULT_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        return VaultSession.defaultVaultURL()
    }

    // MARK: Launch

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.appearance = model.appearance.nsAppearance
        let hotKeys = GlobalHotKeyManager.shared
        hotKeys.handlers[.quickSearch] = { [weak self] in
            self?.model.openQuickSearchFromHotKey()
        }
        hotKeys.handlers[.toggleWindow] = { [weak self] in
            self?.toggleMainWindow()
        }
        hotKeys.install()
        ShortcutStore.shared.onChange = { [weak self] in
            self?.rebuildMainMenu()
        }
        NSApp.mainMenu = MainMenuBuilder.build(model: model, delegate: self)
    }

    /// Re-applies user-configurable key equivalents to the AppKit main menu.
    func rebuildMainMenu() {
        NSApp.mainMenu = MainMenuBuilder.build(model: model, delegate: self)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        showMainWindow()
        NSApp.activate(ignoringOtherApps: true)
        statusItem.attach(model: model)
        WindowAppearanceEnforcer.shared.start()
        ScreenshotAutomation.runIfRequested()
    }

    // MARK: Main window

    func showMainWindow() {
        if let window = mainWindow {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "VaultFlow"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 940, height: 620)
        window.backgroundColor = NSColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("VaultFlowMainWindow")
        window.appearance = model.appearance.nsAppearance
        window.tabbingMode = .disallowed

        let host = NSHostingView(rootView: RootView().environmentObject(model))
        host.frame = window.contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        window.delegate = self

        if !window.setFrameUsingName("VaultFlowMainWindow") {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        mainWindow = window
        WindowRegistry.track(window)
    }

    // MARK: Menu actions (from MainMenuBuilder / MainMenuActions)

    func presentMainWindow() {
        showMainWindow()
    }

    func toggleMainWindow() {
        if let window = mainWindow, window.isKeyWindow {
            window.close()
        } else {
            showMainWindow()
        }
    }

    func openSettingsSheet() {
        showMainWindow()
        model.activeSheet = .settings
    }

    func applyAppearance() {
        NSApp.appearance = model.appearance.nsAppearance
        mainWindow?.appearance = model.appearance.nsAppearance
    }

    // MARK: NSApplicationDelegate

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        isTerminating = true
        GlobalHotKeyManager.shared.uninstall()
        model.lock(reason: "quit")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard !isTerminating else { return }
        // Closing the window keeps the vault unlocked; it is locked by the
        // auto-lock timer, on sleep, or on quit.
    }
}

// MARK: - Window bookkeeping

@MainActor
enum WindowRegistry {
    static var tracked: [NSWindow] = []

    static weak var referenceWindow: NSWindow?

    static func track(_ window: NSWindow) {
        guard !tracked.contains(where: { $0 === window }) else { return }
        tracked.append(window)
        referenceWindow = window
    }

    static func presentMainWindow() {
        (NSApp.delegate as? AppDelegate)?.presentMainWindow()
    }
}

// MARK: - Sheet appearance

/// SwiftUI presents `.sheet` content in a window of its own, which does not
/// inherit `NSApp.appearance`, so force the appearance on every panel that
/// appears while our main window is up.
@MainActor
final class WindowAppearanceEnforcer {
    static let shared = WindowAppearanceEnforcer()
    private var observers: [NSObjectProtocol] = []

    func start() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didBecomeMainNotification]
        for name in names {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.apply() }
            })
        }
    }

    func apply() {
        let appearance = (NSApp.delegate as? AppDelegate)?.model.appearance.nsAppearance ?? NSApp.appearance ?? NSAppearance(named: .darkAqua) ?? NSAppearance.currentDrawing()
        for window in NSApp.windows where !Self.isSystemChrome(window) {
            window.appearance = appearance
            window.backgroundColor = NSColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
        }
    }

    /// AppKit hosts the menu bar item, menus and tooltips in windows of their
    /// own — they are members of `NSApp.windows` too. Painting our background
    /// and appearance on them draws an opaque block behind the menu bar icon.
    private static func isSystemChrome(_ window: NSWindow) -> Bool {
        systemChromeLevels.contains(window.level.rawValue)
    }

    private static let systemChromeLevels: Set<Int> = [
        NSWindow.Level.mainMenu.rawValue,
        NSWindow.Level.statusBar.rawValue,
        NSWindow.Level.popUpMenu.rawValue,
        NSWindow.Level.screenSaver.rawValue,
    ]
}

// MARK: - Menu bar item

/// The menu bar item, hosted by AppKit.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private weak var model: AppModel?
    private var lockCancellable: AnyCancellable?
    private var menuBarCancellable: AnyCancellable?
    private var isRefreshing = false

    func attach(model: AppModel) {
        if self.model == nil {
            self.model = model
            // Keep the icon in sync with the lock state — a small but useful
            // signal that the vault is open.
            lockCancellable = model.$lockState.sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateIcon() }
            }
            // Subscribe to the preference itself. Observing every UserDefaults
            // change re-entered this controller while AppKit restored the
            // status item's autosave state, overflowing the stack.
            menuBarCancellable = model.$showMenuBarExtra.sink { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshVisibility() }
            }
        }
        refreshVisibility()
    }

    func refreshVisibility() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let shouldShow = model?.showMenuBarExtra ?? true
        guard shouldShow else {
            statusItem?.isVisible = false
            return
        }
        let item = ensureStatusItem()
        item.isVisible = true
        if ProcessInfo.processInfo.environment["VF_DEBUG_STATUS"] != nil {
            NSLog("VFDBG refresh show=\(shouldShow) item=\(item) visible=\(item.isVisible)")
        }
    }

    private func ensureStatusItem() -> NSStatusItem {
        if let statusItem { return statusItem }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // Cache before anything re-entrant: `setAutosaveName` restores the
        // saved visibility synchronously and writes to UserDefaults.
        statusItem = item
        // Remember where the user ⌘-drags the icon, so macOS keeps it in view
        // (items near the notch are the first the system tucks away).
        if ProcessInfo.processInfo.environment["VF_NO_AUTOSAVE"] == nil {
            item.autosaveName = "VaultFlowStatusItem"
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        item.button?.imagePosition = .imageOnly
        item.button?.imageScaling = .scaleProportionallyDown
        item.button?.setAccessibilityLabel("VaultFlow")
        updateIcon()
        return item
    }

    private func updateIcon() {
        guard let item = statusItem, let model else { return }
        let unlocked = model.lockState == .unlocked
        let symbol = unlocked ? "lock.open.fill" : "lock.shield.fill"
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "VaultFlow")?
            .withSymbolConfiguration(configuration)
            ?? NSImage(systemSymbolName: "lock.fill", accessibilityDescription: "VaultFlow")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = unlocked ? "VaultFlow — unlocked" : "VaultFlow — locked"
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let model else { return }
        if model.lockState == .unlocked {
            let count = model.entries.count
            menu.addItem(withTitle: "VaultFlow — \(count) item\(count == 1 ? "" : "s")", action: nil, keyEquivalent: "")
            menu.addItem(.separator())
            for entry in model.entries.sorted(by: { $0.updatedAt > $1.updatedAt }).prefix(5) {
                let item = NSMenuItem(title: "Copy password · \(entry.service)", action: #selector(copyPassword(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = entry.id
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let quick = ShortcutStore.shared.effectiveBinding(for: .quickSearch)
            menu.addItem(action("Quick Search…", #selector(quickSearch), quick.key, quick.modifiers))
            menu.addItem(action("Show VaultFlow", #selector(showWindow), "1"))
            menu.addItem(action("Lock Vault", #selector(lockVault), "l", [.command, .control]))
            menu.addItem(.separator())
            menu.addItem(action("Hide Menu Bar Icon", #selector(hideIcon)))
        } else {
            menu.addItem(action("Unlock VaultFlow…", #selector(showWindow)))
            menu.addItem(action("Show Menu Bar Icon", #selector(showIcon)))
        }
        menu.addItem(.separator())
        menu.addItem(action("Settings…", #selector(openSettings), ","))
        menu.addItem(action("Quit VaultFlow", #selector(quit), "q"))
    }

    private func action(_ title: String, _ selector: Selector, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = self
        return item
    }

    @objc private func copyPassword(_ sender: NSMenuItem) {
        guard let model, let id = sender.representedObject as? UUID,
              let entry = model.entries.first(where: { $0.id == id }) else { return }
        model.copyTemporarily(entry.password, label: "\(entry.service) password")
    }

    @objc private func quickSearch() { model?.openQuickSearchFromHotKey() }
    @objc private func showWindow() { WindowRegistry.presentMainWindow() }
    @objc private func lockVault() { model?.lock(reason: "menu bar") }
    @objc private func hideIcon() { model?.showMenuBarExtra = false }
    @objc private func showIcon() { model?.showMenuBarExtra = true }
    @objc private func openSettings() { (NSApp.delegate as? AppDelegate)?.openSettingsSheet() }
    @objc private func quit() { NSApp.terminate(nil) }
}

// MARK: - Development helper

/// Renders VaultFlow's own windows to PNG files so the UI can be inspected
/// without screen-recording permission. Enable with, for example:
///
///     VF_SNAPSHOT_DIR=/tmp/shots VF_SNAPSHOT_STEPS=3,7 ./VaultFlow.app/Contents/MacOS/VaultFlow
///
/// Each comma-separated step snaps every visible window after that many seconds.
enum ScreenshotAutomation {
    private static var timer: Timer?
    private static var folder: URL?
    private static var steps: [Double] = []
    private static var index = 0
    private static var startedAt = Date()

    static func runIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard let directory = environment["VF_SNAPSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        folder = url
        steps = (environment["VF_SNAPSHOT_STEPS"] ?? "3")
            .split(separator: ",")
            .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        startedAt = Date()
        index = 0
        let t = Timer(timeInterval: 0.25, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        log("started steps=\(steps)")
        if let script = environment["VF_SNAPSHOT_SCRIPT"] {
            runScript(script, in: url)
        }
    }

    /// Runs a comma-separated list of `delay:action` steps, e.g.
    /// `2:quickSearch,4:lock`. Used to capture screens that need interaction
    /// when screen-recording permission is unavailable.
    private static func runScript(_ script: String, in folder: URL) {
        for command in script.split(separator: ",") {
            let parts = command.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let delay = Double(parts[0]) else { continue }
            let action = String(parts[1]).trimmingCharacters(in: .whitespaces)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                guard let delegate = NSApp.delegate as? AppDelegate else { return }
                let model = delegate.model
                log("action \(action)")
                switch action {
                case "quickSearch": model.openQuickSearch()
                case "lock": model.lock(reason: "script")
                case "generator": model.destination = .generator
                case "watchtower": model.destination = .watchtower
                case "history": model.destination = .history
                case "settings": delegate.openSettingsSheet()
                case "newEntry": model.activeSheet = .addEntry(service: "")
                case "favorites": model.destination = .favorites
                case "closeSheets": model.activeSheet = nil
                case "createVault":
                    Task {
                        if let key = await model.createVault(password: "vaultflow-demo-2026") {
                            log("recovery key: \(key)")
                        } else {
                            log("createVault failed: toast=\(String(describing: model.toast?.message)) path=\(model.vaultURL.path)")
                        }
                    }
                case "unlock":
                    Task { await model.unlock(with: "vaultflow-demo-2026") }
                case "seed":
                    Task { await seedDemoVault(model: model) }
                case "selectFirst": model.selectedEntryID = model.entries.first?.id
                case "report": model.activeSheet = .securityReport
                case "recoveryKey": model.activeSheet = .recoveryKey
                case "changePassword": model.activeSheet = .changePassword
                case "import": model.activeSheet = .importVault
                case "export": model.activeSheet = .exportVault
                case "migrate": model.activeSheet = .migrate
                case let importer where importer.hasPrefix("importFile:"):
                    let path = String(importer.dropFirst("importFile:".count))
                    Task {
                        do {
                            let data = try await Data(contentsOf: URL(fileURLWithPath: path))
                            let records = try PasswordImporter.parseCSV(String(decoding: data, as: UTF8.self))
                            let count = await model.importRecords(records)
                            log("imported \(count) records: " + records.map { "\($0.service)/\($0.username)/\($0.password)/tags=\($0.tags)" }.joined(separator: " ; "))
                        } catch { log("import failed: \(error.localizedDescription)") }
                    }
                case let m where m.hasPrefix("migrateFile:"):
                    let rest = m.dropFirst("migrateFile:".count)
                    let parts = rest.split(separator: "|", maxSplits: 1)
                    if parts.count == 2 {
                        let path = String(parts[0])
                        let password = String(parts[1])
                        Task {
                            do {
                                let kind = try await model.migrateVault(from: URL(fileURLWithPath: path), password: password)
                                log("migrated kind=\(kind.title) entries=\(model.entries.count) services=\(model.folders.sorted())")
                                log("sample: " + model.entries.prefix(4).map { "\($0.service)/\($0.username)/\($0.password)" }.joined(separator: " ; "))
                            } catch {
                                log("migrate failed: \(error.localizedDescription)")
                            }
                        }
                    }
                case let exporter where exporter.hasPrefix("exportFile:"):
                    let path = String(exporter.dropFirst("exportFile:".count))
                    Task {
                        do {
                            let document = try await model.exportDocument(services: nil)
                            let json = try VaultExporter.json(document)
                            try json.write(to: URL(fileURLWithPath: path))
                            log("exported \(document.count) entries to \(path)")
                        } catch { log("export failed: \(error.localizedDescription)") }
                    }
                case "help": model.activeSheet = .changelog
                case "clipboardHistory": model.activeSheet = .clipboardHistory
                case "totp":
                    if let entry = model.entries.first(where: { $0.hasTOTP }) ?? model.entries.first {
                        model.selectedEntryID = entry.id
                        model.activeSheet = .totpSetup(entry.id)
                    }
                case "editFirst":
                    if let entry = model.entries.first { model.activeSheet = .editEntry(entry) }
                case "search": model.focusSearch()
                case "deleteFirst":
                    if let entry = model.entries.first { model.activeSheet = .deleteConfirmation(entry) }
                case let selector where selector.hasPrefix("select:"):
                    model.selectedEntryID = UUID(uuidString: String(selector.dropFirst(7)))
                default: break
                }
            }
        }
    }

    /// Fills the unlocked vault with representative demo entries so every
    /// screen can be inspected.
    @MainActor
    static func seedDemoVault(model: AppModel) async {
        guard model.entries.isEmpty else { return }
        let today = Date()
        let samples: [(String, String, String, String, String, [String], Int, String)] = [
            ("GitHub", "octocat", "Tr0ub4dor&3-horse", "https://github.com", "work", ["dev", "ssh"], 2, "JBSWY3DPEHPK3PXP"),
            ("Apple ID", "william@icloud.com", "correct horse battery staple", "https://appleid.apple.com", "personal", ["apple"], 40, ""),
            ("Bank of America", "william.yao", "Summer2023!", "https://bankofamerica.com", "finance", ["finance"], 210, ""),
            ("Proton Mail", "wyao", "q7#Lk2!vR9@xPz", "https://proton.me", "personal", ["email"], 15, ""),
            ("Netflix", "william@icloud.com", "netflix123", "https://netflix.com", "social", ["media"], 320, ""),
            ("AWS Console", "vaultflow-admin", "Kd82!mQz#5rTvL0p", "https://aws.amazon.com", "work", ["dev", "cloud"], 30, ""),
            ("X / Twitter", "wyao", "correct horse battery staple", "https://x.com", "social", ["media"], 90, ""),
            ("1Password Legacy", "old-account", "changeme", "https://1password.com", "personal", ["legacy"], 600, ""),
        ]
        for (service, username, password, url, folder, tags, daysAgo, totp) in samples {
            var entry = Entry(service: service, username: username, password: password)
            entry.url = url
            entry.folder = folder
            entry.tags = tags
            entry.totpSecret = totp
            entry.notes = "Imported from the demo vault.\nRotated on request."
            entry.createdAt = Calendar.current.date(byAdding: .day, value: -daysAgo * 2, to: today) ?? today
            entry.updatedAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: today) ?? today
            _ = await model.addEntry(entry)
        }
        if let first = model.entries.first(where: { $0.service == "GitHub" }) {
            model.selectedEntryID = first.id
        }
    }

    private static func tick() {
        guard let folder, index < steps.count else {
            timer?.invalidate(); timer = nil
            return
        }
        let now = Date().timeIntervalSince(startedAt)
        guard now >= steps[index] else { return }
        index += 1
        let windows = NSApp.windows.filter { $0.isVisible && $0.contentView != nil && $0.frame.width > 300 && $0.frame.height > 200 }
        for (offset, window) in windows.enumerated() {
            let name = windows.count > 1 ? String(format: "shot-%02d-%d.png", index, offset + 1) : String(format: "shot-%02d.png", index)
            snapshot(window, to: folder.appendingPathComponent(name))
        }
        log("step \(index) elapsed=\(String(format: "%.1f", now)) windows=\(NSApp.windows.count) eligible=\(windows.count)")
    }

    private static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }

    private static func log(_ message: String) {
        guard let folder else { return }
        let path = folder.appendingPathComponent("log.txt")
        let line = message + "\n"
        if let handle = try? FileHandle(forWritingTo: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: path, atomically: true, encoding: .utf8)
        }
    }
}

// MARK: - Process entry point

/// Entry point. `@main struct … : App` is deliberately not used (see the file
/// header); `MainActor.assumeIsolated` is safe here because `NSApplication.run`
/// executes on the main thread.
@main
struct VaultFlowMain {
    static func main() {
        MainActor.assumeIsolated {
            let app = NSApplication.shared
            let delegate = AppDelegate()
            app.delegate = delegate
            app.run()
        }
    }
}
