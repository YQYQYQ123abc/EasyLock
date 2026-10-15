import SwiftUI
import Quartz

struct PrivatePreviewView: View {
    @Bindable var preview: PrivatePreview
    let touchIDEnabled: Bool
    @State private var expanded = false
    @State private var availableSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1280, height: 800)
    @State private var secret = ""
    @State private var recovery = false
    @State private var chosen: URL?
    @State private var directory: URL?
    @State private var entries: [URL] = []
    @State private var browseError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "lock.shield").font(.title2).foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("私密预览").font(.caption).foregroundStyle(.secondary)
                    Text(preview.item?.name ?? "验证后查看内容")
                        .font(.headline).lineLimit(1).truncationMode(.middle)
                        .help(preview.item?.name ?? "私密预览")
                }
                Spacer()
                Button { expanded.toggle() } label: {
                    Image(systemName: expanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                }.help(expanded ? "恢复预览尺寸" : "扩大预览")
                Button("关闭") { preview.close() }.keyboardShortcut(.cancelAction)
            }
            if let root = preview.restored {
                if root.hasDirectoryPath || (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    HStack {
                        Button("上一级") { load((directory ?? root).deletingLastPathComponent()) }.disabled(directory == root || directory == nil)
                        Text(directory?.lastPathComponent ?? root.lastPathComponent).lineLimit(1)
                    }
                    HSplitView {
                        List(entries, id: \.self, selection: $chosen) { entry in
                            Label(entry.lastPathComponent, systemImage: entry.hasDirectoryPath ? "folder" : "doc")
                                .tag(entry).onTapGesture(count: 2) { if entry.hasDirectoryPath { load(entry) } }
                        }.frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                        if let chosen, !chosen.hasDirectoryPath { PreviewContent(url: chosen).id(chosen) }
                        else { ContentUnavailableView("选择文件预览", systemImage: "folder", description: Text("双击文件夹可展开内容")) }
                    }.frame(maxHeight: .infinity)
                    .onAppear { load(root) }
                } else { PreviewContent(url: root).id(root).frame(maxHeight: .infinity) }
                Label("原文件保持加密 · 关闭后清理临时副本 · 系统预览可能保留缓存", systemImage: "lock.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Label("验证后查看内容", systemImage: "lock.shield").font(.headline)
                    Text("预览会在本机临时解密整个项目，原密文不会修改。关闭或锁定应用时清理临时副本；异常退出后下次启动清理。macOS 预览或第三方预览扩展可能保留缓存，无法保证清除。").font(.callout).foregroundStyle(.secondary)
                    Picker("凭据", selection: $recovery) { Text("文件密码").tag(false); Text("恢复密钥").tag(true) }.pickerStyle(.segmented)
                    SecureField(recovery ? "对应 ELRK1 恢复密钥" : "加密时使用的密码", text: $secret).textFieldStyle(.roundedBorder)
                        .onSubmit { open() }
                    HStack {
                        Button("验证并预览", action: open).buttonStyle(BrandPrimaryButtonStyle()).disabled(secret.isEmpty)
                        if touchIDEnabled && !recovery { Button("Touch ID") { Task { await preview.openWithTouchID() } } }
                    }
                }.frame(maxWidth: 470).frame(maxWidth: .infinity).disabled(preview.busy)
                if preview.busy { ProgressView("正在验证并准备临时预览…").frame(maxWidth: .infinity) }
                Spacer()
            }
            if let message = preview.message { Text(message).font(.caption).foregroundStyle(.orange).textSelection(.enabled) }
            if let browseError { Text(browseError).font(.caption).foregroundStyle(.orange) }
        }.padding(18).frame(width: previewSize.width, height: previewSize.height)
            .onDisappear { secret = ""; chosen = nil; preview.close() }
    }
    private var previewSize: CGSize {
        let available = availableSize
        return CGSize(width: min(expanded ? 1200 : 960, available.width - 80),
                      height: min(expanded ? 860 : 680, available.height - 100))
    }
    private func open() {
        guard !secret.isEmpty, !preview.busy else { return }
        let value = secret; secret = ""
        let key = recovery
        Task { await preview.open(password: key ? "" : value, recovery: key ? value : nil) }
    }
    private func load(_ url: URL) {
        guard let root = preview.restored else { return }
        let path = url.standardizedFileURL.path
        guard path == root.path || path.hasPrefix(root.path + "/") else { return }
        do {
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [])
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            directory = url; chosen = nil; browseError = nil
        } catch { browseError = error.localizedDescription }
    }
}
private struct SecureQuickLook: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> ManagedQuickLookView { ManagedQuickLookView() }
    func updateNSView(_ view: ManagedQuickLookView, context: Context) { view.setItem(url) }
    static func dismantleNSView(_ view: ManagedQuickLookView, coordinator: ()) { view.finish() }
}


/// Common raster images stay inside the app, with a predictable fit and zoom control.
private struct PreviewContent: View {
    let url: URL
    @State private var image: NSImage?
    @State private var loaded = false
    @State private var zoom: CGFloat = 0
    var body: some View {
        VStack(spacing: 0) {
            if let image {
                HStack {
                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                    Spacer()
                    Picker("图片缩放", selection: $zoom) {
                        Text("适合窗口").tag(CGFloat(0))
                        Text("100%").tag(CGFloat(1))
                        Text("200%").tag(CGFloat(2))
                    }.labelsHidden().frame(width: 140)
                }.font(.caption).padding(10)
                Divider()
                GeometryReader { geometry in
                    let fit = min(geometry.size.width / max(1, image.size.width), geometry.size.height / max(1, image.size.height))
                    let factor = zoom == 0 ? min(1, fit) : zoom
                    ScrollView([.horizontal, .vertical]) {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .frame(width: image.size.width * factor, height: image.size.height * factor)
                            .frame(minWidth: geometry.size.width, minHeight: geometry.size.height)
                    }
                }
            } else if loaded {
                SecureQuickLook(url: url)
            } else {
                ProgressView("正在载入预览…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.primary.opacity(0.08)))
        .onAppear {
            if ["jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "bmp", "webp"].contains(url.pathExtension.lowercased()) {
                image = NSImage(contentsOf: url)
            }
            loaded = true
        }
        .onDisappear { image = nil; loaded = false }
    }
}
