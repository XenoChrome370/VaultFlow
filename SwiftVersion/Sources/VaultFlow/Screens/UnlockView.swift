// UnlockView.swift
// VaultFlow · The locked screen
//
// A focused card with the vault ring, master-password field, Touch ID quick
// unlock (when enabled) and the failed-attempt cooling-off used by the Python
// and Java versions, but with a gentler ramp: 5 attempts, then 1/2/4… s pause.

import SwiftUI
import VaultFlowCore

struct UnlockView: View {
    @EnvironmentObject private var model: AppModel
    @State private var password = ""
    @State private var showPassword = false
    @State private var coolingOff = 0
    @State private var shake = false
    @FocusState private var focused: Bool

    private var lockoutSeconds: Int {
        guard model.failedAttempts >= 5 else { return 0 }
        return min(30, 1 << min(5, model.failedAttempts - 5))
    }

    var body: some View {
        VStack(spacing: 22) {
            vaultRing

            VStack(spacing: 6) {
                Text("VaultFlow").font(.system(size: 30, weight: .bold, design: .rounded))
                Text(model.vaultExists ? "Enter your master password to unlock" : "Vault not found")
                    .font(.system(size: 12.5))
                    .foregroundStyle(VaultTheme.subtle)
            }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill")
                        .foregroundStyle(model.lastUnlockError == nil ? VaultTheme.subtle : Color.orange)
                    Group {
                        if showPassword {
                            TextField("Master password", text: $password)
                        } else {
                            SecureField("Master password", text: $password)
                        }
                    }
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit(submit)
                    .disabled(coolingOff > 0)

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(VaultTheme.subtle)
                    }
                    .buttonStyle(.plain)
                    .help(showPassword ? "Hide password" : "Show password")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .glass(cornerRadius: 14)
                .offset(x: shake ? -8 : 0)
                .animation(.spring(response: 0.18, dampingFraction: 0.3), value: shake)

                HStack(spacing: 8) {
                    Button(action: submit) {
                        HStack(spacing: 6) {
                            if model.lockState == .unlocking {
                                ProgressView().controlSize(.small)
                            }
                            Text(model.lockState == .unlocking ? "Unlocking…" : "Unlock")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(VaultButtonStyle(kind: .primary))
                    .disabled(password.isEmpty || model.lockState == .unlocking || coolingOff > 0)

                    if model.quickUnlockEnabled, VaultKeychain.hasStoredMasterKey() {
                        Button {
                            Task { await model.unlockWithKeychain() }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: VaultKeychain.biometryLabel == "Touch ID"
                                      ? "touchid" : "person.badge.key.fill")
                                Text("Use \(VaultKeychain.biometryLabel)")
                            }
                        }
                        .buttonStyle(VaultButtonStyle(kind: .secondary))
                    }
                }

                if coolingOff > 0 {
                    Label("Too many attempts — try again in \(coolingOff)s", systemImage: "clock.badge.exclamationmark")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.orange)
                } else if let error = model.lastUnlockError {
                    Label(error, systemImage: "xmark.octagon.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 380)

            Divider().frame(width: 240).opacity(0.25)

            HStack(spacing: 16) {
                Button {
                    model.activeSheet = .importVault
                } label: {
                    Label("Open another vault…", systemImage: "folder")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(VaultTheme.subtle)

                Text("•").foregroundStyle(VaultTheme.faint)

                Text(vaultSubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(VaultTheme.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.vaultURL.path)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focused = true }
            coolingOff = lockoutSeconds
            startCooldown()
        }
        .onChange(of: model.failedAttempts) { _, _ in
            password = ""
            shake = true
            withAnimation { shake = false }
            coolingOff = lockoutSeconds
        }
    }

    private var vaultSubtitle: String {
        model.vaultURL.deletingLastPathComponent().lastPathComponent + "/" + model.vaultURL.lastPathComponent
    }

    private func startCooldown() {
        guard coolingOff > 0 else { return }
        Task {
            while coolingOff > 0 {
                try? await Task.sleep(for: .seconds(1))
                coolingOff -= 1
            }
        }
    }

    private func submit() {
        guard !password.isEmpty, coolingOff == 0 else { return }
        let value = password
        password = ""
        Task { await model.unlock(with: value) }
    }

    private var vaultRing: some View {
        ZStack {
            Circle()
                .strokeBorder(VaultTheme.ringGradient.opacity(0.55), lineWidth: 2)
                .frame(width: 108, height: 108)
                .rotationEffect(.degrees(model.lockState == .unlocking ? 360 : 0))
                .animation(model.lockState == .unlocking
                           ? .linear(duration: 1.1).repeatForever(autoreverses: false) : .default,
                           value: model.lockState)
            Circle()
                .fill(RadialGradient(colors: [VaultTheme.electric.opacity(0.35), .clear],
                                     center: .center, startRadius: 2, endRadius: 60))
                .frame(width: 108, height: 108)
            Image(systemName: "lock.fill")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(
                    LinearGradient(colors: [.white, VaultTheme.ribbon],
                                   startPoint: .top, endPoint: .bottom)
                )
                .shadow(color: VaultTheme.electric.opacity(0.7), radius: 12)
        }
        .frame(height: 120)
    }
}
