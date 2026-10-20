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
                if loading { ProgressView("正在读取文件夹…").frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let error { ContentUnavailableView("无法预览", systemImage: "exclamationmark.folder", description: Text(error)) }
                else {
                    VStack(spacing: 18) {
                        Image(systemName: "folder.fill").font(.system(size: 80, weight: .light)).foregroundStyle(.blue)
                        Text(item.url.lastPathComponent).font(.title2.weight(.semibold)).multilineTextAlignment(.center)
                        Text("\(entries.count) 个可见项目").foregroundStyle(.secondary)
                        Text(item.url.path).font(.caption).foregroundStyle(.secondary).lineLimit(2).truncationMode(.middle)
                        Text("进入文件夹后，可选择其中的文件进行预览。").font(.caption).foregroundStyle(.secondary)
                    }.padding(32).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else { PreviewContent(url: item.url) }
            if item.folder {
                Text("仅统计直接子项 · 隐藏项目不显示").font(.system(size: 10)).foregroundStyle(.secondary).frame(height: 28)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                guard item.folder else { return }
                let url = item.url
                do { entries = try await Task.detached { try LocalFilesBrowser.readDirectory(url) }.value }
                catch { self.error = error.localizedDescription }
                loading = false
            }
    }
}
