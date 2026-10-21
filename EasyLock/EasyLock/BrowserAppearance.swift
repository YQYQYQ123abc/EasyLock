import SwiftUI

/// Appearance is inferred from the visible filename only, never from private content.
struct FileVisualStyle {
    let symbol: String
    let label: String

    static func resolve(name: String, folder: Bool, locked: Bool) -> Self {
        if folder { return Self(symbol: "folder", label: "FOLDER") }
        var url = URL(fileURLWithPath: name)
        if locked && url.pathExtension.lowercased() == "easylock" { url.deletePathExtension() }
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "gif", "webp", "tiff", "svg":
            return Self(symbol: "photo", label: "IMAGE")
        case "pdf": return Self(symbol: "doc.richtext", label: "PDF")
        case "xls", "xlsx", "csv", "numbers":
            return Self(symbol: "tablecells", label: "SHEET")
        case "ppt", "pptx", "key": return Self(symbol: "rectangle.on.rectangle", label: "SLIDES")
        case "zip", "rar", "7z", "gz", "tar": return Self(symbol: "doc.zipper", label: "ARCHIVE")
        case "mov", "mp4", "m4v", "mkv": return Self(symbol: "play.rectangle", label: "VIDEO")
        case "mp3", "wav", "m4a", "flac", "aac": return Self(symbol: "waveform", label: "AUDIO")
        case "swift", "js", "ts", "py", "json", "html", "css", "rs", "go", "sh":
            return Self(symbol: "chevron.left.forwardslash.chevron.right", label: "CODE")
        case "doc", "docx", "txt", "md", "rtf", "pages":
            return Self(symbol: "doc.text", label: "DOC")
        default: return Self(symbol: locked ? "lock.doc" : "doc", label: locked ? "LOCKED" : "FILE")
        }
    }
}

/// Monochrome file tile that echoes the app icon: paper surface, ink rim,
/// and a lock seal only when the item is protected.
struct BrowserFileArtwork: View {
    let name: String
    let folder: Bool
    let locked: Bool
    var unavailable = false
    var tileSize: CGFloat = 74
    @Environment(\.colorScheme) private var scheme

    private var style: FileVisualStyle { .resolve(name: name, folder: folder, locked: locked) }

    private var tile: LinearGradient {
        scheme == .dark
            ? LinearGradient(colors: [Color(red: 0.165, green: 0.165, blue: 0.175),
                                      Color(red: 0.105, green: 0.105, blue: 0.113)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
            : LinearGradient(colors: [Color.white, Color(red: 0.925, green: 0.925, blue: 0.905)],
                             startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: tileSize * 0.24, style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            shape
                .fill(tile)
                .overlay {
                    shape.strokeBorder(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.09), lineWidth: 1)
                }
                .overlay {
                    shape.inset(by: 1)
                        .strokeBorder(scheme == .dark ? Color.white.opacity(0.035) : Color.white.opacity(0.9), lineWidth: 1)
                }
                .shadow(color: .black.opacity(scheme == .dark ? 0.32 : 0.07), radius: 7, y: 3)
                .frame(width: tileSize, height: tileSize)

            Image(systemName: style.symbol)
                .font(.system(size: tileSize * 0.38, weight: .light))
                .foregroundStyle(EasyLockStyle.ink.opacity(locked ? 0.9 : 0.66))
                .frame(width: tileSize, height: tileSize)
                .symbolRenderingMode(.monochrome)

            if locked || unavailable {
                seal
                    .offset(x: 5, y: 5)
            }
        }
        .frame(height: 92)
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    private var seal: some View {
        ZStack {
            Circle()
                .fill(EasyLockStyle.surface)
                .frame(width: 26, height: 26)
            Circle()
                .fill(unavailable ? EasyLockStyle.warning : EasyLockStyle.ink)
                .frame(width: 21, height: 21)
            Image(systemName: unavailable ? "exclamationmark" : "lock.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(unavailable ? Color.white : EasyLockStyle.buttonText)
        }
        .shadow(color: .black.opacity(0.20), radius: 3, y: 1)
    }
}

struct FileStatusPill: View {
    let locked: Bool
    var needsAttention = false

    private var color: Color { needsAttention ? EasyLockStyle.warning : EasyLockStyle.ink }
    private var label: String { needsAttention ? "需检查" : locked ? "已上锁" : "未加密" }
    private var symbol: String {
        needsAttention ? "exclamationmark.triangle.fill" : locked ? "lock.fill" : "lock.open"
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8, weight: .bold))
            Text(label).font(.system(size: 9.5, weight: .semibold)).tracking(0.2)
        }
        .foregroundStyle(needsAttention ? color : (locked ? color : EasyLockStyle.secondary))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(locked || needsAttention ? 0.07 : 0.04), in: Capsule())
        .overlay {
            Capsule().strokeBorder(color.opacity(locked || needsAttention ? 0.22 : 0.16), lineWidth: 1)
        }
        .accessibilityLabel(label)
    }
}

struct FileActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8, style: .continuous)
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .foregroundStyle(EasyLockStyle.buttonText)
            .background(EasyLockStyle.buttonFill.opacity(configuration.isPressed ? 0.8 : 1), in: shape)
            .opacity(enabled ? 1 : 0.38)
    }
}

struct BrowserCardSurface: ViewModifier {
    let selected: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 16, style: .continuous)
        content
            .padding(14)
            .background { GlassPanel(radius: 16) }
            .overlay {
                shape.strokeBorder(selected ? EasyLockStyle.ink : .clear, lineWidth: 1.6)
            }
            .overlay {
                shape.strokeBorder(hovering && !selected ? EasyLockStyle.ink.opacity(0.16) : .clear, lineWidth: 1)
            }
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
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
                ZStack(alignment: .bottomTrailing) {
                    BrandMark(size: 82)
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(EasyLockStyle.buttonText)
                        .frame(width: 27, height: 27)
                        .background(EasyLockStyle.ink, in: Circle())
                        .overlay { Circle().strokeBorder(EasyLockStyle.surface, lineWidth: 2) }
                        .offset(x: 3, y: 3)
                }
                .padding(.bottom, 4)

                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(EasyLockStyle.ink)
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)

                Button(actionTitle, action: action)
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .padding(.top, 2)
            }
            .frame(maxWidth: 420)
            .padding(32)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
