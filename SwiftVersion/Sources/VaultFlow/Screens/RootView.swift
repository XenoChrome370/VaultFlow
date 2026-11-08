// RootView.swift
// VaultFlow · Top-level routing between onboarding, unlock and the vault

import SwiftUI
import VaultFlowCore

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var zoom = ZoomLevel.shared

    var body: some View {
        content
            .environment(\.vaultZoom, zoom.scale)
    }

    private var content: some View {
        ZStack {
            VaultBackground()
            switch model.lockState {
            case .needsVault:
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .unlocked:
                MainShellView()
                    .transition(.opacity)
            default:
                UnlockView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: model.lockState)
        .overlay(alignment: .bottom) { ToastHost() }
        .sheet(item: $model.activeSheet) { sheet in
            SheetRouter(sheet: sheet)
                .environmentObject(model)
        }
        // Any mouse click resets the inactivity timer.
        .simultaneousGesture(TapGesture().onEnded { model.registerActivity() })
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshVaultPresence()
        }
        .background(WindowAccessor { window in
            WindowRegistry.track(window)
            if window.canBecomeMain { WindowRegistry.referenceWindow = window }
        })
        // Keyboard shortcuts that belong to the window rather than the menu.
        .onKeyPress(.escape) {
            guard model.activeSheet == nil else { return .ignored }
            if model.searchText.isEmpty { return .ignored }
            model.searchText = ""
            return .handled
        }
    }
}

struct ToastHost: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            if let toast = model.toast {
                HStack(spacing: 8) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(toast.isError ? .orange : Color.green)
                    Text(toast.message).font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .glass(cornerRadius: 999)
                .padding(.bottom, 26)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: toast.id) {
                    try? await Task.sleep(nanoseconds: toast.isError ? 4_200_000_000 : 2_200_000_000)
                    withAnimation { model.toast = nil }
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: model.toast)
    }
}

/// Routes every modal sheet in one place.
struct SheetRouter: View {
    let sheet: AppModel.Sheet
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            switch sheet {
            case .addEntry(let service):
                EntryEditorView(entry: nil, presetService: service)
            case .editEntry(let entry):
                EntryEditorView(entry: entry, presetService: entry.service)
            case .importVault:
                ImportView()
            case .exportVault:
                ExportView()
            case .clipboardHistory:
                ClipboardHistoryView()
            case .recoveryKey:
                RecoveryKeyView()
            case .changePassword:
                ChangePasswordView()
            case .securityReport:
                SecurityReportView()
            case .quickSearch:
                QuickSearchView()
            case .changelog:
                HelpView()
            case .settings:
                SettingsView()
            case .totpSetup(let id):
                TOTPSetupView(entryID: id)
            case .deleteConfirmation(let entry):
                DeleteConfirmView(entry: entry)
            case .migrate:
                MigrationView()
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
        .darkAppearance()
    }
}

/// Forces the hosting window (sheet, panel or popover) into dark appearance and
/// paints the vault backdrop, so sheets match the main window on every system.
private struct WindowAppearanceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                VaultBackground()
            }
            .environment(\.colorScheme, .dark)
            .background(WindowAccessor { window in
                window.appearance = NSAppearance(named: .darkAqua)
                window.backgroundColor = NSColor(red: 0.04, green: 0.05, blue: 0.12, alpha: 1)
            })
    }
}

extension View {
    func darkAppearance() -> some View { modifier(WindowAppearanceModifier()) }
}

/// Sheets are presented in their own window, so they need the vault backdrop
/// and an explicit dark appearance of their own.
struct SheetBackdrop<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .background {
                VaultBackground()
            }
            .environment(\.colorScheme, .dark)
    }
}


/// Reports the hosting `NSWindow` so the app can keep a handle on it without
/// walking `NSApp.windows` from a render pass.
struct WindowAccessor: NSViewRepresentable {
    var onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { onWindow(window) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let window = nsView.window { onWindow(window) } }
    }
}
