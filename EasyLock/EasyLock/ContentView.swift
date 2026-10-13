import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum Section: String, CaseIterable, Identifiable {
    case files = "加密文件", security = "安全与设置"
    #if EASYLOCK_ENABLE_LICENSING
    case membership = "许可证"
    #endif
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .files: "lock.doc"
        case .security: "slider.horizontal.3"
        #if EASYLOCK_ENABLE_LICENSING
        case .membership: "seal"
        #endif
        }
    }
}

struct ContentView: View {
    @Bindable var store: VaultStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("widgetShowCount") private var widgetShowCount = false
    @State private var showPasswordApp = false
    @State private var showHelp = false
    @State private var requests = ExternalFileRequests.shared
    @State private var section: Section = .files
    @State private var search = ""
    @State private var input = ""
    @State private var confirmation = ""
    @State private var decryptPassword = ""
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
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 10) {
                    BrandMark(size: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("EasyLock").font(.system(size: 20, weight: .semibold, design: .rounded))
                        Text("你的本地隐私空间").font(.caption2).foregroundStyle(.secondary)
                    }
                }.padding(.horizontal, 18).padding(.top, 28)
                List(Section.allCases, selection: $section) { item in
                    Label(item.rawValue, systemImage: item.icon).padding(.vertical, 6).tag(item)
                }.listStyle(.sidebar)
                VStack(alignment: .leading, spacing: 8) {
                    Label("免费离线 · 内容不上传", systemImage: "internaldrive").font(.caption)
                    Text("开发预览版 0.8").font(.caption2).foregroundStyle(.tertiary)
                }.foregroundStyle(.secondary).padding(20)
            }.background(EasyLockStyle.blue.opacity(0.045)).navigationSplitViewColumnWidth(230)
        } detail: {
            Group {
                if store.password.isEmpty { welcome }
                else {
                    switch section {
                    case .files: library
                    case .security: settings
                    #if EASYLOCK_ENABLE_LICENSING
                    case .membership: membership
                    #endif
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background { VaultBackground() }
                .overlay {
                    if dropTargeted && !store.busy {
                        RoundedRectangle(cornerRadius: 16).strokeBorder(accent, style: StrokeStyle(lineWidth: 2, dash: [8, 5]))
                            .padding(10).background(accent.opacity(0.025)).allowsHitTesting(false)
                    }
                }
                .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { store.acceptDrop($0) }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: section)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: dropTargeted)
        .onAppear { store.refreshTouchIDAvailability() }
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
                showPasswordChange = false; showRecoverySetup = false; showPasswordApp = false
            }
        }
        .tint(accent)
        .groupBoxStyle(BrandGroupBoxStyle())
        .frame(minWidth: 960, minHeight: 700)
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
        .sheet(item: Binding(get: { store.panels.presented }, set: { value in
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
            }
        }
        .task(id: panelState) {
            if !store.nativePanelActive { store.panels.reconcile(requestedPanels) }
        }
        .onDisappear { store.panels.didDismiss() }
    }

    private var requestedPanels: [PanelCoordinator.Panel] {
        var result: [PanelCoordinator.Panel] = []
        if store.notice != nil { result.append(.notice) }
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
        store.panels.occupied || store.nativePanelActive || store.busy || store.loadingDrop || !store.pendingURLs.isEmpty || store.showUnlock ||
        store.showResults || store.notice != nil || showPasswordChange || showRecoverySetup || showHelp || showPasswordApp
    }
    private var externalRequestState: String { "\(requests.revision)-\(externalRequestsBlocked)-\(store.password.isEmpty)" }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 22) {
            BrandMark(size: 100).rotationEffect(.degrees(-5))
            VStack(alignment: .leading, spacing: 10) {
                Text(store.configured ? "欢迎回来。" : "给你的私密文件，\n一把专属的锁。").font(.system(size: 30, weight: .semibold))
                Text(store.configured ? "输入主密码，打开你的文件管理空间。" : "设置主密码，开始在这台 Mac 上加密文件。\n文件内容仅在本地处理。")
                    .foregroundStyle(.secondary).lineSpacing(5)
            }
            VStack(spacing: 12) {
                SecureField(store.configured ? "主密码" : "设置主密码（至少 10 个字符）", text: $input)
                if !store.configured { SecureField("再次输入密码", text: $confirmation) }
            }.textFieldStyle(.roundedBorder).controlSize(.large)
            if !store.pendingURLs.isEmpty || store.showUnlock {
                Label("已接收文件，解锁后继续处理。", systemImage: "tray.and.arrow.down").font(.caption).foregroundStyle(accent)
            }
            if !store.configured {
                Label("请妥善保存密码。未启用恢复密钥的文件无法找回密码。", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
            }
            Button(store.configured ? "解锁 EasyLock" : "设置密码并开始") {
                Task { let isNew = !store.configured; if await store.authenticate(input, confirmation: confirmation) { input = ""; confirmation = ""; if isNew && store.pendingURLs.isEmpty && !store.showUnlock && requests.count == 0 { showPasswordApp = true } } }
            }.buttonStyle(BrandPrimaryButtonStyle()).controlSize(.large).disabled(store.busy || input.isEmpty).keyboardShortcut(.defaultAction)
            if store.configured && store.touchIDEnabled {
                Button { Task { await store.unlockWithTouchID() } } label: { Label("使用 Touch ID 解锁", systemImage: "touchid") }
                    .controlSize(.large).disabled(store.busy || !store.touchIDAvailable).help(store.touchIDAvailable ? "使用系统指纹验证" : store.touchIDReason)
            }
            Button("不登录，使用密码或恢复密钥解密文件") { store.independentDecrypt() }
                .buttonStyle(.plain).font(.caption).disabled(store.busy)
            if store.configured && store.recoveryPublicKey != nil {
                Button("使用恢复密钥重设主密码") { resettingPassword = true; showPasswordChange = true }
                    .buttonStyle(.plain).font(.caption).disabled(store.busy)
            }
        }.frame(width: 410).padding(48)
    }

    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("私密文件").font(.system(size: 28, weight: .semibold)).tracking(-0.5)
                    Text("把重要的内容，留给自己。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Menu {
                    Button("添加文件…", systemImage: "doc.badge.plus") { store.chooseSources() }
                    Button("添加文件夹…", systemImage: "folder.badge.plus") { store.chooseSources(foldersOnly: true) }
                    Divider()
                    Button("导入已有密文…", systemImage: "tray.and.arrow.down") { store.importFiles() }
                    if !store.outcomes.isEmpty { Button("查看上次任务结果") { store.showResults = true } }
                } label: { Label("添加项目", systemImage: "plus") }
                    .menuStyle(.borderlessButton).fixedSize().padding(.horizontal, 16).padding(.vertical, 11)
                    .foregroundStyle(.white).background(accent, in: RoundedRectangle(cornerRadius: 9))
            }
            HStack(spacing: 0) {
                statistic("已登记项目", value: "\(store.items.count)", symbol: "lock.doc")
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 34).padding(.horizontal, 24)
                statistic("加密数据", value: ByteCountFormatter.string(fromByteCount: Int64(store.items.reduce(0) { $0 + $1.size }), countStyle: .file), symbol: "externaldrive")
                Spacer()
                Label("本地保护", systemImage: "checkmark.shield.fill").font(.caption.weight(.medium)).foregroundStyle(accent)
            }.padding(.horizontal, 20).padding(.vertical, 16)
                .background(surface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.65), lineWidth: 1.2))
            if !store.recoveries.isEmpty || !store.recoveryErrors.isEmpty {
                HStack {
                    Label("发现需要检查的未完成任务或离线目录", systemImage: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange)
                    Spacer()
                    Button("查看恢复") { section = .security }
                }.font(.callout).padding(12).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))
            }
            dropZone
            if !store.items.isEmpty {
                HStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.tertiary)
                        TextField("搜索名称或路径", text: $search).textFieldStyle(.plain)
                    }.padding(10).frame(maxWidth: 260).background(surface, in: RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button("全选") { store.selection = Set(filteredItems.map(\.id)) }.buttonStyle(.plain).foregroundStyle(.secondary)
                    Button { decryptPassword = ""; store.showUnlock = true } label: {
                        Label(store.selection.isEmpty ? "解密所选" : "解密 \(store.selection.count) 项", systemImage: "lock.open")
                    }.disabled(store.selection.isEmpty).controlSize(.large)
                }
                fileTable
            } else {
                HStack(spacing: 24) {
                    Label("原地加密", systemImage: "arrow.triangle.2.circlepath")
                    Label("密码保护", systemImage: "key.horizontal")
                    Label("校验后替换", systemImage: "checkmark.shield")
                }.font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.bottom, 10)
            }
            HStack(spacing: 6) {
                Image(systemName: "info.circle")
                Text("支持大文件分块加密 · 修改后缀不能解密")
                Spacer()
                Button("使用说明") { section = .security }.buttonStyle(.plain).foregroundStyle(accent)
            }.font(.caption).foregroundStyle(.secondary)
        }.padding(28).disabled(store.busy)
    }

    private func statistic(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20, weight: .light)).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.system(size: 20, weight: .medium, design: .rounded)).monospacedDigit().contentTransition(.numericText())
                Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: store.items.isEmpty ? 17 : 10) {
            if store.items.isEmpty {
                ZStack(alignment: .bottomTrailing) {
                    BrandMark(size: 118).rotationEffect(.degrees(dropTargeted && !reduceMotion ? 4 : -4))
                    Image(systemName: dropTargeted ? "arrow.down.circle.fill" : "heart.fill")
                        .font(.system(size: 26, weight: .semibold)).foregroundStyle(EasyLockStyle.secondary)
                        .padding(7).background(.background, in: Circle())
                }.accessibilityHidden(true)
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
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(dropTargeted ? accent : Color.primary.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: dropTargeted ? [7, 5] : [])))
            .shadow(color: EasyLockStyle.blue.opacity(0.1), radius: 0, x: 5, y: 5)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: dropTargeted)
    }

    private var fileTable: some View {
        Table(filteredItems, selection: $store.selection) {
            TableColumn("文件名称") { item in
                HStack(spacing: 12) {
                    Image(systemName: "lock.doc").font(.system(size: 21, weight: .light)).foregroundStyle(accent)
                        .frame(width: 36, height: 40).background(accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(item.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                        Text(item.path).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }.padding(.vertical, 7)
                }.help(item.path)
            }.width(min: 210, ideal: 320)
            TableColumn("大小") { Text(ByteCountFormatter.string(fromByteCount: Int64($0.size), countStyle: .file)).font(.caption).foregroundStyle(.secondary) }.width(75)
            TableColumn("状态") { item in
                HStack(spacing: 5) {
                    Circle().fill(item.warning == nil ? accent : Color.orange).frame(width: 5, height: 5)
                    Text(item.warning != nil ? "需要处理" : (item.originalRetained ? "旧版副本" : (item.inPlace == true ? "已加密" : "已导入")))
                }.font(.system(size: 10)).foregroundStyle(.secondary).help(item.warning ?? "")
            }.width(80)
            TableColumn("") { item in
                Button { NSWorkspace.shared.activateFileViewerSelecting([item.resolve()]) } label: { Image(systemName: "arrow.up.forward.square").foregroundStyle(.secondary) }
                    .buttonStyle(.borderless).help("在 Finder 中显示")
            }.width(24)
        }.frame(minHeight: 145).clipShape(RoundedRectangle(cornerRadius: 10))
    }
    private var filteredItems: [LockedItem] { store.items.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.path.localizedCaseInsensitiveContains(search) } }

    private var settings: some View {
        ScrollView { VStack(alignment: .leading, spacing: 25) {
            Text("安全与设置").font(.largeTitle.weight(.semibold))
            Text("清晰掌握每一次保护与恢复。 ").foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("免费 · 离线使用", systemImage: "internaldrive").font(.headline)
                    Text("无需账号或激活，不限制使用设备数量。加密与解密在本机完成，应用不上传文件或使用记录。").foregroundStyle(.secondary)
                    Text("发行渠道：\(DistributionChannel.name)。\(DistributionChannel.updateDescription)").font(.caption).foregroundStyle(.secondary)
                    Text("苹果“密码”的同步和云盘文件同步由系统及对应服务管理，请按需调整它们的设置。").font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(10)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 18) {
                    Label("主密码已设置", systemImage: "key.fill").font(.headline)
                    Text("主密码用于登录及新文件加密。更改后，已有文件仍使用原加密密码或对应恢复密钥。").foregroundStyle(.secondary)
                    Button("保存主密码到苹果“密码”…") { showPasswordApp = true }
                    Button("更改主密码…") { resettingPassword = false; showPasswordChange = true }
                    Divider()
                    Picker("闲置后锁定", selection: Binding(get: { store.autoLockMinutes }, set: { store.setAutoLockMinutes($0) })) {
                        Text("1 分钟").tag(1); Text("5 分钟").tag(5); Text("15 分钟").tag(15); Text("不按闲置时间锁定").tag(0)
                    }
                    Text("锁屏、屏幕关闭、睡眠或切换系统会话时也会锁定应用。自动锁定会请求安全停止当前任务，不会自动加密磁盘上已解密的文件。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Label(store.recoveryPublicKey == nil ? "尚未启用恢复密钥" : "新文件已启用恢复密钥", systemImage: "key.horizontal").font(.headline)
                    if let key = store.recoveryPublicKey { Text("密钥标识：\(RecoveryKey.identifier(key))").font(.caption.monospaced()) }
                    Text("只对启用后新加密的文件生效。应用只保存公开部分，无法重新显示密钥；更换后请保留旧密钥用于旧文件。").font(.caption).foregroundStyle(.secondary)
                    Button(store.recoveryPublicKey == nil ? "创建恢复密钥…" : "更换恢复密钥…") {
                        recoveryDraft = RecoveryKey.generate(); recoveryConfirmation = ""; recoveryExported = false; showRecoverySetup = true
                    }
                    Divider()
                    Toggle("在桌面小组件显示记录数量", isOn: $widgetShowCount)
                        .onChange(of: widgetShowCount) { _, _ in WidgetSummary.publish(count: store.items.count) }
                    Text("默认隐藏数量，小组件不保存文件名、路径或密码。系统刷新可能延迟；显示的是最近同步的记录数量。").font(.caption).foregroundStyle(.secondary)
                    Divider()
                    Toggle("登录时启动 EasyLock", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                    Divider()
                    Toggle(isOn: Binding(get: { store.touchIDEnabled }, set: { enabled in Task { await store.setTouchID(enabled) } })) {
                        Label("Touch ID 解锁", systemImage: "touchid")
                    }.disabled(!store.touchIDAvailable && !store.touchIDEnabled)
                    Text(store.touchIDAvailable ? "启用后，主密码保存在受当前指纹保护的本机钥匙串中。变更指纹后需重新启用，密码解锁始终保留。" : store.touchIDReason)
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Label("开发预览版的文件策略", systemImage: "doc.text.magnifyingglass").font(.headline)
                    Text("保存文件内容、目录结构、名称、权限、时间、标签、资源分支及访问控制列表。macOS 管理的访问授权、来源及下载隔离状态交由系统维护，不直接重写旧标记。实际恢复校验通过后才替换原件；不支持的文件会中止处理。").foregroundStyle(.secondary).lineSpacing(5)
                    Text("请先关闭正在编辑文件的程序。新文件的系统编号和状态变更时间无法保持；历史缓存、备份和其他明文副本不会自动清除。").font(.caption).foregroundStyle(.secondary)
                }.padding(14)
            }
            recoveryPanel
        }.padding(36).frame(maxWidth: 760, alignment: .leading) }.disabled(store.busy)
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
            if store.preflightFailed { Button("重新检查") { Task { await store.inspectPendingSources() } } }
            HStack { Button("取消") { store.pendingURLs = [] }; Spacer(); Button("确认原地加密") { Task { await store.encryptPending() } }.buttonStyle(BrandPrimaryButtonStyle()).disabled(store.inspectingSources || store.preflightFailed) }
        }.padding(28).frame(width: 440).task { await store.inspectPendingSources() }
    }

    private var passwordChangeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(resettingPassword ? "重设主密码" : "更改主密码").font(.title2.weight(.semibold))
            if resettingPassword { SecureField("本机对应的恢复密钥", text: $recoveryInput) }
            else { SecureField("当前主密码", text: $currentPassword) }
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
            .interactiveDismissDisabled(store.busy)
            .onDisappear { currentPassword = ""; newPassword = ""; newConfirmation = ""; recoveryInput = ""; changeAcknowledged = false }
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
            if store.touchIDEnabled && !useRecovery && !restoreElsewhere {
                Button { Task { await store.unlockWithTouchID(decrypt: true) } } label: { Label("使用 Touch ID 解密", systemImage: "touchid") }
                    .disabled(store.busy || !store.touchIDAvailable)
                Text("适用于使用本机主密码加密的文件；其他文件请输入对应密码。").font(.caption).foregroundStyle(.secondary)
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
                    .disabled((useRecovery ? recoveryInput.isEmpty : decryptPassword.isEmpty) || (restoreElsewhere && restoreFolder == nil))
                    .keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 460)
            .onDisappear { decryptPassword = ""; recoveryInput = ""; restoreFolder = nil; restoreElsewhere = false; useRecovery = false }
    }
}




#Preview {
    ContentView(store: VaultStore())
}
