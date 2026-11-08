// OnboardingView.swift
// VaultFlow · First-run experience
//
// Creates a vault, explains the security model, offers biometric quick unlock
// and shows the recovery key exactly once (it can be revealed later from the
// vault menu, since it is wrapped with the master password).

import SwiftUI
import VaultFlowCore

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var step: Int = 0
    @State private var password = ""
    @State private var confirm = ""
    @State private var recoveryKey: String?
    @State private var recoveryConfirmed = false
    @State private var enableQuickUnlock = VaultKeychain.biometryAvailable
    @State private var workFactor: Int = 3
    @State private var migrating = false

    private var strength: StrengthResult { PasswordStrength.evaluate(password) }
    private var passwordsMatch: Bool { !password.isEmpty && password == confirm }
    private var iterations: Int {
        switch workFactor {
        case 0: return 200_000
        case 1: return 350_000
        case 2: return 480_000
        case 3: return 700_000
        default: return 1_000_000
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            hero
                .frame(width: 330)
            VStack(spacing: 0) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(36)
                footer
                    .padding(.horizontal, 36).padding(.bottom, 26)
            }
        }
        .frame(minWidth: 940, minHeight: 620)
    }

    // MARK: Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            ZStack {
                Circle().fill(RadialGradient(colors: [VaultTheme.electric.opacity(0.45), .clear],
                                             center: .center, startRadius: 4, endRadius: 120))
                    .frame(width: 240, height: 240)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 86, weight: .thin))
                    .foregroundStyle(LinearGradient(colors: [.white, VaultTheme.ribbon, VaultTheme.flow],
                                                    startPoint: .topLeading, endPoint: .bottomTrailing))
                    .shadow(color: VaultTheme.electric.opacity(0.8), radius: 22)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("VaultFlow").font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Your passwords, encrypted on this Mac and flowing only where you choose.")
                    .font(.system(size: 13))
                    .foregroundStyle(VaultTheme.subtle)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 9) {
                    featureRow("lock.fill", "AES-256-GCM with PBKDF2-SHA256")
                    featureRow("key.viewfinder", "Passkeys for your eyes: Touch ID quick unlock")
                    featureRow("clock.arrow.circlepath", "Auto-lock, clipboard clearing, breach checks")
                    featureRow("square.and.arrow.down", "Imports the Python & Java VaultFlow vaults")
                }
                .padding(.top, 8)
            }
            Spacer()
        }
        .padding(30)
        .background(
            LinearGradient(colors: [VaultTheme.electric.opacity(0.12), VaultTheme.flow.opacity(0.06)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        )
    }

    private func featureRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VaultTheme.ribbon)
                .frame(width: 16)
            Text(text).font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(stepTitle).font(.system(size: 22, weight: .semibold, design: .rounded))
                Spacer()
                Text("Step \(step + 1) of 3")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(VaultTheme.subtle)
            }

            switch step {
            case 0: createForm
            case 1: recoveryForm
            default: quickUnlockForm
            }
        }
    }

    private var stepTitle: String {
        switch step {
        case 0: return "Create your vault"
        case 1: return "Save your recovery key"
        default: return "Make unlocking effortless"
        }
    }

    private var createForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Everything is encrypted locally. If you forget the master password, nobody — including us — can recover your data without the recovery key.")
                .font(.system(size: 12))
                .foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)

            LabeledField("Master password") {
                SecureField("At least 8 characters", text: $password)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.16)))
            }
            LabeledField("Confirm") {
                SecureField("Repeat the password", text: $confirm)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.white.opacity(0.16)))
            }
            if !password.isEmpty {
                StrengthMeter(result: strength)
                if let warning = strength.warnings.first {
                    Label(warning, systemImage: "exclamationmark.bubble")
                        .font(.system(size: 11)).foregroundStyle(.orange)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Key-derivation work factor").font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(iterations.formatted()) rounds")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(VaultTheme.subtle)
                }
                Slider(value: Binding(get: { Double(workFactor) },
                                      set: { workFactor = Int($0.rounded()) }), in: 0...4, step: 1)
                Text("Higher is safer but unlocking takes longer. 480,000 matches the Python and Java versions.")
                    .font(.system(size: 10.5)).foregroundStyle(VaultTheme.faint)
            }

            Toggle("Enable \(VaultKeychain.biometryLabel == "Password" ? "device authentication" : VaultKeychain.biometryLabel) quick unlock", isOn: $enableQuickUnlock)
                .toggleStyle(.switch)
                .font(.system(size: 12))
                .disabled(!VaultKeychain.biometryAvailable)

            Divider().opacity(0.4)

            Button {
                migrating = true
            } label: {
                Label("I already have a VaultFlow vault (Python / Java)", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(VaultTheme.electric)
        }
    }

    private var recoveryForm: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("This key is the only way back in if you forget your master password. Write it down and keep it somewhere safe — it is shown only during setup, and can be revealed later from the Vault menu.")
                .font(.system(size: 12))
                .foregroundStyle(VaultTheme.subtle)
                .fixedSize(horizontal: false, vertical: true)

            if let recoveryKey {
                Text(recoveryKey)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glass(cornerRadius: 14, tint: VaultTheme.electric)
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(recoveryKey, forType: .string)
                        model.showToast("Recovery key copied — store it offline, then clear your clipboard.")
                    } label: {
                        Label("Copy key", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                    Button {
                        saveKeyToFile(recoveryKey)
                    } label: {
                        Label("Save to file…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(VaultButtonStyle(kind: .secondary))
                    Spacer()
                }
            }

            Toggle("I've stored my recovery key somewhere safe", isOn: $recoveryConfirmed)
                .toggleStyle(.checkbox)
                .font(.system(size: 12.5))
        }
    }

    private var quickUnlockForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Choose your defaults. Every option can be changed later in Settings.")
                .font(.system(size: 12)).foregroundStyle(VaultTheme.subtle)

            VStack(alignment: .leading, spacing: 10) {
                Toggle("Lock after 5 minutes of inactivity", isOn: Binding(
                    get: { model.autoLockPolicyRaw == 5 },
                    set: { model.autoLockPolicyRaw = $0 ? 5 : 15 }))
                Toggle("Lock when the screen sleeps or the Mac sleeps", isOn: $model.lockOnScreenLock)
                Toggle("Copy passwords to the clipboard with a 30-second auto-clear", isOn: .constant(true))
                    .disabled(true)
                Toggle("Check passwords against Have I Been Pwned (k-anonymity)", isOn: $model.breachCheckEnabled)
                Toggle("Keep a clipboard history while unlocked", isOn: $model.clipboardHistoryEnabled)
                Toggle("Show VaultFlow in the menu bar", isOn: $model.showMenuBarExtra)
            }
            .toggleStyle(.switch)
            .font(.system(size: 12.5))

            Spacer()
            Label("Your vault lives at \(model.vaultURL.path). You can move it any time from Settings.",
                  systemImage: "internaldrive")
                .font(.system(size: 11)).foregroundStyle(VaultTheme.faint)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(VaultButtonStyle(kind: .ghost))
            }
            Spacer()
            switch step {
            case 0:
                Button("Create vault") { create() }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(password.count < 8 || !passwordsMatch)
                    .keyboardShortcut(.defaultAction)
            case 1:
                Button("Continue") { step = 2 }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(!recoveryConfirmed)
                    .keyboardShortcut(.defaultAction)
            default:
                Button("Start using VaultFlow") {
                    model.hasCompletedOnboarding = true
                    model.activeSheet = nil
                }
                .buttonStyle(VaultButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func create() {
        model.quickUnlockEnabled = enableQuickUnlock && VaultKeychain.biometryAvailable
        Task {
            if let key = await model.createVault(password: password) {
                withAnimation { recoveryKey = key; step = 1 }
            }
        }
    }

    private func saveKeyToFile(_ key: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "VaultFlow Recovery Key.txt"
        panel.message = "Store this file somewhere safe (not in the vault itself)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let contents = """
        VaultFlow recovery key
        ======================
        \(key)

        Created \(DateFormatter.localizedString(from: Date(), dateStyle: .long, timeStyle: .short))
        Vault location: \(model.vaultURL.path)

        Keep this offline. Anyone with this key and your master password can read the vault.
        """
        try? Data(contents.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        model.showToast("Recovery key saved.")
    }
}
