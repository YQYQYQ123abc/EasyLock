import SwiftUI

enum EasyLockStyle {
    static let accent = Color(red: 0.26, green: 0.36, blue: 0.72)
    static let blue = Color(red: 0.34, green: 0.47, blue: 0.84)
    static let secondary = Color(red: 0.76, green: 0.43, blue: 0.70)
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
                (scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color.white)
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
            .background(EasyLockStyle.accent, in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(Color.primary, lineWidth: 1.5))
            .shadow(color: Color.primary.opacity(enabled ? 0.18 : 0), radius: 0, x: 0, y: configuration.isPressed ? 0 : 3)
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
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.primary.opacity(0.7), lineWidth: 1.2))
            .shadow(color: EasyLockStyle.secondary.opacity(0.09), radius: 0, x: 4, y: 4)
    }
}
