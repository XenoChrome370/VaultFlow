// ZoomLevel.swift
// VaultFlow · Whole-UI zoom (View ▸ Zoom In / Zoom Out / Actual Size)

import SwiftUI

/// Drives the window-wide scale factor so the interface stays comfortable on
/// large displays without changing the system settings.
@MainActor
final class ZoomLevel: ObservableObject {
    static let shared = ZoomLevel()

    static let steps: [CGFloat] = [0.8, 0.9, 1.0, 1.1, 1.2, 1.35, 1.5]

    @Published private(set) var index: Int = {
        let stored = UserDefaults.standard.double(forKey: "vf.zoomLevel")
        return stored == 0 ? 2 : (steps.firstIndex(of: CGFloat(stored)) ?? 2)
    }()

    var scale: CGFloat { Self.steps[index] }
    var percentLabel: String { "\(Int((scale * 100).rounded()))%" }

    func step(_ delta: Int) {
        let next = min(Self.steps.count - 1, max(0, index + delta))
        guard next != index else { return }
        index = next
        persist()
    }

    func reset() {
        index = 2
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(Double(scale), forKey: "vf.zoomLevel")
    }
}
