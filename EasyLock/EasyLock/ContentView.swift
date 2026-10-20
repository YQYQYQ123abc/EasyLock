import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum Section: String, CaseIterable, Identifiable {
    case files = "加密文件", computer = "本机文件", security = "安全与解锁", general = "常规", recovery = "恢复与检查", theme = "主题", about = "关于"
    #if EASYLOCK_ENABLE_LICENSING
    case membership = "许可证"
    #endif
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .files: "lock.doc"
        case .computer: "internaldrive"
        case .security: "lock.shield"
        case .general: "gearshape"
        case .recovery: "arrow.counterclockwise.circle"
        case .theme: "paintpalette"
        case .about: "info.circle"
        #if EASYLOCK_ENABLE_LICENSING
        case .membership: "seal"
        #endif
        }
    }
}

struct ContentView: View {
    @Bindable var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearanceMode") private var appearanceMode = "system"
    @AppStorage("libraryGrid") private var libraryGrid = false
    @State private var showFileDetails = false
    @AppStorage("widgetShowCount") private var widgetShowCount = false
    @State private var showPasswordApp = false
    @State private var showHelp = false
    @State private var requests = ExternalFileRequests.shared
    @State private var section: Section = .files
    @State private var search = ""
    @State private var attentionOnly = false
    @State private var input = ""
    @State private var confirmation = ""
    @State private var decryptPassword = ""
    @State private var didRequestWelcomeTouchID = false
    @State private var currentPasswordVerifiedByTouchID = false
    @State private var didRequestDecryptionTouchID = false
    @State private var dropTargeted = false
    @State private var showPasswordChange = false
    @State private var resettingPassword = false
    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var newConfirmation = ""
    @State private var changeAcknowledged = false
    @State private var showRecoverySetup = false
    @State private var recoveryDraft = ""
    @State private var recoveryConfirmation = ""
    @State private var recoveryExported = false
    @State private var recoveryInput = ""
    @State private var useRecovery = false
    @State private var restoreElsewhere = false
    @State private var restoreFolder: URL?
    private let accent = EasyLockStyle.accent
    private let surface = Color(nsColor: .controlBackgroundColor)

    var body: some View {
        Group {
            if store.password.isEmpty {
                welcome.onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { store.acceptDrop($0) }
            } else {
                NavigationSplitView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.badge.lock").font(.title2).foregroundStyle(accent)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("EasyLock").font(.system(size: 17, weight: .semibold))
                                Text("本机文件保护").font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(20)
                        List(selection: $section) {
                            ForEach([Section.files, .computer]) { item in
                                Label(item.rawValue, systemImage: item.icon)
                                    .font(.callout).padding(.vertical, 7).tag(item)
                            }
                        }.listStyle(.sidebar).scrollContentBackground(.hidden)
                        VStack(alignment: .leading, spacing: 12) {
                            Button { section = .security } label: {
                                Label("设置", systemImage: "gearshape").frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(section != .files && section != .computer ? accent.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).accessibilityAddTraits(section != .files && section != .computer ? .isSelected : [])
                            Label("免费离线 · 内容不上传", systemImage: "internaldrive")
                                .font(.caption).foregroundStyle(.secondary)

                        }.padding(18)
                    }
                    .background { GlassPanel(radius: 0) }
                    .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 280)
                } detail: {
                    workspaceDetail
                }.navigationSplitViewStyle(.balanced)
            }
        }
        .background { WorkspaceBackground() }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: section)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: dropTargeted)
        .onAppear {
            store.refreshTouchIDAvailability()
            if let message = store.preview.message { store.notice = message }
        }
        .task(id: externalRequestState) {
            guard !externalRequestsBlocked else { return }
            if let shortcut = requests.shortcut, !store.password.isEmpty || !shortcut.hasPrefix("add-") {
                _ = requests.consumeShortcut()
                switch shortcut {
                case "settings": section = .security
                case "add-file": section = .files; store.chooseSources()
                case "add-folder": section = .files; store.chooseSources(foldersOnly: true)
                default: section = .files
                }
                return
            }
            requests.consumeNext { request in
                switch request.kind {
                case .openEncrypted: store.receive(request.urls)
                case .finderSelection: store.prepareSources(request.urls)
                }
            }
        }
        .onChange(of: store.sessionRevision) { _, _ in
            do {
                input = ""; confirmation = ""; decryptPassword = ""; currentPassword = ""
                newPassword = ""; newConfirmation = ""; recoveryInput = ""
                recoveryDraft = ""; recoveryConfirmation = ""
                currentPasswordVerifiedByTouchID = false
                showPasswordChange = false; showRecoverySetup = false; showPasswordApp = false
            }
        }
        .preferredColorScheme(appearanceMode == "dark" ? .dark : appearanceMode == "light" ? .light : nil)
        .tint(accent)
        .groupBoxStyle(BrandGroupBoxStyle())
        .frame(minWidth: 980, minHeight: 660)
        .toolbar {
            Button { showHelp = true } label: { Label("使用帮助", systemImage: "questionmark.circle") }
                .disabled(store.busy)

            if !store.password.isEmpty {
                Button { store.lockSession(); input = ""; confirmation = "" } label: { Label("锁定应用", systemImage: "lock") }.disabled(store.busy)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.busy {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text(store.password.isEmpty && !store.guestDecrypt ? "正在安全结束当前操作…" : store.progress).font(.callout).lineLimit(1)
                        Spacer()
                        if store.batchTotal > 0 {
                            Button(store.cancellationRequested ? "正在安全停止…" : "取消任务") { store.cancelBatch() }.disabled(store.cancellationRequested)
                        }
                    }
                    if let update = store.operationUpdate, !store.password.isEmpty || store.guestDecrypt {
                        HStack {
                            Text(update.phase)
                            Spacer()
                            Text(store.phaseEstimate)
                            if update.total > 0 {
                                Text("\(ByteCountFormatter.string(fromByteCount: update.completed, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: update.total, countStyle: .file))")
                            }
                        }.font(.caption).foregroundStyle(.secondary)
                        if update.total > 0 { ProgressView(value: min(Double(update.completed) / Double(update.total), 1)) }
                    }
                    if store.batchTotal > 0 { Text("已完成 \(store.batchCompleted)/\(store.batchTotal) 项 · 提交替换期间会先完成当前步骤").font(.caption2).foregroundStyle(.secondary) }
                }.padding(14).background(.bar)
            }
        }
        .sheet(item: Binding(get: {
            let panel = store.panels.presented
            return panel == .preview || panel == .localPreview ? nil : panel
        }, set: { value in
            if value == nil, let panel = store.panels.current { clearRequest(panel); store.panels.dismiss() }
        }), onDismiss: {
            if let panel = store.panels.didDismiss() { clearRequest(panel) }
        }) { panel in
            VStack(spacing: 0) {
                if panel != .notice, let notice = store.notice {
                    HStack(alignment: .top) {
                        Image(systemName: "info.circle")
                        Text(notice).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button("知道了") { store.notice = nil }
                    }.padding(16).frame(maxWidth: 540).background(Color.secondary.opacity(0.08))
                }
                panelContent(panel)
            }.tint(accent).background(EasyLockStyle.background)
        }
        .background {
            PreviewWindow(panel: store.panels.presented,
                          title: store.preview.item?.name ?? store.localPreview?.url.lastPathComponent ?? "预览",
                          content: {
                AnyView(Group {
                    if store.panels.current == .preview {
                        PrivatePreviewView(preview: store.preview, touchIDEnabled: store.touchIDEnabled && store.touchIDAvailable)
                    } else if let item = store.localPreview {
                        LocalPreviewView(item: item) { store.localPreview = nil }
                    }
                }.tint(accent).preferredColorScheme(appearanceMode == "dark" ? .dark : appearanceMode == "light" ? .light : nil))
            }, closed: {
                if let panel = store.panels.current, panel == .preview || panel == .localPreview {
                    clearRequest(panel)
                    store.panels.didDismiss()
                }
            }).frame(width: 0, height: 0)
        }
        .task(id: panelState) {
            if !store.nativePanelActive { store.panels.reconcile(requestedPanels) }
        }
        .onDisappear { store.preview.close(); store.panels.didDismiss() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.preview.close() }
        .onChange(of: store.preview.message) { _, message in
            if !store.preview.requested, let message { store.notice = message }
        }
    }

    private var workspaceDetail: some View {
        VStack(spacing: 0) {
            Group {
                if store.password.isEmpty { welcome }
                else {
                    switch section {
                    case .files: library
                    case .computer: LocalFilesView(store: store)
                    case .security, .general, .recovery, .theme, .about: settings
                    #if EASYLOCK_ENABLE_LICENSING
                    case .membership: membership
                    #endif
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if dropTargeted && !store.busy {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                            .padding(10).background(accent.opacity(0.025)).allowsHitTesting(false)
                    }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { store.acceptDrop($0) }
        }
    }


    private var requestedPanels: [PanelCoordinator.Panel] {
        var result: [PanelCoordinator.Panel] = []
        if store.notice != nil { result.append(.notice) }
        if store.preview.requested { result.append(.preview) }
        if store.localPreview != nil { result.append(.localPreview) }
        if showHelp { result.append(.help) }
        if showPasswordChange { result.append(.passwordChange) }
        if showRecoverySetup { result.append(.recoverySetup) }
        if showPasswordApp { result.append(.passwordApp) }
        if store.showResults { result.append(.results) }
        if store.showUnlock && (!store.password.isEmpty || store.guestDecrypt) { result.append(.decrypt) }
        if !store.pendingURLs.isEmpty && !store.password.isEmpty { result.append(.encrypt) }
        return result
    }
    private var panelState: String {
        requestedPanels.map(\.rawValue).joined(separator: ",") + "-\(store.panels.occupied)-\(store.nativePanelActive)"
    }
    @ViewBuilder private func panelContent(_ panel: PanelCoordinator.Panel) -> some View {
        switch panel {
        case .notice:
            VStack(alignment: .leading, spacing: 18) {
                Label("EasyLock", systemImage: "info.circle").font(.title2.bold())
                ScrollView { Text(store.notice ?? "").textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 240)
                HStack { Spacer(); Button("知道了") { store.notice = nil }.keyboardShortcut(.defaultAction) }
            }.padding(28).frame(width: 460)
        case .localPreview: if let item = store.localPreview { LocalPreviewView(item: item) { store.localPreview = nil } }
        case .preview: PrivatePreviewView(preview: store.preview, touchIDEnabled: store.touchIDEnabled && store.touchIDAvailable)
        case .encrypt: encryptionSheet
        case .decrypt: decryptionSheet
        case .results: resultsSheet
        case .help: UsageHelpView()
        case .passwordApp: PasswordAppSheet(password: store.password)
        case .passwordChange: passwordChangeSheet
        case .recoverySetup: recoverySetupSheet
        }
    }
    private func clearRequest(_ panel: PanelCoordinator.Panel) {
        switch panel {
        case .notice: store.notice = nil
        case .localPreview: store.localPreview = nil
        case .preview: store.preview.close()
        case .encrypt: store.pendingURLs = []
        case .decrypt: store.showUnlock = false; decryptPassword = ""; recoveryInput = ""
        case .results: store.showResults = false
        case .help: showHelp = false
        case .passwordApp: showPasswordApp = false
        case .passwordChange: showPasswordChange = false
        case .recoverySetup:
            showRecoverySetup = false; recoveryDraft = ""; recoveryConfirmation = ""; recoveryExported = false
        }
    }

    private var externalRequestsBlocked: Bool {
        store.localPreview != nil || store.preview.requested || store.preview.busy || store.panels.occupied || store.nativePanelActive || store.busy || store.loadingDrop || !store.pendingURLs.isEmpty || store.showUnlock ||
        store.showResults || store.notice != nil || showPasswordChange || showRecoverySetup || showHelp || showPasswordApp
    }
    private var externalRequestState: String { "\(requests.revision)-\(externalRequestsBlocked)-\(store.password.isEmpty)" }

    private func authenticate() {
        Task {
            let isNew = !store.configured
            if await store.authenticate(input, confirmation: confirmation) {
                input = ""; confirmation = ""
                if isNew && store.pendingURLs.isEmpty && !store.showUnlock && requests.count == 0 { showPasswordApp = true }
            }
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            BrandMark(size: 96).shadow(color: accent.opacity(0.18), radius: 18, y: 9)
            if !store.pendingURLs.isEmpty {
                Label("已收到 \(store.pendingURLs.count) 个文件或文件夹", systemImage: "doc.badge.clock")
                    .font(.headline).foregroundStyle(accent)
                Text(store.configured ? "请先解锁 EasyLock，随后确认加密。" : "请先设置主密码，随后确认加密。")
                    .font(.callout).foregroundStyle(.secondary)
                Button("取消本次加密") { store.pendingURLs = [] }
            }
            Text(store.configured ? "欢迎回来" : "给文件一把专属的锁")
                .font(.system(size: 24, weight: .semibold))
            Text(store.configured ? "输入主密码，或使用 Touch ID" : "设置主密码，开始在本机保护文件")
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                SecureField(store.configured ? "主密码" : "至少 10 个字符的主密码", text: $input)
                    .textFieldStyle(.plain).onSubmit { if !input.isEmpty && !store.busy { authenticate() } }
                    .accessibilityLabel(store.configured ? "主密码" : "设置主密码")
                Button(action: authenticate) {
                    Image(systemName: "arrow.right").font(.headline).foregroundStyle(.white)
                        .frame(width: 34, height: 34).background(EasyLockStyle.buttonFill, in: Circle())
                }.buttonStyle(.plain).disabled(store.busy || input.isEmpty)
                    .accessibilityLabel(store.configured ? "解锁 EasyLock" : "设置密码并开始")
            }.padding(.leading, 16).padding(5).background(surface, in: Capsule())
                .overlay(Capsule().stroke(EasyLockStyle.border)).frame(width: 330).padding(.top, 10)
            if !store.configured {
                SecureField("再次输入密码", text: $confirmation).textFieldStyle(.roundedBorder)
                    .frame(width: 330).onSubmit { if !store.busy && !input.isEmpty { authenticate() } }
                Text("请保存好密码；未启用恢复密钥的文件无法找回密码。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !store.pendingURLs.isEmpty || store.showUnlock {
                Label("已接收文件，解锁后继续处理", systemImage: "tray.and.arrow.down").font(.caption).foregroundStyle(accent)
            }
            HStack(spacing: 18) {
                if store.configured && store.touchIDEnabled {
                    Button { Task { await store.unlockWithTouchID() } } label: { Label("Touch ID", systemImage: "touchid") }
                        .disabled(store.busy || !store.touchIDAvailable).help(store.touchIDReason)
                }
                if store.configured && store.recoveryPublicKey != nil {
                    Button("使用恢复密钥") { resettingPassword = true; showPasswordChange = true }
                }
            }.buttonStyle(.plain).foregroundStyle(accent)
            Button("不登录，直接解密文件") { store.independentDecrypt() }
                .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                .disabled(store.busy)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity).background { VaultBackground() }
            .task {
                guard !didRequestWelcomeTouchID else { return }
                didRequestWelcomeTouchID = true
                store.refreshTouchIDAvailability()
                guard store.configured, store.touchIDEnabled, store.touchIDAvailable,
                      !store.busy, !store.panels.occupied, !store.guestDecrypt, input.isEmpty else { return }
                await store.unlockWithTouchID()
            }
            .onDisappear { didRequestWelcomeTouchID = false }
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack {
                PageHeading(title: "加密文件", subtitle: "\(store.items.count) 项本机记录 · 文件保存在原位置", symbol: "lock.doc")
                Spacer()
                Picker("显示方式", selection: $libraryGrid) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }.pickerStyle(.segmented).frame(width: 88).help("切换卡片或列表")
            }.padding(.horizontal, 24).padding(.vertical, 14)
            Divider()
            if libraryGrid { gridLibrary } else { listLibrary }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { WorkspaceBackground() }
    }

    private var gridLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索名称或路径", text: $search).textFieldStyle(.plain)
                }.padding(9).background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                Picker("筛选", selection: $attentionOnly) {
                    Text("全部").tag(false); Text("需检查").tag(true)
                }.pickerStyle(.segmented).frame(width: 155)
                Menu {
                    Button("添加文件…") { store.chooseSources() }
                    Button("添加文件夹…") { store.chooseSources(foldersOnly: true) }
                    Button("导入已有密文…") { store.importFiles() }
                    if !store.outcomes.isEmpty { Button("上次任务结果") { store.showResults = true } }
                } label: { Label("添加", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().padding(10)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            }.padding(.horizontal, 24).padding(.vertical, 14)
            if store.recoveryPublicKey == nil || !store.recoveries.isEmpty || !store.recoveryErrors.isEmpty {
                HStack {
                    Label(store.recoveryPublicKey == nil ? "建议创建恢复密钥，保护之后新加密的文件" : "有恢复任务需要检查", systemImage: "exclamationmark.shield")
                    Spacer()
                    Button("安全设置") { section = .security }
                }.font(.caption).foregroundStyle(.orange).padding(.horizontal, 22).padding(.bottom, 12)
            }
            if store.items.isEmpty { dropZone.padding(22) }
            else if filteredItems.isEmpty {
                BrowserEmptyState(symbol: "magnifyingglass", title: "没有匹配的记录", detail: "试试其他名称，或清除筛选查看所有加密文件。", actionTitle: "显示全部记录") { search = ""; attentionOnly = false }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 18) {
                        ForEach(filteredItems) { item in
                            LibraryItemCard(item: item, selected: store.selection.contains(item.id),
                                touchID: store.touchIDEnabled && store.touchIDAvailable,
                                select: { selectCard(item) },
                                preview: { store.selection = [item.id]; previewSelection() },
                                decrypt: { store.selection = [item.id]; decryptPassword = ""; store.showUnlock = true },
                                reveal: { NSWorkspace.shared.activateFileViewerSelecting([item.resolve()]) })
                        }
                    }.padding(.horizontal, 22).padding(.bottom, 22)
                }.focusable()
                .onKeyPress(.space) {
                    guard selectedItems.count == 1, !externalRequestsBlocked else { return .ignored }
                    previewSelection(); return .handled
                }
            }
            Divider()
            HStack {
                Button("全选") { store.selection = Set(filteredItems.map(\.id)) }.disabled(filteredItems.isEmpty)
                if !store.selection.isEmpty {
                    Button("清除") { store.selection = [] }
                    Button("查看详情") { libraryGrid = false; showFileDetails = true }
                    Button("解密所选…") { decryptPassword = ""; store.showUnlock = true }
                }
                Spacer()
                Text("\(filteredItems.count) 项 · 已选 \(store.selection.count) 项").foregroundStyle(.secondary)
            }.buttonStyle(.plain).font(.caption).padding(.horizontal, 22).padding(.vertical, 14)
                .background(surface.opacity(0.7))
        }.disabled(store.busy)
        .onChange(of: search) { _, _ in retainVisibleSelection() }
        .onChange(of: attentionOnly) { _, _ in retainVisibleSelection() }
    }

    private func selectCard(_ item: LockedItem) {
        if NSApp.currentEvent?.modifierFlags.contains(.command) == true {
            if store.selection.contains(item.id) { store.selection.remove(item.id) }
            else { store.selection.insert(item.id) }
        } else { store.selection = [item.id] }
    }

    private var listLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索加密文件", text: $search).textFieldStyle(.plain)
                }.padding(9).background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                if attentionOnly || store.items.contains(where: { $0.warning != nil || $0.originalRetained }) {
                    Toggle("仅看需检查", isOn: $attentionOnly).toggleStyle(.checkbox)
                }
                Menu {
                    Button("添加文件…") { store.chooseSources() }
                    Button("添加文件夹…") { store.chooseSources(foldersOnly: true) }
                    Button("导入已有密文…") { store.importFiles() }
                    if !store.outcomes.isEmpty { Button("上次任务结果") { store.showResults = true } }
                } label: { Label("添加文件", systemImage: "plus") }.fixedSize()
            }.padding(.horizontal, 24).padding(.vertical, 12)
            if store.recoveryPublicKey == nil || !store.recoveries.isEmpty || !store.recoveryErrors.isEmpty {
                HStack {
                    Label(!store.recoveries.isEmpty || !store.recoveryErrors.isEmpty ? "有未完成任务需要检查" : "尚未创建恢复密钥", systemImage: "exclamationmark.shield")
                    Spacer()
                    Button("查看设置") { section = .security }
                }.font(.caption).foregroundStyle(.orange).padding(.horizontal, 24).padding(.bottom, 12)
            }
            if store.items.isEmpty { dropZone.padding(24) }
            else if filteredItems.isEmpty {
                BrowserEmptyState(symbol: "magnifyingglass", title: "没有匹配的文件", detail: "换一个关键词，或查看全部记录。", actionTitle: "显示全部") { search = ""; attentionOnly = false }
            } else {
                HStack(spacing: 0) {
                    List(filteredItems, selection: $store.selection) { item in
                        HStack(spacing: 12) {
                            fileBadge(item, size: 32)
                            Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 12)
                            Text(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            Label(item.warning != nil || item.originalRetained ? "需检查" : "已加密", systemImage: item.warning != nil || item.originalRetained ? "exclamationmark.circle" : "lock")
                                .font(.caption).foregroundStyle(item.warning != nil || item.originalRetained ? Color.orange : .secondary)
                                .frame(width: 76, alignment: .trailing)
                        }.padding(.vertical, 7).tag(item.id).help(item.path)
                        .contextMenu {
                            Button("验证并预览") { store.selection = [item.id]; previewSelection() }
                            Button("解密…") { store.selection = [item.id]; decryptPassword = ""; store.showUnlock = true }
                            Button("查看详情") { store.selection = [item.id]; showFileDetails = true }
                            Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.resolve()]) }
                        }
                    }.listStyle(.inset).scrollContentBackground(.hidden)
                        .onKeyPress(.space) {
                            guard selectedItems.count == 1, !externalRequestsBlocked else { return .ignored }
                            previewSelection(); return .handled
                        }
                    if showFileDetails && !selectedItems.isEmpty {
                        Divider()
                        fileDetails.frame(width: 340)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Text("\(filteredItems.count) 项").foregroundStyle(.secondary)
                if !store.selection.isEmpty {
                    Text("已选 \(store.selection.count) 项").foregroundStyle(.secondary)
                    Button("取消选择") { store.selection = [] }
                } else if !filteredItems.isEmpty {
                    Button("全选") { store.selection = Set(filteredItems.map(\.id)) }
                }
                Spacer()
                if !selectedItems.isEmpty {
                    Button(showFileDetails ? "收起详情" : "详情") { showFileDetails.toggle() }
                    if selectedItems.count == 1 { Button("预览", action: previewSelection) }
                    Button("解密…") { decryptPassword = ""; store.showUnlock = true }.buttonStyle(.borderedProminent)
                }
            }.font(.callout).padding(.horizontal, 24).frame(height: 52)
        }.disabled(store.busy)
        .onChange(of: search) { _, _ in retainVisibleSelection() }
        .onChange(of: attentionOnly) { _, _ in retainVisibleSelection() }
    }

    private func previewSelection() {
        guard !externalRequestsBlocked, let item = selectedItems.first, selectedItems.count == 1 else { return }
        store.preview.begin(item)
    }
    private func retainVisibleSelection() {
        store.selection.formIntersection(Set(filteredItems.map(\.id)))
    }
    private var selectedItems: [LockedItem] { store.items.filter { store.selection.contains($0.id) } }
    private func fileBadge(_ item: LockedItem, size: CGFloat) -> some View {
        let visual = FileVisualStyle.resolve(name: item.name, folder: false, locked: true)
        return Image(systemName: visual.symbol)
            .font(.system(size: size > 40 ? 14 : 10, weight: .bold, design: .rounded))
            .foregroundStyle(visual.color).frame(width: size, height: size)
            .background(visual.color.opacity(0.12), in: RoundedRectangle(cornerRadius: size / 4))
            .accessibilityHidden(true)
    }
    private var fileDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let item = selectedItems.first, selectedItems.count == 1 {
                    HStack(spacing: 16) {
                        fileBadge(item, size: 64)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(item.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                            Label(item.warning != nil || item.originalRetained ? "需要检查" : "密文记录", systemImage: item.warning != nil || item.originalRetained ? "exclamationmark.triangle" : "lock.fill")
                                .font(.caption.weight(.semibold)).foregroundStyle(item.warning != nil || item.originalRetained ? Color.orange : accent)
                                .padding(.horizontal, 10).padding(.vertical, 4).background(accent.opacity(0.08), in: Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        Button("解密…") { decryptPassword = ""; store.showUnlock = true }.buttonStyle(BrandPrimaryButtonStyle())
                        Button { previewSelection() } label: { Label("预览", systemImage: "eye") }.help("选择文件后按空格预览")
                        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([item.resolve()]) }
                    }
                    if let warning = item.warning { Text(warning).font(.callout).foregroundStyle(.orange) }
                    if item.originalRetained { Label("可能仍有明文副本，请在 Finder 中检查。", systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange) }
                    VStack(spacing: 0) {
                        detailRow("位置", value: item.path)
                        detailRow("密文大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                        detailRow("登记时间", value: item.date.formatted(date: .abbreviated, time: .shortened))
                        detailRow("恢复凭据", value: "加密时的密码，或当时启用的恢复密钥")
                    }
                    Text("此处展示本机登记信息，不代表已重新校验文件。解密时会验证密文完整性。").font(.caption).foregroundStyle(.secondary)
                } else if !selectedItems.isEmpty {
                    Label("已选择 \(selectedItems.count) 个项目", systemImage: "doc.on.doc").font(.title2.weight(.semibold))
                    Text("批量解密将使用同一凭据；使用不同密码的文件请分批处理。").foregroundStyle(.secondary)
                    Button("解密所选…") { decryptPassword = ""; store.showUnlock = true }.buttonStyle(BrandPrimaryButtonStyle())
                    ForEach(selectedItems) { Text($0.name).lineLimit(2) }
                } else {
                    Image(systemName: "lock.doc").font(.system(size: 48, weight: .light)).foregroundStyle(accent)
                    Text("选择文件，查看详情").font(.title2.weight(.semibold))
                    Text("按住 ⌘ 可选择多个项目。也可以将文件或文件夹拖到窗口中添加。").foregroundStyle(.secondary)
                }
                Divider()
                Label("修改后缀不会解密；无法双击打开时，请拖回 EasyLock。", systemImage: "info.circle")
                    .font(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(30)
        }.frame(maxWidth: .infinity, maxHeight: .infinity).background(surface)
    }
    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text(title).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
        }.font(.callout).padding(.vertical, 11).overlay(alignment: .bottom) { Divider() }
    }

    private var dropZone: some View {
        VStack(spacing: store.items.isEmpty ? 17 : 10) {
            if store.items.isEmpty {
                Image(systemName: "lock.doc").font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary).padding(.bottom, 8).accessibilityHidden(true)
            }
            HStack(spacing: 9) {
                if !store.items.isEmpty { Image(systemName: "arrow.down.doc").foregroundStyle(accent) }
                Text(dropTargeted ? "松开鼠标，添加到 EasyLock" : "拖入文件或文件夹")
                    .font(.system(size: store.items.isEmpty ? 20 : 15, weight: .medium))
            }
            if store.items.isEmpty {
                Text("无需移动文件的位置，加密后在原处上锁。\n已有加密文件会自动进入解密流程。")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            }
            HStack(spacing: 10) {
                Button { store.chooseSources() } label: { Label("添加文件", systemImage: "doc.badge.plus") }
                Button { store.chooseSources(foldersOnly: true) } label: { Label("添加文件夹", systemImage: "folder.badge.plus") }
            }.controlSize(.large)
            if store.items.isEmpty {
                Button("导入已有加密文件") { store.importFiles() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary).padding(.top, 3)
            }
        }.padding(store.items.isEmpty ? 30 : 16).frame(maxWidth: .infinity, maxHeight: store.items.isEmpty ? .infinity : nil)
            .background(dropTargeted ? EasyLockStyle.secondary.opacity(0.13) : surface, in: RoundedRectangle(cornerRadius: 24))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(dropTargeted ? accent : EasyLockStyle.border, style: StrokeStyle(lineWidth: 1, dash: dropTargeted ? [7, 5] : [])))

            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: dropTargeted)
    }

    private var filteredItems: [LockedItem] {
        store.items.filter {
            (!attentionOnly || $0.warning != nil || $0.originalRetained) &&
            (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search))
        }
    }

    private func beginRecoverySetup() {
        recoveryDraft = RecoveryKey.generate(); recoveryConfirmation = ""; recoveryExported = false; showRecoverySetup = true
    }
    private var settings: some View {
        VStack(spacing: 0) {
            HStack {
                Text("设置").font(.title2.weight(.semibold))
                Spacer()
                Picker("设置分类", selection: $section) {
                    Text("安全").tag(Section.security)
                    Text("通用").tag(Section.general)
                    Text("关于与帮助").tag(Section.about)
                }.pickerStyle(.segmented).frame(width: 320)
            }.padding(22)
            Divider()
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if section == .security {
                Text("登录与解锁").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                GroupBox {
                    VStack(spacing: 0) {
                        settingRow("主密码", detail: "更改后，旧文件仍需原密码或对应恢复密钥。") {
                            Button("更改…") { resettingPassword = false; showPasswordChange = true }
                            Button("存入“密码”App…") { showPasswordApp = true }
                        }
                        Divider()
                        settingRow("闲置后锁定", detail: "锁屏、睡眠和切换用户时也会锁定；不会自动加密已解密文件。") {
                            Picker("闲置后锁定", selection: Binding(get: { store.autoLockMinutes }, set: { store.setAutoLockMinutes($0) })) {
                                Text("1 分钟").tag(1); Text("5 分钟").tag(5); Text("15 分钟").tag(15); Text("不按闲置锁定").tag(0)
                            }.labelsHidden().frame(width: 140)
                        }
                        Divider()
                        settingRow("Touch ID", detail: store.touchIDAvailable ? "更改指纹后需重新启用；凭据保存在本机钥匙串。" : store.touchIDReason) {
                            Toggle("Touch ID", isOn: Binding(get: { store.touchIDEnabled }, set: { value in Task { await store.setTouchID(value) } }))
                                .toggleStyle(.switch).labelsHidden().disabled(!store.touchIDAvailable && !store.touchIDEnabled)
                        }
                    }
                }
                }
                if section == .security || section == .recovery {
                Text("恢复密钥").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                GroupBox {
                    settingRow(store.recoveryPublicKey == nil ? "尚未创建恢复密钥" : "已为新文件启用", detail: "仅适用于启用后新加密的文件。请自行保存完整密钥；更换后保留旧密钥。") {
                        Button(store.recoveryPublicKey == nil ? "创建…" : "更换…", action: beginRecoverySetup)
                    }
                    if let key = store.recoveryPublicKey { Text("密钥标识：\(RecoveryKey.identifier(key))").font(.caption.monospaced()).foregroundStyle(.secondary) }
                }
                recoveryPanel
                }
                if section == .general {
                Text("通用").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                GroupBox {
                    VStack(spacing: 0) {
                        settingRow("登录时启动 EasyLock") {
                            Toggle("登录时启动 EasyLock", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) })).toggleStyle(.switch).labelsHidden()
                        }
                        Divider()
                        settingRow("小组件显示记录数量", detail: "默认隐藏，不共享文件名、路径或密码；系统刷新可能延迟。") {
                            Toggle("小组件显示记录数量", isOn: $widgetShowCount).toggleStyle(.switch).labelsHidden()
                                .onChange(of: widgetShowCount) { _, _ in WidgetSummary.publish(count: store.items.count) }
                        }
                    }
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("快捷操作", systemImage: "keyboard").font(.headline)
                        Text("空格键：预览选中的文件或文件夹。\nCommand 点击：选择多个项目。\nEscape：关闭本机文件预览。")
                            .font(.callout).foregroundStyle(.secondary).lineSpacing(6)
                        Divider()
                        Text("Finder 中右键选择“服务 → 使用 EasyLock 进行加密或解密”。服务是否显示由 macOS 管理。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                }
                if section == .general || section == .theme {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            Label("外观", systemImage: "paintpalette").font(.headline)
                            Picker("界面主题", selection: $appearanceMode) {
                                Text("跟随系统").tag("system")
                                Text("浅色").tag("light")
                                Text("深色").tag("dark")
                            }.pickerStyle(.segmented)
                            Text("立即应用到 EasyLock 界面。透明度与动画遵循 macOS 辅助功能设置。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    GroupBox {
                        settingRow("加密文件默认视图") {
                            Picker("默认视图", selection: $libraryGrid) {
                                Text("卡片").tag(true); Text("列表").tag(false)
                            }.labelsHidden().pickerStyle(.segmented).frame(width: 180)
                        }
                    }
                }
                if section == .about {
                Text("关于").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("免费 · 离线使用", systemImage: "internaldrive").font(.headline)
                        Text("无需账号或激活，不限制设备数量。加密与解密在本机完成，应用不上传文件或使用记录。")
                        Text("\(DistributionChannel.name) · \(DistributionChannel.updateDescription)")
                        Text("云盘与苹果“密码”的同步由相应服务和系统设置管理。")
                        Button("使用帮助与隐私说明") { showHelp = true }
                        DisclosureGroup("文件保护范围") {
                            Text("实际恢复并校验后才替换原件。支持的文件内容与元数据会恢复，macOS 管理的标记由系统维护。加密不会清除历史缓存、备份及其他明文副本；操作前请关闭编辑这些文件的程序。")
                                .padding(.top, 8)
                        }
                    }.font(.callout).foregroundStyle(.secondary)
                }
                }
            }.frame(maxWidth: 760).padding(22).frame(maxWidth: .infinity)
        }
        }.background { WorkspaceBackground() }.disabled(store.busy)
    }
    private func settingRow<Actions: View>(_ title: String, detail: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.callout)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8, content: actions)
        }.padding(.vertical, 12)
    }

    private var recoveryPanel: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("中断任务恢复", systemImage: "arrow.counterclockwise.circle").font(.headline)
                    Spacer()
                    Button("刷新") { Task { await store.scanRecoveries() } }
                    Button("检查恢复目录…") { store.chooseRecoveryFolder() }
                }
                Text("启动时检查曾处理过的目录。离线磁盘连接后可刷新；未记录的位置可手动选择。恢复不会覆盖同名文件，也不会删除已发布的结果。")
                    .font(.caption).foregroundStyle(.secondary)
                if store.recoveries.isEmpty && store.recoveryErrors.isEmpty { Text("没有发现未完成任务。").foregroundStyle(.secondary) }
                ForEach(store.recoveryErrors, id: \.self) { Text($0).font(.caption).foregroundStyle(.orange) }
                ForEach(store.recoveries) { item in
                    Divider()
                    Text(item.source.lastPathComponent).font(.headline)
                    Text(item.explanation).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if item.canRestore { Button("恢复任务开始前的文件") { Task { await store.recover(item) } } }
                        if item.canDiscard { Button("清理未提交的临时副本") { Task { await store.recover(item, discard: true) } } }
                        if item.canDiscard || item.canRestore {
                            Button("重新授权并重试…") { Task { await store.recover(item, discard: item.canDiscard, reauthorize: true) } }
                        }
                        Button("在 Finder 中检查") { NSWorkspace.shared.activateFileViewerSelecting([item.folder]) }
                    }
                }
            }.padding(14)
        }
    }

    private var resultsSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("任务结果").font(.title2.weight(.semibold))
            Text("成功 \(store.outcomes.filter { $0.status == "成功" }.count) 项 · 其他 \(store.outcomes.filter { $0.status != "成功" }.count) 项")
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(store.outcomes) { item in
                        HStack {
                            Text(item.name).fontWeight(.medium).lineLimit(2)
                            Spacer()
                            Text(item.status).foregroundStyle(item.status == "成功" ? accent : .orange)
                        }
                        Text(item.detail).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Divider()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 400)
            HStack {
                if !store.recoveries.isEmpty { Button("查看恢复任务") { store.showResults = false; section = .security } }
                Spacer()
                Button("完成") { store.showResults = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 560)
    }

    #if EASYLOCK_ENABLE_LICENSING
    private var membership: some View { LicenseView() }
    #endif

    private var encryptionSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("原地加密", systemImage: "lock.doc").font(.title2.weight(.semibold))
            Text("已选择 \(store.pendingURLs.count) 个项目。加密后仍在原位置，原名称后添加 .easylock。").foregroundStyle(.secondary)
            ScrollView { VStack(alignment: .leading, spacing: 8) { ForEach(store.pendingURLs, id: \.self) { Text($0.lastPathComponent).lineLimit(1) } }.frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 130)
            Text("完成加密、实际恢复与完整校验后，移除原件，仅保留密文。任何校验失败都会中止替换。").font(.callout.weight(.medium))
            ScrollView { Text(store.preflightText).font(.caption).foregroundStyle(store.preflightFailed ? .orange : .secondary).frame(maxWidth: .infinity, alignment: .leading) }.frame(maxHeight: 100)
            if store.inspectingSources { ProgressView().controlSize(.small) }
            if store.preflightFailed {
                Button("授权所在文件夹并重新检查…") { Task { await store.authorizePendingSources() } }
                    .disabled(store.inspectingSources)
            }
            if store.preflightFailed { Button("重新检查") { Task { await store.inspectPendingSources() } } }
            HStack { Button("取消") { store.pendingURLs = [] }; Spacer(); Button("确认原地加密") { Task { await store.encryptPending() } }.buttonStyle(BrandPrimaryButtonStyle()).disabled(store.inspectingSources || store.preflightFailed) }
        }.padding(28).frame(width: 440).task { await store.inspectPendingSources() }
    }

    private var passwordChangeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(resettingPassword ? "重设主密码" : "更改主密码").font(.title2.weight(.semibold))
            if resettingPassword { SecureField("本机对应的恢复密钥", text: $recoveryInput) }
            else if currentPasswordVerifiedByTouchID {
                HStack {
                    Label("已通过 Touch ID 验证当前密码", systemImage: "touchid").foregroundStyle(accent)
                    Spacer()
                    Button("改用密码") { currentPassword = ""; currentPasswordVerifiedByTouchID = false }
                }.font(.caption)
            } else { SecureField("当前主密码", text: $currentPassword) }
            SecureField("新主密码（至少 10 个字符）", text: $newPassword)
            SecureField("再次输入新密码", text: $newConfirmation)
            Text("这不会给已有文件换密码。旧文件仍需原密码，或在加密时已启用的恢复密钥。Touch ID 会关闭，之后可重新启用。")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("我理解旧文件仍需原有解密凭据", isOn: $changeAcknowledged)
            HStack {
                Button("取消") { showPasswordChange = false }.disabled(store.busy)
                Spacer()
                Button("确认更改") {
                    Task {
                        if await store.changeMasterPassword(current: currentPassword, new: newPassword, confirmation: newConfirmation, recovery: resettingPassword ? recoveryInput : nil) { showPasswordChange = false }
                    }
                }.buttonStyle(BrandPrimaryButtonStyle()).disabled(!changeAcknowledged || store.busy || newPassword.count < 10 || newPassword != newConfirmation)
            }
        }.textFieldStyle(.roundedBorder).padding(28).frame(width: 460)
            .disabled(store.busy)
            .interactiveDismissDisabled(store.busy)
            .task {
                store.refreshTouchIDAvailability()
                guard !resettingPassword, store.touchIDEnabled, store.touchIDAvailable, currentPassword.isEmpty else { return }
                if let verified = await store.verifyCurrentPasswordWithTouchID(), showPasswordChange, !Task.isCancelled {
                    currentPassword = verified; currentPasswordVerifiedByTouchID = true
                }
            }
            .onDisappear { currentPasswordVerifiedByTouchID = false; currentPassword = ""; newPassword = ""; newConfirmation = ""; recoveryInput = ""; changeAcknowledged = false }
    }

    private var recoverySetupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("保存你的恢复密钥").font(.title2.weight(.semibold))
            Text("持有密钥的人可以解密对应文件。请单独保管，应用无法重新显示它。更换密钥时，旧密钥仍需保留。").foregroundStyle(.secondary)
            Text(recoveryDraft).font(.system(.caption, design: .monospaced)).textSelection(.enabled).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            Button(recoveryExported ? "已导出，可再次保存…" : "导出密钥…") { recoveryExported = store.exportRecovery(recoveryDraft) }
            SecureField("重新输入已保存的完整密钥", text: $recoveryConfirmation).textFieldStyle(.roundedBorder)
            Text("只有确认后才用于新加密文件。已有文件不会自动获得恢复能力。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { showRecoverySetup = false }
                Spacer()
                Button("确认已保存并启用") {
                    if store.enableRecovery(recoveryDraft, confirmation: recoveryConfirmation) { showRecoverySetup = false }
                }.buttonStyle(BrandPrimaryButtonStyle()).disabled(recoveryConfirmation.trimmingCharacters(in: .whitespacesAndNewlines) != recoveryDraft)
            }
        }.padding(28).frame(width: 510)
    }

    private var prefersDecryptionTouchID: Bool {
        store.touchIDEnabled && store.touchIDAvailable && !useRecovery && decryptPassword.isEmpty
    }

    private var decryptionSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: "lock.open").font(.largeTitle).foregroundStyle(accent)
            Text("解密后访问").font(.title2.weight(.semibold))
            Text("已选择 \(store.selection.count) 个加密文件。即使后缀被改动，也需要原密码或对应恢复密钥才能恢复。").foregroundStyle(.secondary)
            Picker("解密凭据", selection: $useRecovery) {
                Text("文件密码").tag(false); Text("恢复密钥").tag(true)
            }.pickerStyle(.segmented)
            if useRecovery {
                SecureField("完整 ELRK1 恢复密钥", text: $recoveryInput).textFieldStyle(.roundedBorder).controlSize(.large)
                Text("仅适用于加密时已启用此密钥的文件；旧文件仍需原密码。").font(.caption).foregroundStyle(.secondary)
            } else { SecureField("文件加密密码", text: $decryptPassword).textFieldStyle(.roundedBorder).controlSize(.large) }
            Toggle("恢复到其他位置，并保留密文", isOn: $restoreElsewhere)
            if restoreElsewhere {
                HStack {
                    Text(restoreFolder?.path ?? "尚未选择目录").font(.caption).lineLimit(1).truncationMode(.middle)
                    Button("选择目录…") { if let folder = store.chooseRestoreFolder() { restoreFolder = folder } }
                }
            }
            if store.touchIDEnabled && !useRecovery {
                Text("优先使用 Touch ID。取消验证后可输入密码；其他密码加密的文件需输入对应密码。").font(.caption).foregroundStyle(.secondary)
            }
            Text(restoreElsewhere ? "在所选目录恢复原名称和内容，保留原密文。遇到同名文件会停止，不覆盖。" : "在当前目录恢复加密前的原名称与格式。成功后移除密文；遇到其他同名文件会停止，不覆盖。").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("取消") { store.showUnlock = false; decryptPassword = "" }
                Spacer()
                Button(restoreElsewhere ? "恢复副本" : "原地解密") {
                    let secret = decryptPassword; let key = useRecovery ? recoveryInput : nil
                    let destination = restoreElsewhere ? restoreFolder : nil
                    decryptPassword = ""; recoveryInput = ""
                    Task { await store.decryptSelected(with: secret, destination: destination, recovery: key) }
                }.buttonStyle(BrandPrimaryButtonStyle())
                    .keyboardShortcut(prefersDecryptionTouchID ? nil : .defaultAction)
                    .disabled((useRecovery ? recoveryInput.isEmpty : decryptPassword.isEmpty) || (restoreElsewhere && restoreFolder == nil))
                if store.touchIDEnabled && store.touchIDAvailable && !useRecovery {
                    Button {
                        let destination = restoreElsewhere ? restoreFolder : nil
                        Task { await store.unlockWithTouchID(decrypt: true, destination: destination) }
                    } label: { Label("Touch ID 解密", systemImage: "touchid") }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .keyboardShortcut(prefersDecryptionTouchID ? .defaultAction : nil)
                        .disabled(restoreElsewhere && restoreFolder == nil)
                }
            }
        }.padding(28).frame(width: 460)
            .disabled(store.busy)
            .interactiveDismissDisabled(store.busy)
            .onAppear {
                guard !didRequestDecryptionTouchID else { return }
                didRequestDecryptionTouchID = true
                store.refreshTouchIDAvailability()
                guard store.touchIDEnabled, store.touchIDAvailable, !useRecovery, !restoreElsewhere else { return }
                Task { await store.unlockWithTouchID(decrypt: true) }
            }
            .onDisappear {
                decryptPassword = ""; recoveryInput = ""; restoreFolder = nil
                restoreElsewhere = false; useRecovery = false; didRequestDecryptionTouchID = false
            }
    }
}




#Preview {
    ContentView(store: VaultStore())
}
