import SwiftUI

final class LocalPreviewItem {
    let url: URL
    let folder: Bool
    private let access: ScopedFileAccess
    init(url: URL, folder: Bool, root: URL) {
        self.url = url; self.folder = folder
        access = ScopedFileAccess([root, url])
    }
}

struct LocalPreviewView: View {
    let item: LocalPreviewItem
    let close: () -> Void
    @State private var entries: [LocalFileEntry] = []
    @State private var loading = true
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if item.folder {
                if loading {
                    ProgressView("正在读取文件夹…")
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error {
                    ContentUnavailableView("无法预览", systemImage: "exclamationmark.folder", description: Text(error))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(EasyLockStyle.surfaceMuted)
                                .overlay {
                                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                                        .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                                }
                                .overlay {
                                    RoundedRectangle(cornerRadius: 25, style: .continuous)
                                        .inset(by: 1)
                                        .strokeBorder(Color.white.opacity(0.6), lineWidth: 1)
                                }
                                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                            Image(systemName: "folder")
                                .font(.system(size: 48, weight: .light))
                                .foregroundStyle(EasyLockStyle.ink.opacity(0.7))
                        }
                        .frame(width: 112, height: 112)

                        Text(item.url.lastPathComponent)
                            .font(.system(size: 20, weight: .semibold))
                            .multilineTextAlignment(.center)
                        Text("\(entries.count) 个可见项目")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(item.url.path)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Text("进入文件夹后，可选择其中的文件进行预览。")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                Text("仅统计直接子项 · 隐藏项目不显示")
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
                    .frame(height: 30)
                    .frame(maxWidth: .infinity)
                    .background(EasyLockStyle.surfaceRaised)
            } else {
                PreviewContent(url: item.url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { WorkspaceBackground() }
        .task {
            guard item.folder else { return }
            let url = item.url
            do { entries = try await Task.detached { try LocalFilesBrowser.readDirectory(url) }.value }
            catch { self.error = error.localizedDescription }
            loading = false
        }
    }
}
