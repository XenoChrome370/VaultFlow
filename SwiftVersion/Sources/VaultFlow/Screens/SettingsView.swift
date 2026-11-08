// SettingsView.swift
// VaultFlow · Preferences (also reachable as an in-window destination)

import SwiftUI
import VaultFlowCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    var embedded: Bool = false

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General", security = "Security", vault = "Vault", shortcuts = "Shortcuts", about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .security: return "lock.shield"
            case .vault: return "externaldrive"
            case .shortcuts: return "command"
            case .about: return "info.circle"
            }
        }
    }

    @State private var tab: SettingsTab = SettingsView.initialTab

    /// Screenshot automation can jump straight to a tab with `VF_SETTINGS_TAB`.
    private static var initialTab: SettingsTab {
        if let raw = ProcessInfo.processInfo.environment["VF_SETTINGS_TAB"],
           let tab = SettingsTab(rawValue: raw) {
            return tab
        }
        return .general
    }

    var body: some View {
        Group {
            if embedded {
                inWindow
            } else {
                inWindow.frame(width: 640, height: 540)
            }
        }
    }

    private var inWindow: some View {
        HStack(spacing: 0) {
            List(selection: Binding(get: { tab }, set: { if let v = $0 { tab = v } })) {
                ForEach(SettingsTab.allCases) { item in
                    Label(item.rawValue, systemImage: item.icon).tag(item)
                }
            }
            .listStyle(.sidebar)
            .frame(width: 170)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .general: generalTab
                    case .security: securityTab
                    case .vault: vaultTab
                    case .shortcuts: shortcutsTab
                    case .about: aboutTab
                    }
                }
                .vaultPagePadding()
                .frame(maxWidth: 520, alignment: .leading)
            }
        }
        .background(.regularMaterial)
    }

    // MARK: General

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Appearance")
            Picker("Theme", selection: Binding(get: { model.appearance },
                                               set: { model.appearanceRaw = $0.rawValue; model.applyAppearance() })) {
                ForEach(AppModel.Appearance.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Divider().opacity(0.4)
            SectionHeader(title: "Behaviour")
            Toggle("Keep VaultFlow in the menu bar", isOn: $model.showMenuBarExtra)
            Text("If macOS tucks the icon behind the notch, ⌘-drag it toward the clock, or use the » control in the menu bar. You can always re-show it from VaultFlow › Show Menu Bar Icon.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Hide VaultFlow when another app comes forward", isOn: $model.hideOnDeactivate)
            Toggle("Copy one-time codes without restoring the clipboard", isOn: $model.totpCopyToClipboard)
            Text("By default a copied 2FA code is removed from the clipboard when it expires, and your previous clipboard contents are restored.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)
            SectionHeader(title: "Automatic locking", subtitle: "The vault also locks when the app quits.")
            Picker("Lock after inactivity", selection: Binding(
                get: { AutoLockController.Policy(rawValue: model.autoLockPolicyRaw) ?? .fiveMinutes },
                set: { model.autoLockPolicyRaw = $0.rawValue; model.syncAutoLockSettings() })) {
                ForEach(AutoLockController.Policy.allCases) { Text($0.title).tag($0) }
            }
            Toggle("Lock when the screen locks or the Mac sleeps", isOn: Binding(
                get: { model.lockOnScreenLock },
                set: { model.lockOnScreenLock = $0; model.syncAutoLockSettings() }))
            Toggle("Lock when VaultFlow is hidden", isOn: Binding(
                get: { model.lockOnHide },
                set: { model.lockOnHide = $0; model.syncAutoLockSettings() }))
        }
        .toggleStyle(.switch)
        .font(.system(size: 12.5))
    }

    // MARK: Security

    private var securityTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Unlock", subtitle: VaultKeychain.biometryAvailable
                          ? "\(VaultKeychain.biometryLabel) is available on this Mac."
                          : "This Mac has no biometric sensor; device password is still required.")
            Toggle("\(VaultKeychain.biometryLabel) quick unlock", isOn: Binding(
                get: { model.quickUnlockEnabled },
                set: { newValue in
                    model.quickUnlockEnabled = newValue
                    if !newValue { try? VaultKeychain.delete() }
                }))
            .disabled(!VaultKeychain.biometryAvailable)
            Text("Stores only the derived key in the login keychain, protected by user presence. Turning this off deletes it.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)
            SectionHeader(title: "Clipboard")
            HStack {
                Text("Clear copied secrets after")
                Slider(value: Binding(get: { Double(model.clipboardClearSeconds) },
                                      set: { model.clipboardClearSeconds = Int($0.rounded()) }),
                       in: 10...120, step: 5)
                Text("\(model.clipboardClearSeconds)s").monospacedDigit().frame(width: 38)
            }
            Toggle("Keep clipboard history while unlocked", isOn: Binding(
                get: { model.clipboardHistoryEnabled },
                set: { model.clipboardHistoryEnabled = $0; ClipboardService.shared.historyEnabled = $0 }))
            HStack {
                Text("Forget history after")
                Picker("", selection: $model.historyRetentionHours) {
                    Text("1 hour").tag(1); Text("6 hours").tag(6)
                    Text("24 hours").tag(24); Text("Never").tag(0)
                }
                .labelsHidden().frame(width: 110)
            }
            Text("History lives only in memory and is wiped whenever the vault locks or quits.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)

            Divider().opacity(0.4)
            SectionHeader(title: "Checks")
            Toggle("Check passwords against Have I Been Pwned", isOn: $model.breachCheckEnabled)
            Toggle("Require \(VaultKeychain.biometryLabel == "Password" ? "device authentication" : VaultKeychain.biometryLabel) before revealing a password", isOn: $model.requireAuthToReveal)
            Button {
                model.activeSheet = .securityReport
            } label: { Label("Open security report…", systemImage: "doc.text.magnifyingglass") }
                .buttonStyle(VaultButtonStyle(kind: .secondary))
        }
        .toggleStyle(.switch)
        .font(.system(size: 12.5))
    }

    // MARK: Vault

    private var vaultTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "Storage")
            VStack(alignment: .leading, spacing: 4) {
                Text(model.vaultURL.path)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2).truncationMode(.middle)
                HStack(spacing: 8) {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([model.vaultURL])
                    }
                    Button("Backups…") {
                        let folder = model.vaultURL.deletingLastPathComponent()
                        NSWorkspace.shared.open(folder)
                    }
                    Button("Change…") { moveVaultPanel() }
                    Button("Open another…") { model.activeSheet = .importVault }
                }
                .buttonStyle(.link)
                .font(.system(size: 11))
            }

            InfoRow(label: "Cipher", value: "AES-256-GCM (authenticated)")
            InfoRow(label: "Key derivation", value: "PBKDF2-HMAC-SHA256 · 480,000 rounds")
            InfoRow(label: "Backups", value: ".backup-1 … .backup-3 kept automatically")

            Divider().opacity(0.4)
            SectionHeader(title: "Master password")
            HStack(spacing: 8) {
                Button {
                    model.activeSheet = .changePassword
                } label: { Label("Change master password…", systemImage: "key.horizontal") }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                Button {
                    model.activeSheet = .recoveryKey
                } label: { Label("Recovery key…", systemImage: "lifepreserver") }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
            }

            Divider().opacity(0.4)
            SectionHeader(title: "Migration")
            Text("Import a vault created by the Python (Fernet) or Java (AES-GCM) versions — VaultFlow detects the format and re-encrypts it as AES-256-GCM on first save.")
                .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            let discovered = VaultMigration.discoverLegacyVaults(
                projectRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            if !discovered.isEmpty {
                ForEach(discovered, id: \.path) { url in
                    HStack {
                        Image(systemName: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                        Text(url.path).font(.system(size: 10.5, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button("Open") { model.activeSheet = .importVault }
                            .buttonStyle(.link)
                    }
                    .font(.system(size: 11))
                }
            }
            Button {
                model.activeSheet = .importVault
            } label: { Label("Import from file…", systemImage: "square.and.arrow.down") }
                .buttonStyle(VaultButtonStyle(kind: .secondary))
                .disabled(model.lockState != .unlocked)
        }
        .font(.system(size: 12.5))
        .toggleStyle(.switch)
    }

    // MARK: Shortcuts

    @StateObject private var shortcuts = ShortcutStore.shared

    private var shortcutsTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            SectionHeader(title: "Global hotkeys",
                          subtitle: "Work from any app, even when VaultFlow is in the background.")
            ForEach(GlobalHotKeyAction.allCases) { action in
                VStack(alignment: .leading, spacing: 7) {
                    Text(action.title).font(.system(size: 12.5, weight: .semibold))
                    Text(action.subtitle)
                        .font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                    GlobalHotKeyRecorder(action: action)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.primary.opacity(0.04)))
            }
            Text("A combination that macOS or another app already owns shows as unavailable; pick another one.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
                .fixedSize(horizontal: false, vertical: true)

            Divider().opacity(0.4)

            HStack(alignment: .firstTextBaseline) {
                SectionHeader(title: "In-app shortcuts",
                              subtitle: "Click a key combination, then press the new one. Delete clears it.")
                Spacer()
                Button("Restore defaults") { shortcuts.resetAll() }
                    .buttonStyle(VaultButtonStyle(kind: .ghost))
            }

            if !shortcuts.conflictingActions.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("Some shortcuts share the same keys: "
                         + shortcuts.conflictingActions.map(\.shortTitle).sorted().joined(separator: ", ")
                         + ". Only the first action will fire.")
                        .font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.10)))
            }

            ForEach(ShortcutCategory.allCases) { category in
                VStack(alignment: .leading, spacing: 7) {
                    Text(category.rawValue.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .tracking(1.2)
                        .foregroundStyle(VaultTheme.faint)
                    ForEach(shortcuts(in: category), id: \.self) { action in
                        HStack(spacing: 8) {
                            Text(action.shortTitle).font(.system(size: 12))
                            Spacer(minLength: 8)
                            ShortcutRecorder(action: action)
                        }
                        if action != shortcuts(in: category).last {
                            Divider().opacity(0.25)
                        }
                    }
                }
            }

            Text("Menu bar shortcuts update as soon as you change them; no restart needed.")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
        }
    }

    private func shortcuts(in category: ShortcutCategory) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { $0.category == category }
    }

    // MARK: About

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ServiceAvatar(service: "VaultFlow", size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("VaultFlow").font(.system(size: 20, weight: .bold, design: .rounded))
                    Text("Version \(AppInfo.version) · Build \(AppInfo.build)")
                        .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                }
            }
            Text("A native macOS password manager built for macOS 26 and 27. It reads vaults created by the Python (PyQt5) and Java (Swing) versions of VaultFlow and stores everything in a single AES-256-GCM file.")
                .font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            InfoRow(label: "Bundle", value: "com.vaultflow.macos")
            InfoRow(label: "Compatibility", value: "Python Fernet vaults · Java AES-GCM vaults · plaintext legacy files · CSV / JSON exports")
            HStack(spacing: 8) {
                Button {
                    model.activeSheet = .changelog
                } label: { Label("What's new", systemImage: "sparkles") }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                Button {
                    NSWorkspace.shared.open(model.vaultURL.deletingLastPathComponent())
                } label: { Label("Show data folder", systemImage: "folder") }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
            }
        }
    }

    private func moveVaultPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use this folder"
        panel.message = "VaultFlow will move its encrypted vault into the selected folder."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let target = folder.appendingPathComponent("vault.json")
        if FileManager.default.fileExists(atPath: target.path) {
            model.showToast("A vault already exists there.", isError: true)
            return
        }
        do {
            try FileManager.default.moveItem(at: model.vaultURL, to: target)
            model.showToast("Vault moved.")
        } catch {
            model.showToast("Couldn't move the vault: \(error.localizedDescription)", isError: true)
        }
    }
}

struct InfoRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label).font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle).frame(width: 110, alignment: .leading)
            Text(value).font(.system(size: 11.5)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0"
    }
    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}
