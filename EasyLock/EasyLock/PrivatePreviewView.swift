import SwiftUI
import Quartz

struct PrivatePreviewView: View {
    @Bindable var preview: PrivatePreview
    let touchIDEnabled: Bool
    @State private var didRequestTouchID = false
    @State private var showInfo = false
    @State private var secret = ""
    @State private var recovery = false
    @State private var chosen: URL?
    @State private var directory: URL?
    @State private var entries: [URL] = []
    @State private var browseError: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let root = preview.restored {
                if root.hasDirectoryPath || (try? root.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    HStack(spacing: 9) {
                        Button { load((directory ?? root).deletingLastPathComponent()) } label: {
                            Label("上一级", systemImage: "chevron.up")
                        }
                        .buttonStyle(BrandGhostButtonStyle())
                        .disabled(directory == root || directory == nil)
                        Text(directory?.lastPathComponent ?? root.lastPathComponent)
                            .font(.system(size: 11, weight: .medium))
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(entries.count) 项")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(EasyLockStyle.surfaceRaised)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                    }

                    HSplitView {
                        List(entries, id: \.self, selection: $chosen) { entry in
                            Label(entry.lastPathComponent, systemImage: entry.hasDirectoryPath ? "folder" : "doc")
                                .font(.system(size: 11.5))
                                .tag(entry)
                                .onTapGesture(count: 2) { if entry.hasDirectoryPath { load(entry) } }
                        }
                        .listStyle(.inset)
                        .scrollContentBackground(.hidden)
                        .background(EasyLockStyle.surface)
                        .frame(minWidth: 200, idealWidth: 240, maxWidth: 300)
                        .frame(maxHeight: .infinity)

                        Group {
                            if let chosen, !chosen.hasDirectoryPath {
                                PreviewContent(url: chosen).id(chosen)
                            } else {
                                ContentUnavailableView("选择文件预览", systemImage: "folder", description: Text("双击文件夹可展开内容"))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { load(root) }
                } else {
                    PreviewContent(url: root).id(root).frame(maxHeight: .infinity)
                }
                footer
            } else {
                ZStack {
                    WorkspaceBackground()
                    VStack(spacing: 0) {
                        Spacer(minLength: 24)
                        VStack(alignment: .leading, spacing: 18) {
                            HStack(spacing: 14) {
                                BrandMark(size: 64)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("验证后查看内容")
                                        .font(.system(size: 20, weight: .semibold))
                                        .tracking(-0.3)
                                    Text("内容只在本机临时解密")
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                            Text("预览会临时解密整个项目，原密文不会修改。关闭或锁定应用时清理临时副本；异常退出后下次启动清理。macOS 预览或第三方预览扩展可能保留缓存，无法保证清除。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .lineSpacing(3)

                            Picker("凭据", selection: $recovery) {
                                Text("文件密码").tag(false)
                                Text("恢复密钥").tag(true)
                            }
                            .pickerStyle(.segmented)

                            SecureField(recovery ? "对应 ELRK1 恢复密钥" : "加密时使用的密码", text: $secret)
                                .textFieldStyle(.plain)
                                .font(.system(size: 12))
                                .fieldSurface(height: 44)
                                .onSubmit { open() }

                            HStack(spacing: 9) {
                                Button("验证并预览", action: open)
                                    .buttonStyle(BrandPrimaryButtonStyle())
                                    .disabled(secret.isEmpty)
                                if touchIDEnabled && !recovery {
                                    Button { Task { await preview.openWithTouchID() } } label: {
                                        Label("Touch ID", systemImage: "touchid")
                                    }
                                    .buttonStyle(BrandSecondaryButtonStyle())
                                }
                            }
                        }
                        .padding(24)
                        .frame(maxWidth: 480)
                        .background { GlassPanel(radius: 20) }

                        if preview.busy {
                            ProgressView("正在验证并准备临时预览…")
                                .font(.system(size: 11))
                                .padding(.top, 16)
                        }
                        Spacer(minLength: 24)
                        if let message = preview.message {
                            InlineNotice(text: message)
                                .frame(maxWidth: 480)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 16)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .disabled(preview.busy)
                }
            }
            if let browseError {
                InlineNotice(text: browseError)
                    .padding(12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EasyLockStyle.background)
        .task {
            guard !didRequestTouchID else { return }
            didRequestTouchID = true
            guard touchIDEnabled, !recovery, secret.isEmpty, preview.restored == nil else { return }
            await preview.openWithTouchID()
        }
        .onDisappear { secret = ""; chosen = nil; preview.close() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("原文件保持加密", systemImage: "lock")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
            Spacer()
            Button { showInfo.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("预览与隐私说明")
            .popover(isPresented: $showInfo) {
                Text("关闭后清理应用临时副本；异常退出后下次启动清理。系统或第三方预览扩展可能保留缓存，无法保证清除。")
                    .font(.system(size: 11))
                    .padding(18)
                    .frame(width: 300)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .background(EasyLockStyle.surfaceRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
        }
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
            entries = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .sorted {
                    let leftFolder = (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    let rightFolder = (try? $1.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                    if leftFolder != rightFolder { return leftFolder }
                    return $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
                }
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
struct PreviewContent: View {
    let url: URL
    @State private var image: NSImage?
    @State private var loaded = false
    @State private var imageError = false
    var body: some View {
        VStack(spacing: 0) {
            if let image {
                RasterPreviewCanvas(image: image)
            } else if imageError {
                ContentUnavailableView("无法载入图片", systemImage: "photo", description: Text("文件可能已移动、损坏或格式不受支持。请关闭后重试。"))
            } else if loaded {
                SecureQuickLook(url: url)
            } else {
                ProgressView("正在载入预览…")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EasyLockStyle.background)
        .task(id: url) {
            image = nil; loaded = false; imageError = false
            guard RasterPreview.supports(url) else { loaded = true; return }
            let worker = Task.detached(priority: .userInitiated) { RasterPreview.load(url) }
            let result = await withTaskCancellationHandler {
                await worker.value
            } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            if let result { image = NSImage(cgImage: result, size: NSSize(width: result.width, height: result.height)) }
            else { imageError = true }
            loaded = true
        }
        .onDisappear { image = nil }
    }
}
