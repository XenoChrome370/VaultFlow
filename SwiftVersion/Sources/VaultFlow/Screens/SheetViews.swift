// SheetViews.swift
// VaultFlow · Secondary dialogs: clipboard history, recovery key, master
// password, security report, quick search, delete confirmation, Help.

import SwiftUI
import VaultFlowCore

// MARK: - Clipboard history

struct ClipboardHistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var clipboard = ClipboardService.shared
    var embedded: Bool = false

    @State private var revealed: Set<UUID> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.clipboard")
                    .foregroundStyle(VaultTheme.brandGradient)
                Text("Clipboard history")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Button {
                    model.showToast("Clipboard history is wiped when the vault locks.")
                } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).foregroundStyle(VaultTheme.faint)
                Spacer()
                Button {
                    clipboard.clearHistory()
                } label: { Label("Clear", systemImage: "trash") }
                    .disabled(clipboard.history.isEmpty)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            Divider().opacity(0.5)

            if clipboard.history.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "list.clipboard").font(.system(size: 26, weight: .thin))
                        .foregroundStyle(VaultTheme.faint)
                    Text(clipboard.historyEnabled ? "Nothing copied yet" : "History is turned off in Settings")
                        .font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(clipboard.history) { item in
                            historyRow(item)
                        }
                    }
                    .padding(14)
                }
            }
            Divider().opacity(0.5)
            HStack {
                Text("\(clipboard.history.count) entries · auto-clears \(clipboard.clearAfterSeconds)s after copying")
                    .font(.system(size: 10)).foregroundStyle(VaultTheme.faint)
                Spacer()
                if !embedded {
                    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
        }
        .frame(width: embedded ? nil : 560, height: embedded ? nil : 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder
    private func historyRow(_ item: ClipboardService.ClipboardHistoryItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.isSensitive ? "lock.fill" : "text.alignleft")
                .font(.system(size: 10))
                .foregroundStyle(item.isSensitive ? VaultTheme.electric : VaultTheme.subtle)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.label).font(.system(size: 11.5, weight: .medium))
                Text(displayValue(item))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(VaultTheme.subtle)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(item.date.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9.5))
                .foregroundStyle(VaultTheme.faint)
            IconAction(systemImage: "doc.on.doc", help: "Copy again") {
                clipboard.copy(item.value, label: item.label, sensitive: item.isSensitive)
            }
            IconAction(systemImage: "xmark", help: "Forget") {
                clipboard.forget(item.id)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .onTapGesture {
            if item.isSensitive { revealed.insert(item.id) }
        }
    }

    private func displayValue(_ item: ClipboardService.ClipboardHistoryItem) -> String {
        if revealed.contains(item.id) || !item.isSensitive { return item.value }
        return String(repeating: "•", count: min(24, item.value.count))
    }
}

// MARK: - Recovery key

struct RecoveryKeyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var key: String?
    @State private var password = ""
    @State private var regenerated: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lifepreserver").foregroundStyle(VaultTheme.brandGradient)
                Text("Recovery key").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            Text("Your recovery key is an 8-word phrase generated when the vault was created. Keep it somewhere offline — with it you can recover your passwords if you forget the master password.")
                .font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)

            if let key = regenerated ?? key {
                Text(key)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10).fill(VaultTheme.deepNavy.opacity(0.35)))
                    .foregroundStyle(.white)
                HStack {
                    Button {
                        model.copy(key, label: "Recovery key")
                    } label: { Label("Copy", systemImage: "doc.on.doc") }
                        .buttonStyle(VaultButtonStyle(kind: .secondary))
                    Spacer()
                }
            } else {
                Text("VaultFlow stores your recovery key encrypted with your master password. Enter it to view the key.")
                    .font(.system(size: 11)).foregroundStyle(VaultTheme.faint)
            }

            Divider().opacity(0.4)
            Text("Generate a new key").font(.system(size: 11, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
            SecureField("Master password", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await regenerate() } }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Reveal / regenerate") { Task { await reveal() } }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(password.isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            busy = true
            key = await model.recoveryKey()
            busy = false
        }
    }

    private func reveal() async {
        busy = true
        defer { busy = false }
        let revealed = await model.recoveryKey(password: password)
        if let revealed {
            key = revealed
            password = ""
        } else {
            model.showToast("That master password is not correct.", isError: true)
        }
    }

    private func regenerate() async {
        await reveal()
    }
}

// MARK: - Change master password

struct ChangePasswordView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var current = ""
    @State private var newPassword = ""
    @State private var confirm = ""
    @State private var busy = false
    @State private var error: String?

    private var strength: StrengthResult { PasswordStrength.evaluate(newPassword) }

    private var valid: Bool {
        !current.isEmpty && newPassword.count >= 8 && newPassword == confirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "key.horizontal").foregroundStyle(VaultTheme.brandGradient)
                Text("Change master password").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            Text("The vault is re-encrypted with a fresh salt and your new password. This can take a second.")
                .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
            SecureField("Current password", text: $current).textFieldStyle(.roundedBorder)
            SecureField("New password", text: $newPassword).textFieldStyle(.roundedBorder)
            if !newPassword.isEmpty { StrengthMeter(result: strength) }
            SecureField("Confirm new password", text: $confirm).textFieldStyle(.roundedBorder)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }
            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Change password") { Task { await change() } }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(!valid || busy)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func change() async {
        busy = true
        defer { busy = false }
        do {
            try await model.changePassword(current: current, new: newPassword)
            model.showToast("Master password changed.")
            dismiss()
        } catch {
            self.error = "Couldn't change the password: \(error.localizedDescription)"
        }
    }
}

// MARK: - Security report

struct SecurityReportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var report = ""
    @State private var includePasswords = false

    private var suggestions: [String] {
        var lines: [String] = []
        lines.append("VaultFlow security report — \(Date().formatted(date: .abbreviated, time: .shortened))")
        lines.append(String(repeating: "=", count: 52))
        lines.append("Items: \(model.stats.total)   Weak: \(model.stats.weak)   Reused: \(model.stats.reused)")
        lines.append("Without 2FA: \(model.entries.filter { !$0.hasTOTP }.count)   Older than 6 months: \(model.stats.aging)")
        lines.append("")
        var counts: [String: Int] = [:]
        for entry in model.entries where !entry.password.isEmpty { counts[entry.password, default: 0] += 1 }
        for entry in model.entries {
            var flags: [String] = []
            let result = PasswordStrength.evaluate(entry.password)
            if result.isWeak { flags.append("weak (\(result.score.label))") }
            if (counts[entry.password] ?? 0) > 1 { flags.append("reused \(counts[entry.password]!)×") }
            if entry.ageInDays > 180 { flags.append("\(entry.ageInDays / 30) months old") }
            if !entry.hasTOTP { flags.append("no 2FA") }
            guard !flags.isEmpty else { continue }
            var line = "• \(entry.service) (\(entry.username.isEmpty ? "no username" : entry.username)): "
            line += flags.joined(separator: ", ")
            if includePasswords { line += " — password: \(entry.password)" }
            lines.append(line)
        }
        if lines.count <= 5 { lines.append("Nothing to flag. 🎉") }
        return lines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass").foregroundStyle(VaultTheme.brandGradient)
                Text("Security report").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }
            TextEditor(text: $report)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 300)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
            Toggle("Include passwords (only if you really need to)", isOn: $includePasswords)
                .toggleStyle(.checkbox).font(.system(size: 11))
            HStack {
                Button {
                    model.copy(report, label: "Security report", sensitive: includePasswords)
                } label: { Label("Copy report", systemImage: "doc.on.doc") }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 580, height: 480)
        .background {
            ZStack {
                VaultTheme.midnight
                LinearGradient(colors: [VaultTheme.midnight, VaultTheme.deepNavy.opacity(0.9)], startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
        }
        .environment(\.colorScheme, .dark)
        .onAppear { report = suggestions.joined(separator: "\n") }
        .onChange(of: includePasswords) { _, _ in report = suggestions.joined(separator: "\n") }
    }
}

// MARK: - Quick search palette

struct QuickSearchView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var highlighted = 0
    @State private var keyMonitor: Any?
    @FocusState private var focused: Bool

    private var results: [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.isEmpty { return Array(model.entries.sorted { $0.updatedAt > $1.updatedAt }.prefix(8)) }
        return Array(model.entries.filter { $0.searchIndex.contains(trimmed) }.prefix(10))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(VaultTheme.subtle)
                TextField("Search or type to filter…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .focused($focused)
                Text("esc").font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
                    .onTapGesture { dismiss() }
            }
            .padding(12)
            Divider().opacity(0.5)
            if results.isEmpty {
                Text("No matches").font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
                    .frame(maxWidth: .infinity).padding(20)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 10) {
                                ServiceAvatar(service: entry.service, size: 24)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(entry.service).font(.system(size: 12.5, weight: .medium))
                                    Text(entry.username).font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
                                }
                                Spacer()
                                if index == highlighted {
                                    Text("↵ password").font(.system(size: 9)).foregroundStyle(VaultTheme.electric)
                                }
                                IconAction(systemImage: "person", help: "Copy username") {
                                    model.copy(entry.username, label: "\(entry.service) username", sensitive: false)
                                }
                            }
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7)
                                .fill(index == highlighted ? VaultTheme.electric.opacity(0.18) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                highlighted = index
                                commitPassword(for: index)
                            }
                        }
                    }
                    .padding(8)
                }
                footer
            }
        }
        .frame(width: 560, height: 340)
        .darkAppearance()
        .onAppear {
            focused = true
            installKeyMonitor()
        }
        .onDisappear { removeKeyMonitor() }
        .onChange(of: query) { _, _ in highlighted = 0 }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            hint("↵", "password")
            hint("⌘↵", "username")
            hint("⌥↵", "one-time code")
            hint("↑ ↓", "navigate")
            Spacer()
            Text("\(results.count) match\(results.count == 1 ? "" : "es")")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) { Divider().opacity(0.4) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.primary.opacity(0.08)))
            Text(label).font(.system(size: 9.5)).foregroundStyle(VaultTheme.faint)
        }
    }

    /// A local monitor is needed because the focused text field consumes arrow
    /// keys and Return before SwiftUI's `onMoveCommand` / `onSubmit` see them.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            switch event.keyCode {
            case 53: // Escape
                dismiss()
                return nil
            case 125: // ↓
                if !results.isEmpty {
                    highlighted = min(results.count - 1, highlighted + 1)
                }
                return nil
            case 126: // ↑
                if !results.isEmpty {
                    highlighted = max(0, highlighted - 1)
                }
                return nil
            case 36, 76: // Return / keypad Enter
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.option) {
                    commitTOTP(for: highlighted)
                } else if flags.contains(.command) {
                    commitUsername(for: highlighted)
                } else {
                    commitPassword(for: highlighted)
                }
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func commitPassword(for index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        model.copy(entry.password, label: "\(entry.service) password")
        dismiss()
    }

    private func commitUsername(for index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        model.copy(entry.username, label: "\(entry.service) username", sensitive: false)
        dismiss()
    }

    private func commitTOTP(for index: Int) {
        guard results.indices.contains(index) else { return }
        let entry = results[index]
        if entry.hasTOTP {
            model.copyTOTP(for: entry)
            dismiss()
        } else {
            commitPassword(for: index)
        }
    }
}

// MARK: - Delete confirmation

struct DeleteConfirmView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    var entry: Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ServiceAvatar(service: entry.service, size: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Delete “\(entry.service)”?").font(.system(size: 14, weight: .semibold))
                    Text(entry.username.isEmpty ? "No username" : entry.username)
                        .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                }
            }
            Text("This removes the item from your vault. Backups of the encrypted file are kept, but restoring one loses newer changes.")
                .font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Delete") {
                    model.deleteEntry(entry)
                    dismiss()
                }
                .buttonStyle(VaultButtonStyle(kind: .destructive))
            }
        }
        .padding(20)
        .frame(width: 400)
    }
}

// MARK: - Help / what's new

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Feature: Identifiable {
        let id = UUID()
        let icon: String
        let title: String
        let detail: String
    }

    private let features: [Feature] = [
        .init(icon: "lock.shield.fill", title: "AES-256-GCM vaults",
              detail: "Every field — passwords, notes, custom fields, TOTP secrets — is encrypted with a key derived from your master password (PBKDF2-HMAC-SHA256, 480,000 rounds). The file is authenticated, so tampering is detected, not silently accepted."),
        .init(icon: "square.and.arrow.down", title: "Reads its older siblings",
              detail: "Open the vault files written by the Python (Fernet) and Java (AES-256-GCM) versions. VaultFlow decrypts them, keeps unknown fields intact and re-encrypts on save."),
        .init(icon: "sparkles", title: "Generator with passphrases",
              detail: "Characters, BIP-39 passphrases and PINs, with ambiguous-character filtering, guaranteed character classes, live entropy and batch mode."),
        .init(icon: "binoculars.fill", title: "Watchtower",
              detail: "A health score built from weak, reused and ageing passwords, missing two-factor and Have I Been Pwned breach checks that never send your password anywhere."),
        .init(icon: "touchid", title: "Touch ID quick unlock",
              detail: "Optionally store the vault key in the login keychain behind user presence — biometrics or the device password."),
        .init(icon: "clock.badge.checkmark", title: "One-time passwords",
              detail: "Add TOTP secrets and watch the 30-second code count down right in the inspector. Copied codes restore your previous clipboard automatically."),
        .init(icon: "command", title: "Global quick search",
              detail: "Press ⌃⌥⌘L (configurable) anywhere to copy a password without leaving the app you're in."),
        .init(icon: "rectangle.on.rectangle", title: "Menu bar + auto-lock",
              detail: "Keep VaultFlow in the menu bar, lock on sleep or screen lock, and let the vault lock itself after a configurable idle period."),
        .init(icon: "square.and.arrow.up", title: "Import & export",
              detail: "CSV (1Password, Bitwarden, Chrome, Keychain) and JSON import, CSV/JSON/plain-text export with a plain-text warning and 0600 file permissions.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("What's new in VaultFlow")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                Spacer()
                Text("Version \(AppInfo.version)")
                    .font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(features) { feature in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 13))
                                .foregroundStyle(VaultTheme.brandGradient)
                                .frame(width: 22)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feature.title).font(.system(size: 12, weight: .semibold))
                                Text(feature.detail)
                                    .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .padding(20)
            }
            Divider().opacity(0.5)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 560, height: 520)
    }
}
