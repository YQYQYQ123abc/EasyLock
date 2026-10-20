import SwiftUI
import AppKit

enum EasyLockStyle {
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
    static let accent = adaptive(0x1764F5, 0x83B5FF)
    static let blue = adaptive(0x3687FF, 0x7DBEFF)
    static let secondary = adaptive(0x139BB5, 0x68D5E5)
    static let background = adaptive(0xEDF1F8, 0x101722)
    static let sidebar = adaptive(0xECEDF3, 0x171821)
    static let border = adaptive(0xD9E2F0, 0x344256)
    static let buttonFill = Color(red: 0.08, green: 0.36, blue: 0.96)
}
struct BrandMark: View {
    var size: CGFloat = 64
    var body: some View {
        Image("BrandMark").resizable().interpolation(.high).scaledToFit()
            .frame(width: size, height: size).accessibilityHidden(true)
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
struct VaultBackground: View {
    var body: some View { WorkspaceBackground() }
}

/// Material surfaces retain an opaque alternative for Reduce Transparency.
struct GlassPanel: View {
    var radius: CGFloat = 22
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(reduceTransparency ? AnyShapeStyle(Color(nsColor: .controlBackgroundColor)) : AnyShapeStyle(.thinMaterial))
            .overlay(RoundedRectangle(cornerRadius: radius).fill(Color.white.opacity(scheme == .dark ? 0.04 : 0.45)))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(
                LinearGradient(colors: [.white.opacity(scheme == .dark ? 0.20 : 0.9), EasyLockStyle.border.opacity(0.5)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
    }
}
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.semibold)).padding(.horizontal, 17).padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(EasyLockStyle.buttonFill, in: RoundedRectangle(cornerRadius: 10))
            .shadow(color: EasyLockStyle.buttonFill.opacity(enabled ? 0.14 : 0), radius: 4, y: 2)
            .offset(y: configuration.isPressed && !reduceMotion ? 2 : 0)
            .opacity(enabled ? 1 : 0.45)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct BrandGroupBoxStyle: GroupBoxStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            configuration.label.font(.headline)
            configuration.content
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20)
            .background { GlassPanel(radius: 18) }
            .shadow(color: .black.opacity(0.025), radius: 12, y: 5)
    }
}

/// Shared heading keeps page identity and typography stable while switching sections.
struct PageHeading: View {
    let title: String
    let subtitle: String
    let symbol: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(EasyLockStyle.accent).frame(width: 36, height: 36)
                .background(EasyLockStyle.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 17, weight: .semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle).help(subtitle)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WorkspaceBackground: View {
    var body: some View {
        Color(nsColor: .windowBackgroundColor).allowsHitTesting(false).accessibilityHidden(true)
    }
}
