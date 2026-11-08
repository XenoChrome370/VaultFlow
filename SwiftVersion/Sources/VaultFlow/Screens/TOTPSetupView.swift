// TOTPSetupView.swift
// VaultFlow · Add a one-time password to an item

import SwiftUI
import VaultFlowCore

struct TOTPSetupView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var entryID: UUID

    @State private var input = ""
    @State private var issuer = ""
    @State private var account = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var algorithm: TOTPConfiguration.Algorithm = .sha1
    @State private var error: String?

    private var entry: Entry? { model.entries.first { $0.id == entryID } }

    private var parsed: TOTPConfiguration? {
        if let configuration = TOTPConfiguration.parse(input) { return configuration }
        return nil
    }

    private var preview: String {
        guard let parsed else { return "— — —" }
        return TOTP.formatted(TOTP.code(for: parsed))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "clock.badge.checkmark").foregroundStyle(VaultTheme.brandGradient)
                Text("Add one-time password")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
                if let entry {
                    Text(entry.service).font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                }
            }
            Text("Paste the secret your provider shows next to the QR code, or a full otpauth:// URL. The secret is stored encrypted with the rest of the vault.")
                .font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)

            TextField("otpauth://totp/… or JBSWY3DPEHPK3PXP", text: $input)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

            HStack(spacing: 16) {
                LabeledField("Digits") {
                    Picker("", selection: $digits) {
                        Text("6").tag(6); Text("7").tag(7); Text("8").tag(8)
                    }.labelsHidden().frame(width: 70)
                }
                LabeledField("Period") {
                    Picker("", selection: $period) {
                        Text("30 s").tag(30); Text("60 s").tag(60)
                    }.labelsHidden().frame(width: 80)
                }
                LabeledField("Algorithm") {
                    Picker("", selection: $algorithm) {
                        ForEach(TOTPConfiguration.Algorithm.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.labelsHidden().frame(width: 90)
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Text("Preview").font(.system(size: 10.5, weight: .semibold)).foregroundStyle(VaultTheme.subtle)
                Text(preview)
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                    .foregroundStyle(parsed == nil ? VaultTheme.faint : VaultTheme.electric)
            }
            if let parsed {
                InfoRow(label: "Issuer", value: parsed.issuer.isEmpty ? "—" : parsed.issuer)
                InfoRow(label: "Account", value: parsed.account.isEmpty ? "—" : parsed.account)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11)).foregroundStyle(.red)
            }

            HStack {
                if entry?.hasTOTP == true {
                    Button("Remove one-time password", role: .destructive) {
                        if var entry { entry.totpSecret = ""; model.updateEntry(entry) }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear {
            if let secret = entry?.totpSecret, !secret.isEmpty { input = secret }
        }
        .onChange(of: input) { _, _ in syncFields() }
    }

    private func syncFields() {
        guard let parsed else { return }
        issuer = parsed.issuer.isEmpty ? issuer : parsed.issuer
        account = parsed.account.isEmpty ? account : parsed.account
        digits = parsed.digits
        period = parsed.period
        algorithm = parsed.algorithm
    }

    private func save() {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret: String
        if trimmed.lowercased().hasPrefix("otpauth://") {
            secret = trimmed
        } else {
            // A bare Base32 secret: keep the tuned digits/period/algorithm.
            let label = [issuer, account].filter { !$0.isEmpty }.joined(separator: ":")
            var components = URLComponents()
            components.scheme = "otpauth"
            components.host = "totp"
            components.path = "/" + (label.isEmpty ? "VaultFlow" : label)
            components.queryItems = [
                URLQueryItem(name: "secret", value: trimmed.replacingOccurrences(of: " ", with: "").uppercased()),
                URLQueryItem(name: "digits", value: String(digits)),
                URLQueryItem(name: "period", value: String(period)),
                URLQueryItem(name: "algorithm", value: algorithm.rawValue)
            ]
            secret = components.string ?? trimmed
        }
        guard TOTPConfiguration.parse(secret) != nil else {
            error = "That doesn't look like a valid TOTP secret."
            return
        }
        guard var entry else { return }
        entry.totpSecret = secret
        if !issuer.isEmpty, entry.notes.isEmpty { entry.notes = issuer }
        model.updateEntry(entry)
        dismiss()
    }
}
