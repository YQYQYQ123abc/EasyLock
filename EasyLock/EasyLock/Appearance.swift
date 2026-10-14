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
    static let accent = adaptive(0x4569CB, 0x9AB2FF)
    static let blue = adaptive(0x5B7FE8, 0x7F9CF5)
    static let secondary = adaptive(0xC777C6, 0xD899D7)
    static let background = adaptive(0xF3F3F7, 0x111218)
    static let sidebar = adaptive(0xECEDF3, 0x171821)
    static let border = adaptive(0xE3E4EC, 0x383B4D)
    static let buttonFill = Color(red: 0.29, green: 0.40, blue: 0.77)
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
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                EasyLockStyle.background
                RadialGradient(colors: [EasyLockStyle.blue.opacity(0.13), .clear], center: .topLeading, startRadius: 0, endRadius: 500)
                RadialGradient(colors: [EasyLockStyle.secondary.opacity(0.14), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 460)
                if !reduceTransparency {
                    BrandLoop().stroke(EasyLockStyle.blue.opacity(scheme == .dark ? 0.11 : 0.065), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                        .frame(width: min(proxy.size.width * 0.65, 520), height: 380).offset(x: 100, y: 110)
                    Image(systemName: "heart.fill").font(.system(size: 100)).foregroundStyle(EasyLockStyle.secondary.opacity(0.08))
                        .rotationEffect(.degrees(-14)).offset(x: -36, y: -30)
                }
            }.clipped()
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}
struct BrandPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.callout.weight(.semibold)).padding(.horizontal, 17).padding(.vertical, 10)
            .foregroundStyle(.white)
            .background(EasyLockStyle.buttonFill, in: RoundedRectangle(cornerRadius: 8))
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
        }.frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(EasyLockStyle.border, lineWidth: 1))
    }
}
