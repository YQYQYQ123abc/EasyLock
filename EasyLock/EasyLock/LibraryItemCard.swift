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
    private var tint: Color { FileVisualStyle.resolve(name: item.name, folder: false, locked: true).color }
    var body: some View {
        VStack(spacing: 0) {
            Button(action: select) {
                VStack(spacing: 8) {
                    HStack {
                        FileStatusPill(locked: true, needsAttention: needsAttention)
                        Spacer()
                        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selected ? EasyLockStyle.accent : .secondary)
                            .font(.title3)
                    }
                    BrowserFileArtwork(name: item.name, folder: false, locked: true, unavailable: needsAttention)
                    Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(2)
                        .truncationMode(.middle).frame(height: 36).frame(maxWidth: .infinity)
                    Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file) + " · 密文")
                        .font(.caption).foregroundStyle(.secondary)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).help(item.name + "\n点击选择，⌘ 点击多选")
                .accessibilityLabel(item.name + (selected ? "，已选择" : ""))
            Divider().padding(.vertical, 12)
            HStack {
                Button(action: preview) { Label("预览", systemImage: "eye") }
                    .buttonStyle(.plain).foregroundStyle(EasyLockStyle.accent)
                Spacer()
                Button(action: decrypt) { Label("解密", systemImage: "lock.open") }
                    .buttonStyle(FileActionStyle())
            }.font(.system(size: 11))
                .opacity(selected || hovering ? 1 : 0)
                .allowsHitTesting(selected || hovering)
                .accessibilityHidden(!selected && !hovering)
        }
        .modifier(BrowserCardSurface(selected: selected, tint: tint))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("验证并预览", action: preview)
            Button("解密…", action: decrypt)
            Button("在 Finder 中显示", action: reveal)
        }
    }
}
