import SwiftUI

/// Appearance is inferred from the visible filename only, never from private content.
struct FileVisualStyle {
    let symbol: String
    let label: String
    let color: Color
    let companion: Color
    let rounded: Bool
    static func resolve(name: String, folder: Bool, locked: Bool) -> Self {
        if folder { return Self(symbol: "folder.fill", label: "FOLDER", color: .blue, companion: .cyan, rounded: false) }
        var url = URL(fileURLWithPath: name)
        if locked && url.pathExtension.lowercased() == "easylock" { url.deletePathExtension() }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "svg":
            return Self(symbol: "photo", label: "IMAGE", color: .teal, companion: .mint, rounded: false)
        case "pdf": return Self(symbol: "doc.richtext", label: "PDF", color: .pink, companion: .red, rounded: false)
        case "xls", "xlsx", "csv", "numbers":
            return Self(symbol: "tablecells", label: "SHEET", color: .teal, companion: .cyan, rounded: false)
        case "ppt", "pptx", "key": return Self(symbol: "rectangle.on.rectangle", label: "SLIDES", color: .orange, companion: .pink, rounded: false)
        case "zip", "rar", "7z", "gz", "tar": return Self(symbol: "doc.zipper", label: "ARCHIVE", color: .orange, companion: .yellow, rounded: false)
        case "mov", "mp4", "m4v", "mkv": return Self(symbol: "play.rectangle.fill", label: "VIDEO", color: .purple, companion: .pink, rounded: true)
        case "mp3", "wav", "m4a", "flac", "aac": return Self(symbol: "waveform", label: "AUDIO", color: .indigo, companion: .cyan, rounded: true)
        case "swift", "js", "ts", "py", "json", "html", "css", "rs", "go", "sh":
            return Self(symbol: "chevron.left.forwardslash.chevron.right", label: "CODE", color: .cyan, companion: .blue, rounded: false)
        case "doc", "docx", "txt", "md", "rtf", "pages":
            return Self(symbol: "doc.text", label: "DOC", color: .gray, companion: .blue, rounded: false)
        default: return Self(symbol: locked ? "lock.doc" : "doc", label: locked ? "LOCKED" : "FILE", color: .gray, companion: .blue, rounded: false)
        }
    }
}

struct BrowserFileArtwork: View {
    let name: String
    let folder: Bool
    let locked: Bool
    var unavailable = false
    private var style: FileVisualStyle { .resolve(name: name, folder: folder, locked: locked) }
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [style.color.opacity(0.15), style.color.opacity(0.30)], startPoint: .top, endPoint: .bottom))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(style.color.opacity(0.18), lineWidth: 1))
                .frame(width: 72, height: 72)
                .shadow(color: .black.opacity(0.10), radius: 2, y: 2)
            Image(systemName: style.symbol).font(.system(size: 34, weight: .regular)).foregroundStyle(style.color)
            if locked || unavailable {
                Image(systemName: unavailable ? "exclamationmark" : "lock.fill")
                    .font(.system(size: 10, weight: .semibold)).foregroundStyle(.yellow)
                    .frame(width: 22, height: 22).background(Color(red: 0.12, green: 0.16, blue: 0.23), in: Circle())
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                    .offset(x: 32, y: 32)
            }
        }.frame(height: 88).frame(maxWidth: .infinity).accessibilityHidden(true)
    }
}

struct FileStatusPill: View {
    let locked: Bool
    var needsAttention = false
    private var color: Color { needsAttention ? .orange : locked ? .pink : .teal }
    var body: some View {
        Label(needsAttention ? "需检查" : locked ? "已上锁" : "未加密", systemImage: needsAttention ? "exclamationmark.triangle" : locked ? "lock" : "lock.open")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct FileActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 11).padding(.vertical, 7).foregroundStyle(.white)
            .background(EasyLockStyle.buttonFill.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1).opacity(enabled ? 1 : 0.4)
    }
}

struct BrowserCardSurface: ViewModifier {
    let selected: Bool
    var tint: Color = EasyLockStyle.accent
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.padding(16)
            .background { GlassPanel(radius: 16) }
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(selected ? EasyLockStyle.accent : .clear, lineWidth: 2))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(hovering ? 0.12 : 0.05), lineWidth: 1))
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: hovering)
    }
}

struct BrowserEmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    let actionTitle: String
    let action: () -> Void
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light)).foregroundStyle(EasyLockStyle.accent)
                    .frame(width: 86, height: 86)
                    .background(EasyLockStyle.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 26))
                    .overlay(RoundedRectangle(cornerRadius: 26).stroke(EasyLockStyle.blue.opacity(0.12)))
                VStack(spacing: 9) {
                    Text(title).font(.title3.weight(.semibold)).foregroundStyle(.primary)
                    Text(detail).font(.callout).foregroundStyle(.secondary).lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }.multilineTextAlignment(.center)
                Button(actionTitle, action: action).buttonStyle(BrandPrimaryButtonStyle()).padding(.top, 4)
            }.frame(maxWidth: 420).padding(32).frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
