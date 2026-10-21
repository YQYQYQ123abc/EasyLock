import SwiftUI
import AppKit

/// The interface follows the app icon: paper and ink, a nested shield outline,
/// a single lock, and almost no color. Color is reserved for warnings only.
enum EasyLockStyle {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }

    // Core ramp
    static let ink = adaptive(0x111113, 0xF6F6F2)
    static let accent = ink
    static let secondary = adaptive(0x5F5F63, 0xACACB2)
    static let tertiary = adaptive(0x797975, 0x8B8B92)

    static let background = adaptive(0xF4F4F0, 0x09090A)
    static let surface = adaptive(0xFFFFFF, 0x141416)
    static let surfaceRaised = adaptive(0xFAFAF7, 0x19191C)
    static let surfaceMuted = adaptive(0xF0F0EB, 0x1E1E21)
    static let border = adaptive(0xE3E3DC, 0x2A2A2E)
    static let borderStrong = adaptive(0xCBCBC4, 0x3C3C41)

    // Controls
    static let buttonFill = ink
    static let buttonText = adaptive(0xFFFFFF, 0x0A0A0B)
    static let warning = adaptive(0xA66A0C, 0xE2B35E)
    static let danger = adaptive(0xAC382D, 0xE58377)

    // The sidebar is ink in both appearances, like the dark app icon.
    static let sidebar = Color(red: 0.043, green: 0.043, blue: 0.049)
    static let sidebarLine = Color.white.opacity(0.075)
    static let sidebarText = Color.white.opacity(0.64)
    static let sidebarDim = Color.white.opacity(0.40)
    static let sidebarSelectedText = Color(red: 0.05, green: 0.05, blue: 0.06)

    static let cardRadius: CGFloat = 18
    static let controlRadius: CGFloat = 10
}

// MARK: - Brand

/// Shield with a nested rim and a padlock, drawn to match the application icon.
struct ShieldShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * w, y: rect.minY + y * h)
        }
        var path = Path()
        path.move(to: pt(0.5, 0.012))
        path.addLine(to: pt(0.148, 0.132))
        path.addQuadCurve(to: pt(0.064, 0.214), control: pt(0.064, 0.143))
        path.addCurve(to: pt(0.5, 0.988),
                      control1: pt(0.069, 0.56), control2: pt(0.232, 0.862))
        path.addCurve(to: pt(0.936, 0.214),
                      control1: pt(0.768, 0.862), control2: pt(0.931, 0.56))
        path.addQuadCurve(to: pt(0.852, 0.132), control: pt(0.936, 0.143))
        path.closeSubpath()
        return path
    }
}

struct ShieldMark: View {
    enum Tone { case auto, light, dark }
    var size: CGFloat = 64
    var tone: Tone = .auto
    @Environment(\.colorScheme) private var scheme

    private var lightSilhouette: Bool {
        switch tone {
        case .light: true
        case .dark: false
        case .auto: scheme == .dark
        }
    }

    var body: some View {
        let silhouette = lightSilhouette
        ZStack {
            ShieldShape().fill(
                LinearGradient(colors: silhouette
                               ? [Color.white, Color(red: 0.90, green: 0.90, blue: 0.88)]
                               : [Color(red: 0.115, green: 0.115, blue: 0.122), Color(red: 0.025, green: 0.025, blue: 0.03)],
                               startPoint: .top, endPoint: .bottom)
            )
            ShieldShape()
                .stroke(silhouette ? Color.black.opacity(0.20) : Color.white.opacity(0.52),
                        lineWidth: max(1, size * 0.018))
                .padding(size * 0.088)
            Image(systemName: "lock.fill")
                .font(.system(size: size * 0.30, weight: .semibold))
                .foregroundStyle(silhouette ? Color.black.opacity(0.88) : Color.white.opacity(0.95))
                .offset(y: size * 0.006)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct BrandMark: View {
    var size: CGFloat = 64
    var showsTile = true
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder var body: some View {
        if showsTile {
            let shape = RoundedRectangle(cornerRadius: size * 0.235, style: .continuous)
            ZStack {
                shape
                    .fill(scheme == .dark
                          ? LinearGradient(colors: [Color(red: 0.135, green: 0.135, blue: 0.145), Color(red: 0.05, green: 0.05, blue: 0.056)], startPoint: .topLeading, endPoint: .bottomTrailing)
                          : LinearGradient(colors: [Color.white, Color(red: 0.965, green: 0.965, blue: 0.95)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .overlay {
                        shape.inset(by: 1)
                            .strokeBorder(scheme == .dark ? Color.white.opacity(0.03) : Color.white.opacity(0.9), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.16), radius: size * 0.11, y: size * 0.045)
                ShieldMark(size: size * 0.70)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
        } else {
            ShieldMark(size: size)
        }
    }
}

// MARK: - Surfaces

/// Opaque card surface with the icon's double rim. Kept under the historic
/// `GlassPanel` name so existing call sites remain valid.
struct GlassPanel: View {
    var radius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        shape
            .fill(EasyLockStyle.surface)
            .overlay {
                shape.strokeBorder(EasyLockStyle.border, lineWidth: 1)
            }
            .overlay {
                if radius > 0 {
                    shape.inset(by: 1)
                        .strokeBorder(scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.85), lineWidth: 1)
                }
            }
            .shadow(color: .black.opacity(radius > 0 ? (scheme == .dark ? 0.34 : 0.05) : 0),
                    radius: radius > 0 ? 16 : 0,
                    y: radius > 0 ? 6 : 0)
    }
}

struct VaultBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                WorkspaceBackground()
                ShieldShape()
                    .stroke(EasyLockStyle.ink.opacity(0.032), lineWidth: 1.2)
                    .frame(width: min(max(geo.size.width * 0.54, 380), 660),
                           height: min(max(geo.size.height * 0.82, 460), 820))
                    .rotationEffect(.degrees(7))
                    .offset(x: geo.size.width * 0.34, y: geo.size.height * 0.05)
            }
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

struct WorkspaceBackground: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            EasyLockStyle.background
            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.045 : 0.70), .clear],
                           startPoint: .topLeading, endPoint: .center)
            LinearGradient(colors: [.clear, Color.black.opacity(scheme == .dark ? 0.0 : 0.018)],
                           startPoint: .center, endPoint: .bottom)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Controls

struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: EasyLockStyle.controlRadius, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .foregroundStyle(EasyLockStyle.buttonText)
            .background(EasyLockStyle.buttonFill, in: shape)
            .overlay {
                shape.strokeBorder(scheme == .dark ? Color.black.opacity(0.12) : Color.white.opacity(0.12), lineWidth: 1)
            }
            .shadow(color: .black.opacity(enabled && scheme == .light ? 0.16 : 0), radius: 7, y: 3)
            .opacity(enabled ? (configuration.isPressed ? 0.78 : 1) : 0.36)
    }
}

struct BrandSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.colorScheme) private var scheme

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: EasyLockStyle.controlRadius, style: .continuous)
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 34)
            .foregroundStyle(EasyLockStyle.ink)
            .background(configuration.isPressed ? EasyLockStyle.surfaceMuted : EasyLockStyle.surface, in: shape)
            .overlay { shape.strokeBorder(EasyLockStyle.border, lineWidth: 1) }
            .shadow(color: .black.opacity(scheme == .dark ? 0.20 : 0.035), radius: 5, y: 2)
            .opacity(enabled ? 1 : 0.38)
    }
}

struct BrandGhostButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(EasyLockStyle.ink.opacity(configuration.isPressed ? 0.55 : 0.82))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.35)
    }
}

struct BrandGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
            configuration.content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background { GlassPanel(radius: EasyLockStyle.cardRadius) }
    }
}

/// Rounded input background used by welcome, sheets and inline forms.
private struct FieldSurfaceModifier: ViewModifier {
    var focused: Bool
    var height: CGFloat
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        content
            .padding(.horizontal, 13)
            .frame(height: height)
            .background(EasyLockStyle.surface, in: shape)
            .overlay {
                shape.strokeBorder(focused ? EasyLockStyle.ink.opacity(0.62) : EasyLockStyle.border,
                                   lineWidth: focused ? 1.5 : 1)
            }
            .shadow(color: .black.opacity(focused ? (scheme == .dark ? 0.28 : 0.06) : 0), radius: 6, y: 2)
    }
}

extension View {
    func fieldSurface(focused: Bool = false, height: CGFloat = 42) -> some View {
        modifier(FieldSurfaceModifier(focused: focused, height: height))
    }
}

// MARK: - Reusable fragments

struct IconMedallion: View {
    let symbol: String
    var size: CGFloat = 38

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                .fill(EasyLockStyle.ink)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                }
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(EasyLockStyle.buttonText)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Shared heading keeps page identity and typography stable while switching sections.
struct PageHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            IconMedallion(symbol: symbol, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.35)
                Text(subtitle)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(subtitle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.25)
            .foregroundStyle(EasyLockStyle.secondary)
            .padding(.leading, 2)
    }
}

struct SheetHeader: View {
    let symbol: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            IconMedallion(symbol: symbol, size: 42)
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .tracking(-0.3)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct KeyCap: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(EasyLockStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(EasyLockStyle.border, lineWidth: 1)
            }
    }
}

struct InlineNotice: View {
    enum Kind { case info, warning }
    let text: String
    var kind: Kind = .warning

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: kind == .warning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.system(size: 11.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(kind == .warning ? EasyLockStyle.warning : EasyLockStyle.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(EasyLockStyle.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(kind == .warning ? EasyLockStyle.warning.opacity(0.28) : EasyLockStyle.border, lineWidth: 1)
        }
    }
}

struct BrandLoop: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.82, y: rect.height * 0.18))
        path.addCurve(to: CGPoint(x: rect.width * 0.18, y: rect.height * 0.8), control1: CGPoint(x: -rect.width * 0.1, y: -rect.height * 0.3), control2: CGPoint(x: -rect.width * 0.08, y: rect.height * 1.12))
        path.addCurve(to: CGPoint(x: rect.width * 0.7, y: rect.height * 0.45), control1: CGPoint(x: rect.width * 0.53, y: rect.height * 1.1), control2: CGPoint(x: rect.width * 1.03, y: rect.height * 0.07))
        path.addCurve(to: CGPoint(x: rect.width, y: rect.height * 0.83), control1: CGPoint(x: rect.width * 0.41, y: rect.height * 0.78), control2: CGPoint(x: rect.width * 0.88, y: rect.height * 0.86))
        return path
    }
}
