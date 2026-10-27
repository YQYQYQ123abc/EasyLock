import SwiftUI

struct LibraryItemCard: View {
    @State private var hovering = false
    let item: LockedItem
    let selected: Bool
    let touchID: Bool
    let select: () -> Void
    let preview: () -> Void
    let decrypt: () -> Void
    let reveal: () -> Void

    private var needsAttention: Bool { item.warning != nil || item.originalRetained }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                VStack(spacing: 10) {
                    HStack {
                        FileStatusPill(locked: true, needsAttention: needsAttention)
                        Spacer(minLength: 8)
                        SelectionDot(selected: selected)
                    }
                    BrowserFileArtwork(name: item.name, folder: false, locked: true, unavailable: needsAttention)
                    VStack(spacing: 5) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .multilineTextAlignment(.center)
                            .frame(height: 34, alignment: .top)
                            .frame(maxWidth: .infinity)
                        HStack(spacing: 5) {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                            Text("·")
                            Text("密文")
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(item.name + "\n点击选择，⌘ 点击多选")
            .accessibilityLabel(item.name + (selected ? "，已选择" : ""))

            Rectangle()
                .fill(EasyLockStyle.border)
                .frame(height: 1)
                .padding(.vertical, 10)
                .opacity(selected || hovering ? 1 : 0)

            HStack(spacing: 10) {
                Button(action: preview) { Label("预览", systemImage: "eye") }
                    .buttonStyle(BrandGhostButtonStyle())
                Spacer(minLength: 0)
                Button(action: decrypt) { Label("解密", systemImage: "lock.open") }
                    .buttonStyle(FileActionStyle())
            }
            .opacity(selected || hovering ? 1 : 0)
            .allowsHitTesting(selected || hovering)
            .accessibilityHidden(!selected && !hovering)
        }
        .modifier(BrowserCardSurface(selected: selected))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("验证并预览", action: preview)
            Button("解密…", action: decrypt)
            Button("在 Finder 中显示", action: reveal)
        }
    }
}

struct LibraryListRow: View {
    @State private var hovering = false
    let item: LockedItem
    let selected: Bool
    let select: () -> Void
    let preview: () -> Void
    let decrypt: () -> Void
    let reveal: () -> Void

    private var needsAttention: Bool { item.warning != nil || item.originalRetained }

    var body: some View {
        Button(action: select) {
            HStack(spacing: 12) {
                FileBadge(name: item.name, locked: true, size: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.path)
                        .font(.system(size: 9.5))
                        .foregroundStyle(EasyLockStyle.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 14)
                Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: 72, alignment: .trailing)
                FileStatusPill(locked: true, needsAttention: needsAttention)
                    .frame(width: 72, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(selectionFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(EasyLockStyle.blue)
                        .frame(width: 3, height: 20)
                        .padding(.leading, 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(item.path)
        .contextMenu {
            Button("验证并预览", action: preview)
            Button("解密…", action: decrypt)
            Button("在 Finder 中显示", action: reveal)
        }
    }

    private var selectionFill: Color {
        selected ? EasyLockStyle.blueSoft : (hovering ? EasyLockStyle.blue.opacity(0.045) : .clear)
    }
}

struct FileBadge: View {
    let name: String
    var locked = true
    var folder = false
    var size: CGFloat = 34

    private var style: FileVisualStyle { .resolve(name: name, folder: folder, locked: locked) }

    private var usesAccent: Bool { locked || folder }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
        ZStack(alignment: .bottomTrailing) {
            shape
                .fill(usesAccent ? EasyLockStyle.blueSoft : EasyLockStyle.surfaceMuted)
                .overlay {
                    shape.strokeBorder(usesAccent ? EasyLockStyle.blue.opacity(0.16) : EasyLockStyle.border, lineWidth: 1)
                }
            Image(systemName: style.symbol)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(usesAccent ? EasyLockStyle.blueDeep : EasyLockStyle.ink.opacity(0.76))
                .frame(width: size, height: size)
            if locked && size >= 48 {
                Image(systemName: "lock.fill")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(EasyLockStyle.blue, in: Circle())
                    .overlay { Circle().strokeBorder(EasyLockStyle.surface, lineWidth: 1.5) }
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

struct SelectionDot: View {
    let selected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(selected ? EasyLockStyle.blue : EasyLockStyle.borderStrong, lineWidth: 1.2)
                .frame(width: 17, height: 17)
            if selected {
                Circle()
                    .fill(EasyLockStyle.blue)
                    .frame(width: 17, height: 17)
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(EasyLockStyle.buttonText)
            }
        }
        .accessibilityHidden(true)
    }
}
