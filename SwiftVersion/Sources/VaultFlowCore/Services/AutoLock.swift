// AutoLock.swift
// VaultFlow · Idle- and background-triggered locking

import Foundation
import AppKit

/// Locks the vault after a period of inactivity, on screen lock, or on sleep.
@MainActor
public final class AutoLockController: ObservableObject {
    public static let shared = AutoLockController()

    public enum Policy: Int, CaseIterable, Identifiable, Sendable {
        case never = 0
        case oneMinute = 1
        case fiveMinutes = 5
        case tenMinutes = 10
        case fifteenMinutes = 15
        case thirtyMinutes = 30

        public var id: Int { rawValue }

        public var title: String {
            switch self {
            case .never: return "Never (not recommended)"
            case .oneMinute: return "After 1 minute"
            case .fiveMinutes: return "After 5 minutes"
            case .tenMinutes: return "After 10 minutes"
            case .fifteenMinutes: return "After 15 minutes"
            case .thirtyMinutes: return "After 30 minutes"
            }
        }

        public var interval: TimeInterval? {
            self == .never ? nil : TimeInterval(rawValue * 60)
        }
    }

    @Published public var policy: Policy = .fiveMinutes {
        didSet { restartTimer(); defaults.set(policy.rawValue, forKey: Self.key) }
    }
    @Published public var lockOnScreenLock: Bool = true
    @Published public var lockOnSleep: Bool = true
    @Published public var lockOnHide: Bool = false

    public var onLock: (() -> Void)?

    private var timer: Timer?
    private let defaults = UserDefaults.standard
    static let key = "vf.autoLockPolicy"
    private var observers: [NSObjectProtocol] = []

    public init() {
        if defaults.object(forKey: Self.key) != nil {
            policy = Policy(rawValue: defaults.integer(forKey: Self.key)) ?? .fiveMinutes
        }
        installObservers()
        restartTimer()
    }

    /// Call whenever the user interacts, to reset the idle clock.
    public func registerActivity() {
        guard policy.interval != nil else { return }
        restartTimer()
    }

    private func restartTimer() {
        timer?.invalidate()
        guard let interval = policy.interval else { return }
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.triggerLock("inactivity") }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    private func triggerLock(_ reason: String) {
        onLock?()
    }

    private func installObservers() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lockOnScreenLock else { return }
                self.onLock?()
            }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lockOnSleep else { return }
                self.onLock?()
            }
        })
        observers.append(center.addObserver(forName: NSApplication.didResignActiveNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lockOnHide else { return }
                self.onLock?()
            }
        })
        // Distributed notification posted by the system when the screen is locked.
        let screenLock = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"),
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.lockOnScreenLock else { return }
                self.onLock?()
            }
        }
        distributedObservers.append(screenLock)
    }

    private var distributedObservers: [NSObjectProtocol] = []

    deinit {
        timer?.invalidate()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        for observer in distributedObservers {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
    }
}
