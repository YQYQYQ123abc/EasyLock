import SwiftUI
import AppKit

struct LocalFilesView: View {
    @Bindable var store: VaultStore
    @AppStorage("localFilesSort") private var sort = "name"
    @AppStorage("localFilesList") private var listMode = true
    @FocusState private var searchFocused: Bool
    @State private var search = ""
    @State private var filter = 0
    private var browser: LocalFilesBrowser { store.localFiles }
    private var visible: [LocalFileEntry] {
        browser.entries.filter {
            (search.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(search)) &&
            (filter == 0 || (filter == 1 && $0.state == .plain) || (filter == 2 && $0.state == .encrypted) || (filter == 3 && $0.folder))
        }.sorted {
            if $0.folder != $1.folder { return $0.folder }
            if sort == "size", $0.size != $1.size { return $0.size > $1.size }
            let order = $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent)
            return sort == "descending" ? order == .orderedDescending : order == .orderedAscending
        }
    }
    private var selected: [LocalFileEntry] { visible.filter { browser.selection.contains($0.id) && $0.state != .unavailable } }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                PageHeading(title: "本机文件",
                            subtitle: browser.directory?.lastPathComponent ?? "浏览本机 · 原地加密 · 离线管理",
                            symbol: "internaldrive")
                Spacer(minLength: 8)
                if browser.root != nil {
                    Menu {
                        Button("刷新当前目录", systemImage: "arrow.clockwise") { Task { await browser.refresh() } }.keyboardShortcut("r")
                        Button("搜索当前目录") { searchFocused = true }.keyboardShortcut("f")
                        Divider()
                        Picker("排序", selection: $sort) {
                            Text("名称 A–Z").tag("name")
                            Text("名称 Z–A").tag("descending")
                            Text("文件大小优先").tag("size")
                        }
                        Divider()
                        Button("关闭并忘记浏览位置", systemImage: "xmark.circle") { browser.forget() }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EasyLockStyle.ink)
                            .frame(width: 30, height: 30)
                            .background(EasyLockStyle.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                            }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .disabled(browser.loading)
                    .help("目录操作")
                }
                Button(browser.root == nil ? "选择文件夹…" : "更换目录…") { chooseFolder() }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(!store.canPresentPicker || browser.loading)
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)

            if browser.root != nil {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 5) {
                        navButton("chevron.left", "后退", disabled: !browser.canGoBack) {
                            search = ""; Task { await browser.back() }
                        }
                        navButton("chevron.right", "前进", disabled: !browser.canGoForward) {
                            search = ""; Task { await browser.forward() }
                        }
                        navButton("arrow.up", "上一级", disabled: browser.directory == browser.root || browser.loading) {
                            search = ""; Task { await browser.up() }
                        }
                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(.secondary)
                            Text(browser.directory?.path ?? "")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .help(browser.directory?.path ?? "")
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
                        .background(EasyLockStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

                        Picker("显示方式", selection: $listMode) {
                            Image(systemName: "square.grid.2x2").tag(false)
                            Image(systemName: "list.bullet").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 78)
                        .help("卡片 / 列表")
                    }

                    HStack(spacing: 10) {
                        searchField
                        filterPicker.frame(width: 290)
                        Spacer(minLength: 0)
                    }
                }
                .padding(.horizontal, 26)
                .padding(.bottom, 14)
            }

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)

            if let message = browser.message {
                InlineNotice(text: message)
                    .padding(.horizontal, 26)
                    .padding(.top, 12)
            }

            if browser.loading {
                ProgressView("正在读取当前目录…")
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if browser.root == nil {
                VStack(spacing: 18) {
                    BrandMark(size: 92)
                    Text("浏览本机文件")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.3)
                    Text("选择一个文件夹，在这里浏览、加密和解密。\n文件留在原处，内容只保存在你的 Mac 上。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineSpacing(4)
                    Button("选择并授权文件夹…", action: chooseFolder)
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(!store.canPresentPicker)
                }
                .padding(32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                BrowserEmptyState(
                    symbol: browser.message != nil ? "exclamationmark.folder" : search.isEmpty ? (filter == 2 ? "lock.doc" : "folder") : "magnifyingglass",
                    title: emptyTitle,
                    detail: emptyDetail,
                    actionTitle: search.isEmpty && filter == 0 ? "刷新目录" : "显示全部项目"
                ) {
                    if search.isEmpty && filter == 0 { Task { await browser.refresh() } }
                    else { search = ""; filter = 0 }
                }
            } else {
                ScrollView {
                    if listMode {
                        LazyVStack(spacing: 1) {
                            ForEach(visible) { entry in fileRow(entry) }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 224), spacing: 14)], spacing: 14) {
                            ForEach(visible) { entry in fileCard(entry) }
                        }
                        .padding(20)
                    }
                }
                .focusable()
                .onKeyPress(.space) {
                    guard selected.count == 1, store.canPresentPicker else { return .ignored }
                    store.previewLocalFile(selected[0]); return .handled
                }
            }

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)

            if visible.isEmpty {
                HStack(spacing: 8) {
                    Label(browser.root == nil ? "尚未选择目录" : "当前目录 \(browser.entries.count) 项", systemImage: "folder")
                    Spacer()
                    Text("仅显示当前目录 · 隐藏文件不显示")
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 26)
                .frame(height: 44)
                .background(EasyLockStyle.surfaceRaised)
            } else {
                HStack(spacing: 14) {
                    selectionSummary
                    Spacer(minLength: 12)
                    if !selected.isEmpty { batchActions }
                }
                .padding(.horizontal, 26)
                .frame(minHeight: 52)
                .background(EasyLockStyle.surfaceRaised)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { WorkspaceBackground() }
        .disabled(store.busy)
        .task { await browser.restore() }
        .onChange(of: store.busy) { _, busy in
            if !busy && !browser.loading { Task { await browser.refresh() } }
        }
        .onChange(of: search) { _, _ in trimSelection() }
        .onChange(of: filter) { _, _ in trimSelection() }
    }

    private func navButton(_ symbol: String, _ help: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(disabled ? EasyLockStyle.tertiary : EasyLockStyle.ink)
                .frame(width: 26, height: 26)
                .background(EasyLockStyle.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(help)
    }

    private var emptyTitle: String {
        if browser.message != nil { return "暂时无法显示目录" }
        if !search.isEmpty { return "没有找到匹配的文件" }
        switch filter {
        case 1: return "没有未加密的项目"
        case 2: return "这里还没有上锁的文件"
        case 3: return "当前目录没有子文件夹"
        default: return "这个文件夹还是空的"
        }
    }

    private var emptyDetail: String {
        if browser.message != nil { return "请检查上方提示，恢复目录访问后重新刷新。" }
        if !search.isEmpty { return "试试其他关键词，或清除搜索与筛选查看全部项目。" }
        if filter == 2 { return "切换到全部项目，选择文件或文件夹即可进行加密。" }
        if filter != 0 { return "可以切换到全部项目，或进入其他目录继续浏览。" }
        return "可以更换目录，或在 Finder 中放入文件后刷新。"
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索当前目录", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .fieldSurface(height: 34)
        .frame(maxWidth: 340)
    }

    private var filterPicker: some View {
        Picker("筛选", selection: $filter) {
            Text("全部").tag(0)
            Text("未加密").tag(1)
            Text("已上锁").tag(2)
            Text("文件夹").tag(3)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private var selectionSummary: some View {
        HStack(spacing: 10) {
            Text("\(visible.count) 项")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
            Text(selected.isEmpty ? "⌘ 点击多选" : "已选 \(selected.count) 项")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Button(selected.isEmpty ? "全选" : "取消选择") {
                browser.selection = selected.isEmpty ? Set(visible.filter { $0.state != .unavailable }.map(\.id)) : []
            }
            .buttonStyle(BrandGhostButtonStyle())
            .disabled(visible.isEmpty)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var batchActions: some View {
        HStack(spacing: 8) {
            if selected.count == 1 {
                Button("预览") { store.previewLocalFile(selected[0]) }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(!store.canPresentPicker)
            }
            Button { act(selected.filter { $0.state == .plain }) } label: {
                Label("加密所选", systemImage: "lock")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .disabled(!store.canPresentPicker || !selected.contains { $0.state == .plain })

            Button { act(selected.filter { $0.state == .encrypted }) } label: {
                Label("解密所选", systemImage: "lock.open")
            }
            .buttonStyle(BrandSecondaryButtonStyle())
            .disabled(!store.canPresentPicker || !selected.contains { $0.state == .encrypted })
        }
        .fixedSize()
    }

    private func chooseFolder() {
        guard let folder = store.chooseBrowsingFolder() else { return }
        search = ""; filter = 0
        Task { await browser.open(folder) }
    }

    private func trimSelection() { browser.selection.formIntersection(Set(visible.map(\.id))) }

    private func act(_ entries: [LocalFileEntry]) {
        guard store.canPresentPicker, !entries.isEmpty else { return }
        store.prepareSources(entries.map(\.url))
    }

    private func select(_ entry: LocalFileEntry) {
        guard entry.state != .unavailable else { return }
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if browser.selection.contains(entry.id) { browser.selection.remove(entry.id) }
            else { browser.selection.insert(entry.id) }
        } else { browser.selection = [entry.id] }
    }

    @ViewBuilder private func itemMenu(_ entry: LocalFileEntry) -> some View {
        Button("预览") { store.previewLocalFile(entry) }
            .disabled(entry.state == .unavailable || !store.canPresentPicker)
        if entry.folder && entry.state != .unavailable {
            Button("进入文件夹") { search = ""; Task { await browser.load(entry.url) } }
        }
        Button(entry.state == .encrypted ? "解密…" : "加密…") { act([entry]) }
            .disabled(entry.state == .unavailable || !store.canPresentPicker)
        Divider()
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
    }

    private func fileRow(_ entry: LocalFileEntry) -> some View {
        let locked = entry.state == .encrypted
        let unavailable = entry.state == .unavailable
        let isSelected = browser.selection.contains(entry.id)
        return HStack(spacing: 11) {
            Button { select(entry) } label: {
                HStack(spacing: 10) {
                    SelectionDot(selected: isSelected)
                    FileBadge(name: entry.url.lastPathComponent, locked: locked, folder: entry.folder, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.url.lastPathComponent)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(entry.reason ?? (entry.folder ? "文件夹" : ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)))
                            .font(.system(size: 9.5))
                            .foregroundStyle(entry.reason == nil ? EasyLockStyle.tertiary : EasyLockStyle.warning)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(unavailable)

            FileStatusPill(locked: locked, needsAttention: unavailable)
            Text(entry.folder ? "文件夹" : ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
            Button { store.previewLocalFile(entry) } label: {
                Image(systemName: "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(EasyLockStyle.ink)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .disabled(unavailable || !store.canPresentPicker)
            .help("预览")
            .accessibilityLabel("预览")

            Menu { itemMenu(entry) } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? EasyLockStyle.ink.opacity(0.055) : .clear,
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .help(entry.reason ?? entry.url.lastPathComponent)
        .contextMenu { itemMenu(entry) }
    }

    private func fileCard(_ entry: LocalFileEntry) -> some View {
        let locked = entry.state == .encrypted
        let unavailable = entry.state == .unavailable
        let isSelected = browser.selection.contains(entry.id)
        return VStack(spacing: 10) {
            Button { select(entry) } label: {
                VStack(spacing: 9) {
                    HStack {
                        FileStatusPill(locked: locked, needsAttention: unavailable)
                        Spacer()
                        SelectionDot(selected: isSelected)
                    }
                    BrowserFileArtwork(name: entry.url.lastPathComponent,
                                       folder: entry.folder,
                                       locked: locked,
                                       unavailable: unavailable)
                    Text(entry.url.lastPathComponent)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .multilineTextAlignment(.center)
                        .frame(height: 34, alignment: .top)
                        .frame(maxWidth: .infinity)
                    Text(entry.reason ?? (entry.folder ? "文件夹" : ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)))
                        .font(.system(size: 10))
                        .foregroundStyle(entry.reason == nil ? EasyLockStyle.secondary : EasyLockStyle.warning)
                        .lineLimit(2)
                        .frame(height: 26, alignment: .top)
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(unavailable)
            .help(entry.reason ?? entry.url.lastPathComponent)

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)

            HStack(spacing: 8) {
                if entry.folder && !unavailable {
                    Button { search = ""; Task { await browser.load(entry.url) } } label: {
                        Label("打开", systemImage: "folder")
                    }
                    .buttonStyle(BrandGhostButtonStyle())
                } else {
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([entry.url])
                    } label: {
                        Label("定位", systemImage: "arrow.up.forward.square")
                    }
                    .buttonStyle(BrandGhostButtonStyle())
                    .help("在 Finder 中显示")
                }
                Button { store.previewLocalFile(entry) } label: {
                    Image(systemName: "eye")
                        .font(.system(size: 11))
                        .foregroundStyle(EasyLockStyle.ink)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help("预览（空格键）")
                .accessibilityLabel("预览")
                .disabled(unavailable || !store.canPresentPicker)

                Spacer(minLength: 4)
                Button { act([entry]) } label: {
                    Label(locked ? "解密" : "加密", systemImage: locked ? "lock.open" : "lock")
                }
                .buttonStyle(FileActionStyle())
                .disabled(unavailable || !store.canPresentPicker)
            }
        }
        .modifier(BrowserCardSurface(selected: isSelected))
        .contextMenu { itemMenu(entry) }
    }
}
