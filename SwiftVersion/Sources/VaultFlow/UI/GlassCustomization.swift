// GlassCustomization.swift
// VaultFlow · User-tunable Liquid Glass appearance
//
// The design language used to be a fixed set of constants. This store turns the
// pieces a person actually wants to change — accent, backdrop, glass strength,
// corner softness, density and pane widths — into persisted preferences, so the
// UI bends to the user instead of the other way round.
//
// Values are read live by `VaultTheme`, so every surface follows along. The
// store lives outside `AppModel` because it is purely presentational and is
// seeded before any vault is unlocked.

import SwiftUI
import AppKit

final class GlassCustomization: ObservableObject {
    static let shared = GlassCustomization()

    // MARK: Accent

    enum AccentTheme: String, CaseIterable, Identifiable {
        case aurora = "Aurora"
        case violet = "Violet"
        case mint = "Mint"
        case sunset = "Sunset"
        case rose = "Rose"
        case graphite = "Graphite"

        var id: String { rawValue }

        /// Primary accent: buttons, selection, glow.
        var primary: Color {
            switch self {
            case .aurora: return Color(red: 0.27, green: 0.55, blue: 1.00)
            case .violet: return Color(red: 0.62, green: 0.36, blue: 1.00)
            case .mint: return Color(red: 0.24, green: 0.87, blue: 0.68)
            case .sunset: return Color(red: 1.00, green: 0.55, blue: 0.28)
            case .rose: return Color(red: 0.98, green: 0.42, blue: 0.60)
            case .graphite: return Color(red: 0.72, green: 0.78, blue: 0.88)
            }
        }

        /// Secondary accent: gradients and the second backdrop field.
        var secondary: Color {
            switch self {
            case .aurora: return Color(red: 0.60, green: 0.38, blue: 1.00)
            case .violet: return Color(red: 0.92, green: 0.36, blue: 0.86)
            case .mint: return Color(red: 0.20, green: 0.72, blue: 0.94)
            case .sunset: return Color(red: 0.98, green: 0.34, blue: 0.52)
            case .rose: return Color(red: 0.74, green: 0.36, blue: 0.98)
            case .graphite: return Color(red: 0.52, green: 0.60, blue: 0.74)
            }
        }

        /// Tertiary accent: highlight rims and ribbons.
        var tertiary: Color {
            switch self {
            case .aurora: return Color(red: 0.36, green: 0.90, blue: 1.00)
            case .violet: return Color(red: 0.44, green: 0.70, blue: 1.00)
            case .mint: return Color(red: 0.62, green: 0.94, blue: 0.72)
            case .sunset: return Color(red: 1.00, green: 0.78, blue: 0.38)
            case .rose: return Color(red: 1.00, green: 0.66, blue: 0.78)
            case .graphite: return Color(red: 0.84, green: 0.88, blue: 0.96)
            }
        }

        /// Deep field used behind selected rows so light text stays legible.
        var deep: Color {
            switch self {
            case .aurora: return Color(red: 0.085, green: 0.26, blue: 0.70)
            case .violet: return Color(red: 0.32, green: 0.18, blue: 0.72)
            case .mint: return Color(red: 0.06, green: 0.42, blue: 0.40)
            case .sunset: return Color(red: 0.62, green: 0.24, blue: 0.16)
            case .rose: return Color(red: 0.58, green: 0.14, blue: 0.34)
            case .graphite: return Color(red: 0.22, green: 0.27, blue: 0.36)
            }
        }

        var swatch: LinearGradient {
            LinearGradient(colors: [primary, secondary], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Backdrop

    enum BackdropStyle: String, CaseIterable, Identifiable {
        case aurora = "Aurora"
        case mesh = "Mesh"
        case gradient = "Gradient"
        case solid = "Solid"
        var id: String { rawValue }
    }

    enum GlassMaterial: String, CaseIterable, Identifiable {
        case clear = "Clear"
        case regular = "Frosted"
        var id: String { rawValue }
    }

    enum CornerStyle: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case standard = "Standard"
        case soft = "Soft"
        var id: String { rawValue }

        var scale: CGFloat {
            switch self {
            case .compact: return 0.68
            case .standard: return 1
            case .soft: return 1.38
            }
        }
    }

    enum Density: String, CaseIterable, Identifiable {
        case compact = "Compact"
        case comfortable = "Comfortable"
        case spacious = "Spacious"
        var id: String { rawValue }

        var scale: CGFloat {
            switch self {
            case .compact: return 0.78
            case .comfortable: return 1
            case .spacious: return 1.3
            }
        }
    }

    // MARK: Persisted values

    @Published var accent: AccentTheme {
        didSet { defaults.set(accent.rawValue, forKey: Key.accent) }
    }
    @Published var backdrop: BackdropStyle {
        didSet { defaults.set(backdrop.rawValue, forKey: Key.backdrop) }
    }
    @Published var glassMaterial: GlassMaterial {
        didSet { defaults.set(glassMaterial.rawValue, forKey: Key.material) }
    }
    @Published var corners: CornerStyle {
        didSet { defaults.set(corners.rawValue, forKey: Key.corners) }
    }
    @Published var density: Density {
        didSet { defaults.set(density.rawValue, forKey: Key.density) }
    }
    /// Scales the tint painted behind glass. 1 = the original intensity.
    @Published var glassIntensity: Double {
        didSet { defaults.set(glassIntensity, forKey: Key.intensity) }
    }
    @Published var backdropAnimated: Bool {
        didSet { defaults.set(backdropAnimated, forKey: Key.animated) }
    }
    @Published var showRibbons: Bool {
        didSet { defaults.set(showRibbons, forKey: Key.ribbons) }
    }
    @Published var paneShadows: Bool {
        didSet { defaults.set(paneShadows, forKey: Key.shadows) }
    }
    @Published var sidebarWidth: Double {
        didSet { defaults.set(sidebarWidth, forKey: Key.sidebarWidth) }
    }
    @Published var listWidth: Double {
        didSet { defaults.set(listWidth, forKey: Key.listWidth) }
    }

    // MARK: Derived metrics

    /// Base tint painted under the material, scaled by the user's strength.
    var surfaceTintOpacity: Double { 0.24 * glassIntensity }
    var pagePaddingHorizontal: CGFloat { 26 * density.scale }
    var pagePaddingVertical: CGFloat { 22 * density.scale }
    var paneGap: CGFloat { 12 * density.scale }
    var shellInset: CGFloat { 14 * density.scale }

    // MARK: Lifecycle

    private let defaults: UserDefaults

    private enum Key {
        static let accent = "vf.glass.accent"
        static let backdrop = "vf.glass.backdrop"
        static let material = "vf.glass.material"
        static let corners = "vf.glass.corners"
        static let density = "vf.glass.density"
        static let intensity = "vf.glass.intensity"
        static let animated = "vf.glass.animated"
        static let ribbons = "vf.glass.ribbons"
        static let shadows = "vf.glass.shadows"
        static let sidebarWidth = "vf.layout.sidebarWidth"
        static let listWidth = "vf.layout.listWidth"
    }

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        self.accent = AccentTheme(rawValue: defaults.string(forKey: Key.accent) ?? "") ?? .aurora
        self.backdrop = BackdropStyle(rawValue: defaults.string(forKey: Key.backdrop) ?? "") ?? .aurora
        self.glassMaterial = GlassMaterial(rawValue: defaults.string(forKey: Key.material) ?? "") ?? .regular
        self.corners = CornerStyle(rawValue: defaults.string(forKey: Key.corners) ?? "") ?? .standard
        self.density = Density(rawValue: defaults.string(forKey: Key.density) ?? "") ?? .comfortable
        self.glassIntensity = defaults.object(forKey: Key.intensity) as? Double ?? 1
        self.backdropAnimated = defaults.object(forKey: Key.animated) as? Bool ?? true
        self.showRibbons = defaults.object(forKey: Key.ribbons) as? Bool ?? true
        self.paneShadows = defaults.object(forKey: Key.shadows) as? Bool ?? true
        self.sidebarWidth = defaults.object(forKey: Key.sidebarWidth) as? Double ?? 230
        self.listWidth = defaults.object(forKey: Key.listWidth) as? Double ?? 372
    }

    /// Restore the shipping defaults without touching vault data.
    func reset() {
        accent = .aurora
        backdrop = .aurora
        glassMaterial = .regular
        corners = .standard
        density = .comfortable
        glassIntensity = 1
        backdropAnimated = true
        showRibbons = true
        paneShadows = true
        sidebarWidth = 230
        listWidth = 372
    }
}

// MARK: - Colour blending

extension Color {
    /// Blend two colours in sRGB. Used to tint the backdrop from the accent
    /// without hard-coding a second palette per theme.
    func mixed(with other: Color, _ amount: Double) -> Color {
        let t = min(1, max(0, amount))
        guard let a = NSColor(self).usingColorSpace(.sRGB),
              let b = NSColor(other).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: a.redComponent + (b.redComponent - a.redComponent) * t,
            green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
            blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t
        )
    }
}
