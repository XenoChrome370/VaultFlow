// MigrationView.swift
// VaultFlow · Open a vault written by the Python or Java versions

import SwiftUI
import UniformTypeIdentifiers
import VaultFlowCore

struct MigrationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var path = ""
    @State private var kind: LegacyVaultKind?
    @State private var password = ""
    @State private var itemCount: Int?
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(VaultTheme.brandGradient)
                Text("Open a legacy vault").font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            Text("Choose passwords.json from the Python version or javaStorage.json from the Java version. VaultFlow detects the format, decrypts it in memory and keeps it as this app's vault from then on.")
                .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Vault file", text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 11, design: .monospaced))
                Button("Choose…") { choose() }
            }

            if let discovered = discoveries, !discovered.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Found nearby").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
                    ForEach(discovered, id: \.path) { url in
                        Button {
                            inspect(url)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc")
                                Text(url.path).lineLimit(1).truncationMode(.middle)
                                    .font(.system(size: 10.5, design: .monospaced))
                            }
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(VaultTheme.electric)
                    }
                }
            }

            if let kind {
                InfoRow(label: "Detected", value: kind.title)
                SecureField("Master password for that vault", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await open() } }
            }
            if let itemCount {
                Label("\(itemCount) items decrypted and ready.", systemImage: "checkmark.seal.fill")
                    .font(.system(size: 11.5)).foregroundStyle(.green)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }

            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Open vault") { Task { await open() } }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(kind == nil || password.isEmpty || busy)
            }
        }
        .padding(20)
        .frame(width: 540)
    }

    private var discoveries: [URL]? {
        VaultMigration.discoverLegacyVaults(
            projectRoot: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json, .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        inspect(url)
    }

    private func inspect(_ url: URL) {
        path = url.path
        itemCount = nil
        error = nil
        password = ""
        guard let data = try? Data(contentsOf: url) else {
            error = "Couldn't read that file."
            return
        }
        kind = VaultMigration.detect(data) ?? .plaintext
    }

    private func open() async {
        guard !path.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let detected = try await model.migrateVault(from: URL(fileURLWithPath: path), password: password)
            kind = detected
            itemCount = model.entries.count
            password = ""
            model.showToast("Opened the \(detected.title) vault.")
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
