// ClipboardService.swift
// VaultFlow · Clipboard copying with auto-clear and a private history
//
// Mirrors the Python/Java behaviour (30 s auto-clear, only if the clipboard
// still holds our value) and adds an optional in-memory history that never
// touches disk and is wiped on lock.

import Foundation
import AppKit

@MainActor
public final class ClipboardService: ObservableObject {
    public static let shared = ClipboardService()

    /// Seconds before the pasteboard is cleared. 0 disables auto-clear.
    @Published public var clearAfterSeconds: Int = 30
    @Published public private(set) var lastCopiedLabel: String = ""
    @Published public private(set) var secondsRemaining: Int? = nil
    @Published public private(set) var history: [ClipboardHistoryItem] = []
    @Published public var historyEnabled: Bool = false

    private var clearTimer: Timer?
    private var tickTimer: Timer?
    private var lastValue: String?

    public struct ClipboardHistoryItem: Identifiable, Equatable {
        public let id = UUID()
        public let label: String
        public let value: String
        public let date: Date
        public let isSensitive: Bool
    }

    public init() {}

    /// Copies `value` and schedules the timed clear.
    ///
    /// - Parameter restorePrevious: when true the clipboard is put back to its
    ///   previous contents after the timer fires (used for one-time codes).
    public func copy(_ value: String, label: String, sensitive: Bool = true,
                     restorePrevious: Bool = false) {
        let restoreValue = restorePrevious ? NSPasteboard.general.string(forType: .string) : nil
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        lastValue = value
        lastCopiedLabel = label

        if historyEnabled {
            history.insert(ClipboardHistoryItem(label: label, value: value,
                                                date: Date(), isSensitive: sensitive),
                           at: 0)
            if history.count > 25 { history.removeLast(history.count - 25) }
            if history.count % 5 == 0 { expireHistory() }
        }

        scheduleAutoClear(restoring: restoreValue)
    }

    /// Copies, then restores the clipboard to its previous contents.
    public func copyTemporarily(_ value: String, label: String, seconds: Int? = nil) {
        if let seconds { clearAfterSeconds = seconds }
        copy(value, label: label, restorePrevious: true)
    }

    private func scheduleAutoClear(restoring restoreValue: String?) {
        clearTimer?.invalidate()
        tickTimer?.invalidate()
        guard clearAfterSeconds > 0 else { return }
        let copied = lastValue
        clearTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(clearAfterSeconds), repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if NSPasteboard.general.string(forType: .string) == copied {
                    NSPasteboard.general.clearContents()
                    if let restoreValue { NSPasteboard.general.setString(restoreValue, forType: .string) }
                }
                self.lastValue = nil
                self.secondsRemaining = nil
                self.tickTimer?.invalidate()
            }
        }
        startCountdown(clearAfterSeconds)
    }

    private func startCountdown(_ seconds: Int) {
        secondsRemaining = seconds
        tickTimer?.invalidate()
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let remaining = self.secondsRemaining else { return }
                if remaining <= 1 {
                    self.secondsRemaining = nil
                    self.tickTimer?.invalidate()
                } else {
                    self.secondsRemaining = remaining - 1
                }
            }
        }
    }

    public func clearHistory() {
        history.removeAll()
    }

    /// Removes a single entry from the in-memory history.
    public func forget(_ id: UUID) {
        history.removeAll { $0.id == id }
    }

    public func expireHistory(retentionHours: Int = 24) {
        let cutoff = Date().addingTimeInterval(-Double(retentionHours) * 3600)
        history.removeAll { $0.date < cutoff }
    }

    /// Called on lock / quit.
    public func wipe() {
        clearTimer?.invalidate()
        tickTimer?.invalidate()
        history.removeAll()
        lastValue = nil
        lastCopiedLabel = ""
        secondsRemaining = nil
    }
}
