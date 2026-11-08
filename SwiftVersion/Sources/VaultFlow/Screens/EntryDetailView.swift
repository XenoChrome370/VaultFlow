// EntryDetailView.swift
// VaultFlow · Inspector for the selected item

import SwiftUI
import VaultFlowCore

struct EntryDetailView: View {
    @EnvironmentObject private var model: AppModel
    var entry: Entry

    @State private var revealed = false
    @State private var authenticate = false

    private var strength: StrengthResult { PasswordStrength.evaluate(entry.password) }
    private var configuration: TOTPConfiguration? { TOTPConfiguration.parse(entry.totpSecret) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                passwordCard
                if entry.hasTOTP { totpCard }
                detailsCard
                if !entry.customFields.isEmpty { customFieldsCard }
                if !entry.notes.isEmpty { notesCard }
                footer
            }
            .vaultPagePadding()
        }
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .id(entry.id)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 14) {
            ServiceAvatar(service: entry.service, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.service)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .textSelection(.enabled)
                HStack(spacing: 6) {
                    if !entry.username.isEmpty {
                        Text(entry.username).font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
                    } else {
                        Text("No username").font(.system(size: 12)).foregroundStyle(VaultTheme.faint)
                    }
                    Text("·").foregroundStyle(VaultTheme.faint)
                    VaultBadge(text: entry.folder, systemImage: "folder")
                    if !entry.tags.isEmpty {
                        ForEach(entry.tags.prefix(3), id: \.self) { tag in
                            VaultBadge(text: tag, systemImage: "number", tint: VaultTheme.flow)
                        }
                    }
                }
            }
            Spacer()
            HStack(spacing: 4) {
                IconAction(systemImage: entry.favorite ? "star.fill" : "star",
                           help: entry.favorite ? "Remove from favorites" : "Add to favorites",
                           tint: entry.favorite ? .yellow : VaultTheme.subtle) {
                    model.toggleFavorite(entry)
                }
                IconAction(systemImage: "square.on.square", help: "Duplicate") { model.duplicate(entry) }
                IconAction(systemImage: "square.and.pencil", help: "Edit") { model.activeSheet = .editEntry(entry) }
                IconAction(systemImage: "trash", help: "Delete", tint: .red) {
                    model.activeSheet = .deleteConfirmation(entry)
                }
            }
        }
    }

    // MARK: Password

    private var passwordCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(revealed ? entry.password : masked(entry.password))
                    .font(.system(size: 17, weight: .semibold,
                                  design: revealed ? .monospaced : .rounded))
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .animation(.none, value: revealed)
                Spacer()
                Button {
                    if model.requireAuthToReveal && !revealed {
                        Task {
                            let ok = await VaultKeychain.authenticate(reason: "Reveal password for \(entry.service)")
                            if ok { revealed = true }
                        }
                    } else {
                        revealed.toggle()
                    }
                } label: {
                    Image(systemName: revealed ? "eye.slash" : "eye")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.borderless)
                .help(revealed ? "Hide password" : "Reveal password")

                Button {
                    model.copy(entry.password, label: "\(entry.service) password")
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(VaultButtonStyle(kind: .primary))
            }
            StrengthMeter(result: strength)
            if let warning = strength.warnings.first {
                Label(warning, systemImage: "exclamationmark.bubble")
                    .font(.system(size: 11)).foregroundStyle(.orange)
            }
            Divider().opacity(0.4)
            HStack(spacing: 14) {
                metaChip("Created", dateText(entry.createdAt))
                metaChip("Updated", dateText(entry.updatedAt))
                metaChip("Length", "\(entry.password.count) chars")
                if entry.password.count > 0 {
                    metaChip("Reused", reusedText)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16)
    }

    private var reusedText: String {
        let same = model.entries.filter { $0.password == entry.password }.count
        return same > 1 ? "\(same)×" : "no"
    }

    private func metaChip(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title.uppercased()).font(.system(size: 8.5, weight: .bold)).foregroundStyle(VaultTheme.faint)
            Text(value).font(.system(size: 11.5, weight: .medium))
        }
    }

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func masked(_ value: String) -> String {
        guard !value.isEmpty else { return "—" }
        return String(repeating: "•", count: min(18, max(8, value.count)))
    }

    // MARK: One-time passwords

    private var totpCard: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = configuration.map { TOTP.code(for: $0, at: context.date) } ?? "------"
            let remaining = configuration.map { TOTP.secondsRemaining(for: $0, at: context.date) } ?? 0
            let period = configuration?.period ?? 30
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.primary.opacity(0.12), lineWidth: 3.5)
                    Circle()
                        .trim(from: 0, to: max(0.001, Double(remaining) / Double(period)))
                        .stroke(VaultTheme.ringGradient, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.9), value: remaining)
                    Text("\(remaining)")
                        .font(.system(size: 11, weight: .bold).monospacedDigit())
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("ONE-TIME PASSWORD")
                        .font(.system(size: 8.5, weight: .bold)).foregroundStyle(VaultTheme.faint)
                    Text(TOTP.formatted(code))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .textSelection(.enabled)
                }
                Spacer()
                Button {
                    let plain = code.replacingOccurrences(of: " ", with: "")
                    if model.totpCopyToClipboard {
                        ClipboardService.shared.copyTemporarily(plain, label: "\(entry.service) code")
                        model.showToast("Code copied — restores clipboard in \(ClipboardService.shared.clearAfterSeconds)s")
                    } else {
                        model.copy(plain, label: "\(entry.service) code")
                    }
                } label: {
                    Label("Copy code", systemImage: "number.square")
                }
                .buttonStyle(VaultButtonStyle(kind: .secondary))
            }
            .padding(14)
            .glass(cornerRadius: 16, tint: VaultTheme.flow)
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Details")
            if !entry.username.isEmpty {
                detailRow("Username", entry.username, copyable: true) {
                    model.copy(entry.username, label: "\(entry.service) username", sensitive: false)
                }
            }
            if !entry.url.isEmpty {
                detailRow("Website", entry.url, copyable: true) {
                    model.copy(entry.url, label: "Website", sensitive: false)
                } trailing: {
                    if let url = URL(string: entry.url.hasPrefix("http") ? entry.url : "https://\(entry.url)") {
                        IconAction(systemImage: "safari", help: "Open in browser", tint: VaultTheme.electric) {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            detailRow("Folder", entry.folder)
            if !entry.tags.isEmpty {
                HStack(spacing: 6) {
                    Text("Tags").font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle).frame(width: 74, alignment: .leading)
                    ForEach(entry.tags, id: \.self) { tag in
                        VaultBadge(text: tag, systemImage: "number", tint: VaultTheme.flow)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16)
    }

    private func detailRow<T: View>(_ title: String, _ value: String, copyable: Bool = false,
                                    action: @escaping () -> Void = {},
                                    @ViewBuilder trailing: () -> T = { EmptyView() }) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle)
                .frame(width: 74, alignment: .leading)
            Text(value)
                .font(.system(size: 12.5))
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            trailing()
            if copyable {
                IconAction(systemImage: "doc.on.doc", help: "Copy \(title.lowercased())", action: action)
            }
        }
    }

    private var customFieldsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Custom fields")
            ForEach(entry.customFields) { field in
                HStack(spacing: 8) {
                    Text(field.label)
                        .font(.system(size: 11.5)).foregroundStyle(VaultTheme.subtle)
                        .frame(width: 110, alignment: .leading)
                    Text(field.sensitive ? String(repeating: "•", count: max(6, field.value.count)) : field.value)
                        .font(.system(size: 12.5, design: field.sensitive ? .rounded : .default))
                        .lineLimit(1)
                    Spacer()
                    IconAction(systemImage: "doc.on.doc", help: "Copy field") {
                        model.copy(field.value, label: field.label, sensitive: field.sensitive)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16)
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "Notes")
            Text(entry.notes)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 16)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("Updated \(entry.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
            Spacer()
            if !entry.hasTOTP {
                Button {
                    model.activeSheet = .totpSetup(entry.id)
                } label: { Label("Add one-time password", systemImage: "clock.badge.checkmark") }
                    .buttonStyle(VaultButtonStyle(kind: .ghost))
            }
        }
        .padding(.top, 2)
    }
}
