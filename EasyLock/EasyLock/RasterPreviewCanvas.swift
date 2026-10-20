import SwiftUI

/// An edge-to-edge canvas; controls float over it instead of taking a second title row.
struct RasterPreviewCanvas: View {
    let image: NSImage
    @State private var zoom: CGFloat = 0
    @State private var hovering = false
    @FocusState private var controlsFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let fit = min(geometry.size.width / max(1, image.size.width), geometry.size.height / max(1, image.size.height))
            let factor = zoom == 0 ? min(1, fit) : zoom
            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image).resizable().interpolation(.high)
                    .frame(width: image.size.width * factor, height: image.size.height * factor)
                    .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
            }
            .overlay(alignment: .bottom) {
                HStack(spacing: 14) {
                    Button { zoom = 0 } label: { Image(systemName: "arrow.down.right.and.arrow.up.left") }
                        .help("适合窗口").accessibilityLabel("适合窗口")
                    Divider().frame(height: 14)
                    Button { zoom = max(0.25, (zoom == 0 ? min(1, fit) : zoom) / 1.25) } label: { Image(systemName: "minus.magnifyingglass") }
                        .help("缩小").accessibilityLabel("缩小")
                    Button { zoom = min(4, (zoom == 0 ? min(1, fit) : zoom) * 1.25) } label: { Image(systemName: "plus.magnifyingglass") }
                        .help("放大").accessibilityLabel("放大")
                }.buttonStyle(.plain).font(.system(size: 13)).padding(.horizontal, 14).padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule()).padding(.bottom, 14)
                    .focusable().focused($controlsFocused)
                    .opacity(hovering || controlsFocused ? 1 : 0)
                    .allowsHitTesting(hovering || controlsFocused)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
            }
        }.onHover { hovering = $0 }
    }
}
