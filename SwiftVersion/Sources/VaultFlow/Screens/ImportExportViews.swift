// ImportExportViews.swift
// VaultFlow · Import (CSV / JSON / legacy vaults) and export

import SwiftUI
import UniformTypeIdentifiers
import VaultFlowCore

// MARK: - Import

struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Mode: String, CaseIterable {
        case text = "Paste CSV / JSON"
        case file = "Choose a file"
        case legacy = "Legacy vault"
    }

    @State private var mode: Mode = .text
    @State private var pasted = ""
    @State private var fileURL: URL?
    @State private var records: [ImportedRecord] = []
    @State private var parseError: String?
    @State private var busy = false
    @State private var imported: Int?
    @State private var legacyKind: LegacyVaultKind?
    @State private var legacyPath = ""
    @State private var legacyDocument: VaultDocument?

    // Legacy vault state
    @State private var legacyPassword = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Import").font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()

                    switch mode {
                    case .text: textImport
                    case .file: fileImport
                    case .legacy: legacyImport
                    }

                    if let parseError {
                        Label(parseError, systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11.5)).foregroundStyle(.red)
                    }
                    if imported != nil {
                        Label("Imported \(imported!) item\(imported == 1 ? "" : "s").", systemImage: "checkmark.seal.fill")
                            .font(.system(size: 11.5)).foregroundStyle(.green)
                    }
                    if !records.isEmpty && imported == nil { preview }
                }
                .padding(20)
            }
            Divider().opacity(0.5)
            HStack {
                Text("Accepted: 1Password / Bitwarden / Chrome CSV, Keychain CSV, VaultFlow JSON, Python & Java vault files.")
                    .font(.system(size: 10)).foregroundStyle(VaultTheme.faint)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                if mode != .legacy {
                    Button("Import \(records.count) items") { performImport() }
                        .buttonStyle(VaultButtonStyle(kind: .primary))
                        .disabled(records.isEmpty || busy)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 620, height: 600)
    }

    private var textImport: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste rows with a header line").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
            TextEditor(text: $pasted)
                .font(.system(size: 11, design: .monospaced))
                .frame(height: 220)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
                .onChange(of: pasted) { _, newValue in parse(newValue) }
            Button("Use clipboard contents") {
                if let text = NSPasteboard.general.string(forType: .string) { pasted = text }
            }
            .buttonStyle(.link).font(.system(size: 11))
        }
    }

    private var fileImport: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "doc.badge.arrow.up")
                Text(fileURL?.lastPathComponent ?? "No file chosen")
                    .font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { chooseFile() }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.05)))
        }
    }

    private var legacyImport: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Open a vault file created by the Python, Java or earlier VaultFlow builds. It is decrypted into memory, merged into this vault and re-encrypted here.")
                .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                TextField("Path to vault file", text: $legacyPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                Button("Choose…") { chooseLegacyFile() }
            }
            if let legacyKind {
                InfoRow(label: "Detected", value: legacyKind.title)
            }
            if legacyDocument != nil {
                Label("Vault decrypted — ready to merge.", systemImage: "lock.open.fill")
                    .font(.system(size: 11.5)).foregroundStyle(.green)
                Button("Import into VaultFlow") { Task { await importLegacy() } }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
            } else if legacyKind != nil {
                SecureField("Master password of that vault", text: $legacyPassword)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await decryptLegacy() } }
                Button("Decrypt") { Task { await decryptLegacy() } }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                    .disabled(legacyPassword.isEmpty || busy)
            }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Preview").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
            ForEach(Array(records.prefix(6).enumerated()), id: \.offset) { _, record in
                HStack(spacing: 8) {
                    ServiceAvatar(service: record.service, size: 18)
                    Text(record.service).font(.system(size: 11.5, weight: .medium))
                    Text(record.username).font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                    Spacer()
                    Text(String(repeating: "•", count: min(8, max(3, record.password.count))))
                        .font(.system(size: 10)).foregroundStyle(VaultTheme.faint)
                }
            }
            if records.count > 6 {
                Text("… and \(records.count - 6) more").font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
            }
        }
    }

    // MARK: Actions

    private func parse(_ text: String) {
        parseError = nil
        imported = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { records = []; return }
        do {
            if trimmed.hasPrefix("[") || trimmed.hasPrefix("{") {
                records = try PasswordImporter.parseJSON(Data(trimmed.utf8))
            } else {
                records = try PasswordImporter.parseCSV(trimmed)
            }
        } catch {
            records = []
            parseError = error.localizedDescription
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .json, .plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        fileURL = url
        guard let data = try? Data(contentsOf: url) else { return }
        if url.pathExtension.lowercased() == "json" {
            if let image = try? PasswordImporter.parseJSON(data) {
                records = image
            } else if let text = String(data: data, encoding: .utf8) {
                parse(text)
            }
        } else if let text = String(data: data, encoding: .utf8) {
            parse(text)
        }
    }

    private func chooseLegacyFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = try? Data(contentsOf: url) else { return }
        legacyPath = url.path
        legacyDocument = nil
        legacyPassword = ""
        legacyKind = VaultMigration.detect(data) ?? .plaintext
    }

    private func decryptLegacy() async {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: legacyPath)) else { return }
        busy = true
        defer { busy = false }
        do {
            let unlocked = try VaultMigration.open(data, password: legacyPassword)
            legacyKind = unlocked.kind
            legacyDocument = unlocked.document
            parseError = nil
        } catch {
            parseError = "Couldn't open that vault: \(error.localizedDescription)"
        }
    }

    private func importLegacy() async {
        guard let legacyDocument else { return }
        let records = legacyDocument.allEntries.map { entry in
            ImportedRecord(service: entry.service, username: entry.username, password: entry.password,
                           notes: entry.notes, url: entry.url, folder: entry.folder,
                           tags: entry.tags, totpSecret: entry.totpSecret)
        }
        busy = true
        imported = await model.importRecords(records)
        busy = false
    }

    private func performImport() {
        busy = true
        Task {
            let count = await model.importRecords(records)
            imported = count
            records = []
            busy = false
        }
    }
}

// MARK: - Export

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private enum Format: String, CaseIterable {
        case csv = "CSV"
        case json = "JSON"
        case clipboard = "Plain text"
    }

    @State private var format: Format = .csv
    @State private var includeNotes = true
    @State private var onlyFavorites = false
    @State private var acknowledged = false

    private var selectedEntries: [Entry] {
        onlyFavorites ? model.entries.filter(\.favorite) : model.entries
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("Export vault").font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20).padding(.vertical, 14)
            Divider().opacity(0.5)
            VStack(alignment: .leading, spacing: 14) {
                Picker("Format", selection: $format) {
                    ForEach(Format.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Toggle("Include notes", isOn: $includeNotes).toggleStyle(.checkbox)
                Toggle("Only favorites", isOn: $onlyFavorites).toggleStyle(.checkbox)
                Label("Exports are unencrypted. Delete the file, or clear the clipboard, as soon as you're done.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("I understand this file contains my passwords in plain text", isOn: $acknowledged)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11.5))
            }
            .font(.system(size: 12))
            .padding(20)
            Spacer()
            Divider().opacity(0.5)
            HStack {
                Text("\(selectedEntries.count) items").font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(format == .clipboard ? "Copy" : "Export…") { performExport() }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(!acknowledged || selectedEntries.isEmpty)
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(width: 480, height: 400)
    }

    private func performExport() {
        let entries = selectedEntries
        switch format {
        case .clipboard:
            let text = entries.map { entry in
                "\(entry.service)\n  user: \(entry.username)\n  pass: \(entry.password)" + (includeNotes && !entry.notes.isEmpty ? "\n  notes: \(entry.notes)" : "")
            }.joined(separator: "\n\n")
            model.copy(text, label: "Exported \(entries.count) items")
            dismiss()
        case .csv, .json:
            let panel = NSSavePanel()
            panel.nameFieldStringValue = format == .csv ? "VaultFlow Export.csv" : "VaultFlow Export.json"
            panel.allowedContentTypes = format == .csv ? [.commaSeparatedText] : [.json]
            guard panel.runModal() == .OK, let url = panel.url else { return }
            Task {
                do {
                    let data: Data
                    if format == .csv {
                        data = Data(VaultExporter.csv(entries, includeNotes: includeNotes).utf8)
                    } else {
                        let services = Array(Set(entries.map(\.service)))
                        data = try VaultExporter.json(await model.exportDocument(services: services),
                                                      services: services)
                    }
                    try data.write(to: url, options: .atomic)
                    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
                    model.showToast("Exported to \(url.lastPathComponent)")
                    dismiss()
                } catch {
                    model.showToast("Export failed: \(error.localizedDescription)", isError: true)
                }
            }
        }
    }
}
