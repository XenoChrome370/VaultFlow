// Theme.swift
// VaultFlow · Visual language
//
// Liquid Glass, done natively. Every surface is built on the macOS 26 glass
// material (`glassEffect`), so panels, buttons and chrome refract the flowing
// mesh backdrop behind them instead of faking translucency with flat fills.
// All colours, radii and component recipes live here so the whole app can be
// retuned in one place.

import SwiftUI
import VaultFlowCore
import AppKit

enum VaultTheme {

    // MARK: Palette (anchored to the app icon)

    /// Deep space navy used for shadows and the darkest backdrop fields.
    static let midnight = Color(red: 0.012, green: 0.018, blue: 0.042)
    static let deepNavy = Color(red: 0.042, green: 0.060, blue: 0.140)
    static let electric = Color(red: 0.27, green: 0.55, blue: 1.00)
    static let flow = Color(red: 0.60, green: 0.38, blue: 1.00)
    static let ribbon = Color(red: 0.36, green: 0.90, blue: 1.00)
    /// A deeper blue used behind glass so panels stay dark and their labels
    /// keep the system's light-on-dark vibrancy.
    static let royal = Color(red: 0.085, green: 0.26, blue: 0.70)
    static let mint = Color(red: 0.24, green: 0.87, blue: 0.68)
    static let amber = Color(red: 1.00, green: 0.67, blue: 0.26)

    /// Text colours resolve against the active appearance; the window is always
    /// dark, so `ink` must not be the icon's near-black navy.
    static let ink = Color.primary
    static let subtle = Color.primary.opacity(0.66)
    static let faint = Color.primary.opacity(0.36)

    // MARK: Metrics

    /// Corner radii follow macOS 26's concentric shape language.
    static let panelRadius: CGFloat = 24
    static let cardRadius: CGFloat = 16
    static let controlRadius: CGFloat = 12
    static let cornerRadius: CGFloat = cardRadius
    static let pillRadius: CGFloat = 999

    // MARK: Gradient helpers

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [electric, ribbon, flow], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var ringGradient: AngularGradient {
        AngularGradient(colors: [electric, ribbon, flow, electric], center: .center)
    }

    static func strengthColor(_ score: StrengthScore) -> Color {
        switch score {
        case .extremelyWeak: return Color(red: 1.00, green: 0.36, blue: 0.42)
        case .weak: return Color(red: 1.00, green: 0.58, blue: 0.28)
        case .fair: return Color(red: 1.00, green: 0.82, blue: 0.30)
        case .strong: return mint
        case .excellent: return Color(red: 0.22, green: 0.80, blue: 0.98)
        }
    }

    /// Deterministic colour for a service avatar, derived from its name.
    static func avatarColors(for name: String) -> (Color, Color) {
        let palette: [(Color, Color)] = [
            (electric, flow),
            (Color(red: 0.10, green: 0.74, blue: 0.88), Color(red: 0.20, green: 0.40, blue: 0.98)),
            (Color(red: 0.98, green: 0.42, blue: 0.46), Color(red: 0.74, green: 0.20, blue: 0.66)),
            (Color(red: 1.00, green: 0.68, blue: 0.28), Color(red: 0.92, green: 0.30, blue: 0.38)),
            (Color(red: 0.32, green: 0.84, blue: 0.50), Color(red: 0.08, green: 0.62, blue: 0.66)),
            (Color(red: 0.70, green: 0.45, blue: 1.00), Color(red: 0.36, green: 0.28, blue: 0.94)),
            (Color(red: 0.30, green: 0.64, blue: 1.00), Color(red: 0.60, green: 0.34, blue: 0.98))
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

/// A glass slab isolated in a background layer. Keeping the material out of the
/// content subtree matters: on this SDK `glassEffect` applies a vibrancy layer
/// to its children, which can turn white labels black when the backdrop is
/// bright. Used as a background, the glass refracts without touching content.
struct GlassBackdrop<S: Shape>: View {
    var glass: Glass = .regular
    var shape: S
    var tint: Color? = nil
    var tintOpacity: Double = 0.24

    var body: some View {
        ZStack {
            if let tint {
                shape.fill(tint.opacity(tintOpacity))
            }
            shape.fill(Color.white.opacity(0.02))
                .glassEffect(glass, in: shape)
        }
    }
}

/// A native Liquid Glass surface. Content keeps its own colour; the material is
/// applied behind it so it genuinely refracts the mesh backdrop, then a thin
/// specular rim and a soft drop shadow give the pane its physical edge.
struct GlassSurface: ViewModifier {
    var cornerRadius: CGFloat = VaultTheme.cardRadius
    var tint: Color? = nil
    var strokeOpacity: Double = 0.22
    var interactive: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    private var glass: Glass {
        interactive ? .regular.interactive() : .regular
    }

    func body(content: Content) -> some View {
        content
            .background {
                GlassBackdrop(glass: glass, shape: shape, tint: tint, tintOpacity: 0.24)
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(strokeOpacity + 0.12),
                            Color.white.opacity(0.035),
                            (tint ?? VaultTheme.ribbon).opacity(0.16)
                        ],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.9
                )
                .allowsHitTesting(false)
            }
            .shadow(color: VaultTheme.midnight.opacity(0.34), radius: 18, y: 10)
    }
}

extension View {
    func glass(cornerRadius: CGFloat = VaultTheme.cardRadius, tint: Color? = nil,
               strokeOpacity: Double = 0.22, interactive: Bool = false) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint,
                              strokeOpacity: strokeOpacity, interactive: interactive))
    }

    /// The standard floating pane used by the sidebar, item list and detail shell.
    func glassPanel(cornerRadius: CGFloat = VaultTheme.panelRadius,
                    tint: Color? = nil) -> some View {
        modifier(GlassSurface(cornerRadius: cornerRadius, tint: tint,
                              strokeOpacity: 0.26, interactive: false))
    }

    /// Adds the animated aurora background used behind every screen.
    func vaultBackground() -> some View {
        background(VaultBackground())
    }

    func vaultPagePadding() -> some View {
        padding(.horizontal, 26).padding(.vertical, 22)
    }
}

// MARK: - Background

/// A slowly drifting mesh gradient with a few luminous orbs. Large, soft fields
/// of colour give the glass above something worth refracting; the thin flow
/// ribbons echo the app icon without stealing attention.
struct VaultBackground: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 18.0, paused: false)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { geo in
                let size = geo.size
                ZStack {
                    VaultTheme.midnight
                    MeshGradient(width: 3, height: 3, points: points(at: time), colors: palette)
                        .frame(width: size.width, height: size.height)

                    // Luminous fields.
                    orb(color: VaultTheme.electric, diameter: size.width * 0.85, opacity: 0.30)
                        .offset(x: -size.width * 0.30 + sin(time * 0.16) * 30,
                                y: -size.height * 0.30 + cos(time * 0.13) * 24)
                    orb(color: VaultTheme.flow, diameter: size.width * 0.72, opacity: 0.26)
                        .offset(x: size.width * 0.34 + cos(time * 0.11) * 26,
                                y: size.height * 0.26 + sin(time * 0.15) * 22)
                    orb(color: VaultTheme.ribbon, diameter: size.width * 0.46, opacity: 0.18)
                        .offset(x: size.width * 0.02 + sin(time * 0.20) * 18,
                                y: -size.height * 0.04 + cos(time * 0.18) * 16)

                    flowRibbons(time: time)
                        .opacity(0.14)
                        .blendMode(.plusLighter)

                    // Ground the composition and keep chrome legible.
                    LinearGradient(
                        colors: [.clear, VaultTheme.midnight.opacity(0.55)],
                        startPoint: .center, endPoint: .bottom
                    )
                }
                .frame(width: size.width, height: size.height)
                .clipped()
            }
        }
        .ignoresSafeArea()
    }

    private var palette: [Color] {
        [
            VaultTheme.midnight,
            Color(red: 0.055, green: 0.075, blue: 0.180),
            VaultTheme.midnight,
            Color(red: 0.085, green: 0.140, blue: 0.360),
            Color(red: 0.170, green: 0.140, blue: 0.430),
            Color(red: 0.050, green: 0.090, blue: 0.240),
            VaultTheme.midnight,
            Color(red: 0.070, green: 0.180, blue: 0.380),
            Color(red: 0.020, green: 0.030, blue: 0.080)
        ]
    }

    /// The four edge midpoints and the centre gently orbit, so the gradient
    /// appears to breathe without ever jumping.
    private func points(at time: Double) -> [SIMD2<Float>] {
        let a = Float(sin(time * 0.11)) * 0.055
        let b = Float(cos(time * 0.10)) * 0.055
        let c = Float(sin(time * 0.08 + 1.4)) * 0.045
        let d = Float(cos(time * 0.13 + 2.1)) * 0.045
        return [
            SIMD2(0, 0),          SIMD2(0.5 + a, 0), SIMD2(1, 0),
            SIMD2(0, 0.5 + b),    SIMD2(0.5 + c, 0.5 + d), SIMD2(1, 0.5 - b),
            SIMD2(0, 1),          SIMD2(0.5 - a, 1), SIMD2(1, 1)
        ]
    }

    private func orb(color: Color, diameter: CGFloat, opacity: Double) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [color.opacity(opacity), color.opacity(opacity * 0.35), .clear],
                    center: .center, startRadius: 0, endRadius: diameter * 0.5
                )
            )
            .frame(width: diameter, height: diameter)
            .blur(radius: 60)
            .allowsHitTesting(false)
    }

    private func flowRibbons(time: Double) -> some View {
        Canvas { context, size in
            for index in 0..<2 {
                var path = Path()
                let base = size.height * (0.30 + Double(index) * 0.30)
                path.move(to: CGPoint(x: -60, y: base))
                for step in stride(from: 0.0, through: size.width + 60, by: 24) {
                    let wave = sin((step / 190) + time * 0.22 + Double(index) * 1.6) * 30
                    path.addLine(to: CGPoint(x: step, y: base + wave))
                }
                context.stroke(
                    path,
                    with: .linearGradient(
                        Gradient(colors: [.clear, VaultTheme.ribbon.opacity(0.55), .clear]),
                        startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)
                    ),
                    lineWidth: 1.0
                )
            }
        }
        .allowsHitTesting(false)
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
        .padding(.horizontal, 8).padding(.vertical, 3.5)
        .background {
            Capsule().fill(tint.opacity(0.13))
        }
        .overlay(Capsule().strokeBorder(tint.opacity(0.26), lineWidth: 0.7))
        .foregroundStyle(tint)
    }
}

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .semibold))
                if let subtitle {
                    Text(subtitle).font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
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
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [VaultTheme.strengthColor(result.score).opacity(0.75),
                                         VaultTheme.strengthColor(result.score)],
                                startPoint: .leading, endPoint: .trailing
                            )
                        )
                        .frame(width: max(6, geo.size.width * fraction))
                        .shadow(color: VaultTheme.strengthColor(result.score).opacity(0.45), radius: 5, y: 1)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: result.bits)
                }
            }
            .frame(height: 6)
            HStack(spacing: 6) {
                Text(result.score.shortLabel)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(VaultTheme.strengthColor(result.score))
                Text("·").foregroundStyle(VaultTheme.faint)
                Text("\(Int(result.bits.rounded())) bits")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(VaultTheme.subtle)
                if showCrackTime {
                    Text("·").foregroundStyle(VaultTheme.faint)
                    Text(result.crackTime).font(.system(size: 10.5)).foregroundStyle(VaultTheme.subtle)
                }
                Spacer()
            }
        }
    }

    private var fraction: Double {
        min(1.0, max(0.04, result.bits / 120.0))
    }
}

/// Service avatar: a rounded square with the service initial and a glassy rim.
struct ServiceAvatar: View {
    var service: String
    var size: CGFloat = 28

    var body: some View {
        let colors = VaultTheme.avatarColors(for: service)
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(LinearGradient(colors: [colors.0, colors.1],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            // Specular sheen across the top half.
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .fill(
                    LinearGradient(colors: [Color.white.opacity(0.30), .clear],
                                   startPoint: .top, endPoint: .center)
                )
                .blendMode(.plusLighter)
            Text(VaultTheme.initials(for: service))
                .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: colors.1.opacity(0.55), radius: 2, y: 1)
        }
        .frame(width: size, height: size)
        .overlay(
            RoundedRectangle(cornerRadius: size * 0.30, style: .continuous)
                .strokeBorder(Color.white.opacity(0.30), lineWidth: 0.7)
        )
        .shadow(color: colors.1.opacity(0.38), radius: size * 0.30, y: size * 0.10)
    }
}

/// Pill button in the Liquid Glass idiom: tinted glass for primary actions,
/// neutral glass for secondary ones, and no chrome for ghost buttons.
struct VaultButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, destructive, ghost }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12.5, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 7)
            .foregroundStyle(foreground)
            .background {
                if kind != .ghost {
                    GlassBackdrop(glass: .regular.interactive(), shape: Capsule(),
                                  tint: (kind == .primary || kind == .destructive) ? fillColor : nil,
                                  tintOpacity: 1)
                }
            }
            .overlay {
                if kind != .ghost {
                    Capsule().strokeBorder(borderColor, lineWidth: 0.8)
                }
            }
            .shadow(color: shadowColor, radius: configuration.isPressed ? 4 : 9,
                    y: configuration.isPressed ? 1 : 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.24, dampingFraction: 0.78), value: configuration.isPressed)
    }

    /// Painted behind the glass; `Glass.tint` would hide the label on this SDK.
    private var fillColor: Color {
        switch kind {
        case .primary: return VaultTheme.electric.opacity(0.52)
        case .destructive: return Color.red.opacity(0.42)
        case .secondary, .ghost: return .clear
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .destructive: return .red
        default: return .primary
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary: return Color.white.opacity(0.32)
        case .destructive: return Color.red.opacity(0.34)
        case .secondary: return Color.white.opacity(0.16)
        case .ghost: return .clear
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .primary: return VaultTheme.electric.opacity(0.35)
        case .destructive: return Color.red.opacity(0.18)
        default: return .clear
        }
    }
}

/// A compact icon button. Native interactive glass supplies the hover shine,
/// so no manual hover state is needed.
struct IconAction: View {
    var systemImage: String
    var help: String
    var tint: Color = VaultTheme.subtle
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .foregroundStyle(tint)
                .background {
                    GlassBackdrop(glass: .clear.interactive(), shape: Circle())
                }
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

extension View {
    /// Keyboard-friendly focus ring matching the brand.
    func vaultFocusable() -> some View {
        self
    }
}
