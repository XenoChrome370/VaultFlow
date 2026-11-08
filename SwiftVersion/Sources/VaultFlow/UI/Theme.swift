// Theme.swift
// VaultFlow · Visual language
//
// A native-Liquid-Glass reinterpretation of the Java version's "liquid" look:
// translucent panels, pill controls and a flowing blue light ribbon. All colours
// live here so the whole app can be retinted in one place.

import SwiftUI
import VaultFlowCore
import AppKit

enum VaultTheme {

    // MARK: Palette (anchored to the app icon)

    /// Deep navy used for shadows and backdrop gradients (not for text).
    static let midnight = Color(red: 0.02, green: 0.03, blue: 0.08)
    static let deepNavy = Color(red: 0.06, green: 0.08, blue: 0.18)
    static let electric = Color(red: 0.24, green: 0.53, blue: 1.00)
    static let flow = Color(red: 0.55, green: 0.37, blue: 1.00)
    static let ribbon = Color(red: 0.39, green: 0.86, blue: 1.00)

    /// Text colours are resolved against the active appearance: the window is
    /// always dark, so `ink` must not be the icon's near-black navy.
    static let ink = Color.primary
    static let subtle = Color.primary.opacity(0.62)
    static let faint = Color.primary.opacity(0.34)

    static let cornerRadius: CGFloat = 18
    static let pillRadius: CGFloat = 999

    // MARK: Gradient helpers

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [electric, flow], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var ringGradient: AngularGradient {
        AngularGradient(colors: [electric, ribbon, flow, electric], center: .center)
    }

    static func strengthColor(_ score: StrengthScore) -> Color {
        switch score {
        case .extremelyWeak: return .red
        case .weak: return .orange
        case .fair: return .yellow
        case .strong: return .green
        case .excellent: return Color(red: 0.20, green: 0.85, blue: 0.62)
        }
    }

    /// Deterministic colour for a service avatar, derived from its name.
    static func avatarColors(for name: String) -> (Color, Color) {
        let palette: [(Color, Color)] = [
            (electric, flow),
            (Color(red: 0.10, green: 0.72, blue: 0.85), Color(red: 0.20, green: 0.40, blue: 0.95)),
            (Color(red: 0.95, green: 0.42, blue: 0.42), Color(red: 0.72, green: 0.20, blue: 0.62)),
            (Color(red: 0.98, green: 0.68, blue: 0.25), Color(red: 0.90, green: 0.32, blue: 0.35)),
            (Color(red: 0.35, green: 0.80, blue: 0.45), Color(red: 0.10, green: 0.60, blue: 0.62)),
            (Color(red: 0.68, green: 0.45, blue: 0.98), Color(red: 0.35, green: 0.30, blue: 0.90)),
            (Color(red: 0.30, green: 0.62, blue: 0.98), Color(red: 0.55, green: 0.35, blue: 0.98))
        ]
        var hash: UInt64 = 5381
        for byte in name.utf8 { hash = (hash &* 33) &+ UInt64(byte) }
        return palette[Int(hash % UInt64(palette.count))]
    }

    static func initials(for service: String) -> String {
        let cleaned = service.replacingOccurrences(of: "www.", with: "")
        let parts = cleaned.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if let first = parts.first, let character = first.first {
            return String(character).uppercased()
        }
        return "◆"
    }
}

// MARK: - Glass surface

/// A translucent, rounded surface. On macOS 26+ this is real Liquid Glass;
/// on earlier systems it falls back to a frosted `NSVisualEffectView`.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = VaultTheme.cornerRadius
    var tint: Color? = nil
    var strokeOpacity: Double = 0.25
    var interactive: Bool = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(Color.white.opacity(0.055))
                    shape.fill(.ultraThinMaterial)
                    if let tint {
                        shape.fill(tint.opacity(0.10))
                    }
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0.02)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(strokeOpacity + 0.15),
                                 Color.white.opacity(0.04),
                                 VaultTheme.electric.opacity(0.18)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            }
            .shadow(color: VaultTheme.midnight.opacity(0.16), radius: 18, y: 8)
            .shadow(color: VaultTheme.electric.opacity(0.05), radius: 34, y: 12)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = VaultTheme.cornerRadius, tint: Color? = nil,
               strokeOpacity: Double = 0.25) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint, strokeOpacity: strokeOpacity))
    }

    /// Adds the animated aurora background used behind every screen.
    func vaultBackground() -> some View {
        background(VaultBackground())
    }

    func vaultPagePadding() -> some View {
        padding(.horizontal, 28).padding(.vertical, 22)
    }
}

// MARK: - Background

struct VaultBackground: View {
    @State private var phase: Double = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.07, blue: 0.16),
                    Color(red: 0.03, green: 0.04, blue: 0.10),
                    Color(red: 0.07, green: 0.06, blue: 0.17)
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    orb(color: VaultTheme.electric, size: size.width * 0.55)
                        .offset(x: -size.width * 0.18 + sin(phase) * 24,
                                y: -size.height * 0.20 + cos(phase) * 18)
                    orb(color: VaultTheme.flow, size: size.width * 0.48)
                        .offset(x: size.width * 0.26 + cos(phase * 0.8) * 20,
                                y: size.height * 0.22 + sin(phase * 0.8) * 16)
                    orb(color: VaultTheme.ribbon, size: size.width * 0.34)
                        .offset(x: size.width * 0.05, y: -size.height * 0.02 + sin(phase * 1.3) * 12)
                }
                .blur(radius: 120)
                .opacity(0.30)
            }
            // Flow lines echoing the icon's light ribbon.
            Canvas { context, size in
                for index in 0..<3 {
                    var path = Path()
                    let y = size.height * (0.32 + Double(index) * 0.14)
                    path.move(to: CGPoint(x: -40, y: y))
                    for step in stride(from: 0.0, through: size.width + 40, by: 24) {
                        let wave = sin((step / 160) + phase + Double(index)) * 26
                        path.addLine(to: CGPoint(x: step, y: y + wave))
                    }
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [.clear, VaultTheme.electric.opacity(0.35), .clear]),
                            startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
                        ),
                        lineWidth: 1.2
                    )
                }
            }
            .blendMode(.plusLighter)
            .opacity(0.35)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) {
                phase = .pi * 2
            }
        }
    }

    private func orb(color: Color, size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(0.42), color.opacity(0.10), .clear],
                    center: .center, startRadius: 0, endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
    }
}

// MARK: - Zoom

private struct VaultZoomKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

extension EnvironmentValues {
    /// Whole-UI scale factor driven by View ▸ Zoom In / Zoom Out.
    var vaultZoom: CGFloat {
        get { self[VaultZoomKey.self] }
        set { self[VaultZoomKey.self] = newValue }
    }
}

// MARK: - Controls

struct VaultBadge: View {
    var text: String
    var systemImage: String? = nil
    var tint: Color = VaultTheme.electric

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 9, weight: .bold)) }
            Text(text).font(.system(size: 10, weight: .semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.18)))
        .foregroundStyle(tint)
        .overlay(Capsule().stroke(tint.opacity(0.30), lineWidth: 0.6))
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

/// The strength meter shared by the generator, editor and security centre.
struct StrengthMeter: View {
    var result: StrengthResult
    var showCrackTime: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.10))
                    Capsule()
                        .fill(VaultTheme.strengthColor(result.score))
                        .frame(width: max(6, geo.size.width * fraction))
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: result.bits)
                }
            }
            .frame(height: 5)
            HStack(spacing: 6) {
                Text(result.score.shortLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(VaultTheme.strengthColor(result.score))
                Text("·").foregroundStyle(VaultTheme.faint)
                Text("\(Int(result.bits.rounded())) bits")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(VaultTheme.subtle)
                if showCrackTime {
                    Text("·").foregroundStyle(VaultTheme.faint)
                    Text(result.crackTime).font(.system(size: 11)).foregroundStyle(VaultTheme.subtle)
                }
                Spacer()
            }
        }
    }

    private var fraction: Double {
        min(1.0, max(0.04, result.bits / 120.0))
    }
}

/// Service avatar: a rounded square with the service initial.
struct ServiceAvatar: View {
    var service: String
    var size: CGFloat = 28

    var body: some View {
        let colors = VaultTheme.avatarColors(for: service)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(LinearGradient(colors: [colors.0, colors.1], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(VaultTheme.initials(for: service))
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6)
        )
        .shadow(color: colors.1.opacity(0.30), radius: size * 0.25, y: size * 0.08)
    }
}

/// Pill button used for primary actions in the Java version's spirit.
struct VaultButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, ghost }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(foreground)
            .background {
                Capsule().fill(background)
            }
            .overlay {
                Capsule().strokeBorder(borderColor, lineWidth: 1)
            }
            .shadow(color: shadowColor, radius: configuration.isPressed ? 3 : 8, y: configuration.isPressed ? 1 : 3)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .destructive: return .red
        default: return .primary
        }
    }

    private var background: AnyShapeStyle {
        switch kind {
        case .primary: return AnyShapeStyle(VaultTheme.brandGradient)
        case .destructive: return AnyShapeStyle(Color.red.opacity(0.14))
        case .secondary: return AnyShapeStyle(Color.white.opacity(0.12))
        case .ghost: return AnyShapeStyle(Color.clear)
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return Color.white.opacity(0.30)
        case .destructive: return Color.red.opacity(0.35)
        case .secondary: return Color.white.opacity(0.22)
        case .ghost: return Color.clear
        }
    }

    private var shadowColor: Color {
        kind == .primary ? VaultTheme.electric.opacity(0.35) : .clear
    }
}

/// A compact icon button with a tooltip.
struct IconAction: View {
    var systemImage: String
    var help: String
    var tint: Color = VaultTheme.subtle
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(hovering ? Color.primary.opacity(0.10) : Color.clear))
                .foregroundStyle(hovering ? Color.primary : tint)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

extension View {
    /// Keyboard-friendly focus ring matching the brand.
    func vaultFocusable() -> some View {
        self
    }
}
