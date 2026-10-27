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

    // Signal blue is the only saturated hue; it carries focus, charts and actions.
    static let blue = adaptive(0x2563EB, 0x5B8DEF)
    static let blueDeep = adaptive(0x1D4ED8, 0x7EA8FF)
    static let blueSoft = adaptive(0xEFF4FF, 0x18253D)
    static let blueTint = adaptive(0xDBEAFE, 0x203553)
    static let accent = blue

    // Neutral ramp
    static let ink = adaptive(0x101828, 0xF2F4F7)
    static let secondary = adaptive(0x667085, 0x98A2B3)
    static let tertiary = adaptive(0x98A2B3, 0x667085)

    static let background = adaptive(0xEFF2F7, 0x090B10)
    static let surface = adaptive(0xFFFFFF, 0x15171C)
    static let surfaceRaised = adaptive(0xF8FAFC, 0x1A1D23)
    static let surfaceMuted = adaptive(0xF2F4F7, 0x20242B)
    static let border = adaptive(0xE4E7EC, 0x282C34)
    static let borderStrong = adaptive(0xD0D5DD, 0x353A44)

    // Controls
    static let buttonFill = blue
    static let buttonText = Color.white
    static let success = adaptive(0x12B76A, 0x32D583)
    static let successSoft = adaptive(0xECFDF3, 0x10261A)
    static let warning = adaptive(0xB54708, 0xFDB022)
    static let warningSoft = adaptive(0xFFFAEB, 0x251D0E)
    static let danger = adaptive(0xB42318, 0xF97066)
    static let dangerSoft = adaptive(0xFEF3F2, 0x2A1715)

    // Light-first sidebar, still dark in dark appearance.
    static let sidebar = adaptive(0xF7F9FC, 0x0B0D12)
    static let sidebarLine = adaptive(0xE4E7EC, 0x22262E)
    static let sidebarText = adaptive(0x475467, 0x9AA3B2)
    static let sidebarDim = adaptive(0x98A2B3, 0x6B7280)
    static let sidebarSelectedFill = adaptive(0xE8EFFC, 0x1C2A42)
    static let sidebarSelectedText = adaptive(0x1D4ED8, 0x9DBBFF)
    static let sidebarHover = adaptive(0xF0F3F8, 0x171A20)

    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 11
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
            .shadow(color: .black.opacity(radius > 0 ? (scheme == .dark ? 0.34 : 0.065) : 0),
                    radius: radius > 0 ? 18 : 0,
                    y: radius > 0 ? 6 : 0)
    }
}

struct VaultBackground: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                WorkspaceBackground()
                ShieldShape()
                    .stroke(EasyLockStyle.blue.opacity(0.055), lineWidth: 1.2)
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
            RadialGradient(colors: [EasyLockStyle.blue.opacity(scheme == .dark ? 0.10 : 0.05), .clear],
                           center: .topTrailing, startRadius: 18, endRadius: 680)
            LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.02 : 0.22), .clear],
                           startPoint: .topLeading, endPoint: .center)
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
            .shadow(color: EasyLockStyle.blue.opacity(enabled ? (scheme == .light ? 0.24 : 0.18) : 0), radius: 10, y: 4)
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
            .foregroundStyle(EasyLockStyle.blueDeep.opacity(configuration.isPressed ? 0.55 : 0.9))
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
                shape.strokeBorder(focused ? EasyLockStyle.blue.opacity(0.72) : EasyLockStyle.border,
                                   lineWidth: focused ? 1.5 : 1)
            }
            .shadow(color: EasyLockStyle.blue.opacity(focused ? 0.14 : 0), radius: 7, y: 2)
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
                .fill(EasyLockStyle.blueSoft)
                .overlay {
                    RoundedRectangle(cornerRadius: size * 0.29, style: .continuous)
                        .strokeBorder(EasyLockStyle.blue.opacity(0.16), lineWidth: 1)
                }
            Image(systemName: symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(EasyLockStyle.blueDeep)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Shared heading keeps page identity and typography stable while switching sections.
/// Shared size for quiet icon-only controls such as ellipsis menus, eye
/// buttons, and directory navigation. Keeping one control shape makes the
/// small iconography read as the same family across pages.
struct IconControl: ViewModifier {
    var size: CGFloat = 30
    var bordered = true

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .background(bordered ? EasyLockStyle.surface : EasyLockStyle.surfaceMuted,
                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay {
                if bordered {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

extension View {
    func iconControl(size: CGFloat = 30, bordered: Bool = true) -> some View {
        modifier(IconControl(size: size, bordered: bordered))
    }
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            IconMedallion(symbol: symbol, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.5)
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
        .foregroundStyle(kind == .warning ? EasyLockStyle.warning : EasyLockStyle.blueDeep)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(kind == .warning ? EasyLockStyle.warningSoft : EasyLockStyle.blueSoft,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder((kind == .warning ? EasyLockStyle.warning : EasyLockStyle.blue).opacity(0.22), lineWidth: 1)
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
