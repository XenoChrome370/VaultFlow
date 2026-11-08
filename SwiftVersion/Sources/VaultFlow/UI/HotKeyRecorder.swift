// HotKeyRecorder.swift
// VaultFlow · Shortcut recorders used by Settings
//
// Two flavours: a global (system-wide) recorder backed by Carbon hotkeys, and an
// in-app recorder that writes into `ShortcutStore`.

import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The clickable pill that shows a shortcut and starts recording when tapped.
struct KeyCapsule: View {
    var text: String
    var recording: Bool
    var isConflict: Bool = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(recording ? VaultTheme.electric.opacity(0.18) : Color.primary.opacity(0.06))
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(recording ? VaultTheme.electric
                              : (isConflict ? Color.orange : Color.primary.opacity(0.12)),
                              lineWidth: 1)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(recording ? VaultTheme.electric : .primary)
                .lineLimit(1)
        }
        .frame(height: 30)
        .frame(minWidth: 92, maxWidth: 180)
        .contentShape(Rectangle())
    }
}

// MARK: - Global hotkeys

struct GlobalHotKeyRecorder: View {
    let action: GlobalHotKeyAction
    @StateObject private var manager = GlobalHotKeyManager.shared
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            KeyCapsule(text: recording ? "Press keys…" : manager.definition(for: action).displayString,
                       recording: recording)
                .onTapGesture { recording ? stopRecording() : startRecording() }

            Button(recording ? "Cancel" : "Record") { recording ? stopRecording() : startRecording() }
                .buttonStyle(VaultButtonStyle(kind: .secondary))

            Button("Reset") {
                stopRecording()
                manager.resetToDefault(action)
            }
            .buttonStyle(VaultButtonStyle(kind: .ghost))

            Spacer(minLength: 0)

            Circle()
                .fill(manager.isRegistered(action) ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(manager.isRegistered(action) ? "Active" : "Unavailable")
                .font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
                .help(manager.isRegistered(action)
                      ? "This shortcut is registered with the system."
                      : "macOS or another app is already using this combination.")
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // Require a real modifier so the shortcut can't swallow typing.
            let meaningful = flags.intersection([.command, .option, .control])
            guard !meaningful.isEmpty else { return nil }
            let definition = HotKeyDefinition(
                keyCode: UInt32(event.keyCode),
                carbonModifiers: HotKeyDefinition.carbonModifiers(from: flags),
                displayString: "")
            manager.setDefinition(definition, for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

// MARK: - In-app shortcuts

struct ShortcutRecorder: View {
    let action: ShortcutAction
    @StateObject private var store = ShortcutStore.shared
    @State private var recording = false
    @State private var monitor: Any?

    private var binding: KeyCombo { store.binding(for: action) }
    private var isConflict: Bool { store.conflictingActions.contains(action) }

    var body: some View {
        HStack(spacing: 4) {
            KeyCapsule(text: recording ? "Press keys…" : binding.displayString,
                       recording: recording, isConflict: isConflict)
                .onTapGesture { recording ? stopRecording() : startRecording() }

            Button {
                stopRecording()
                store.reset(action)
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(VaultTheme.subtle)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Restore the default shortcut")
            .opacity(binding == action.defaultCombo ? 0 : 1)
            .disabled(binding == action.defaultCombo)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        guard monitor == nil else { return }
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            // Delete with no modifiers clears the shortcut.
            if event.keyCode == UInt16(kVK_Delete),
               flags.intersection([.command, .option, .control]).isEmpty {
                store.setBinding(.none, for: action)
                stopRecording()
                return nil
            }
            let meaningful = flags.intersection([.command, .option, .control])
            guard !meaningful.isEmpty,
                  let characters = event.charactersIgnoringModifiers,
                  !characters.isEmpty else { return nil }
            store.setBinding(KeyCombo(key: characters, modifiers: flags), for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
