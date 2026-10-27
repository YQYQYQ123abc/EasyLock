import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum Section: String, CaseIterable, Identifiable {
    case overview = "概览", files = "加密文件", computer = "本机文件", security = "安全与解锁", general = "常规", recovery = "恢复与检查", theme = "主题", about = "关于"
    #if EASYLOCK_ENABLE_LICENSING
    case membership = "许可证"
    #endif
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .overview: "rectangle.grid.2x2"
        case .files: "lock.doc"
        case .computer: "internaldrive"
        case .security: "lock.shield"
        case .general: "gearshape"
        case .recovery: "arrow.counterclockwise"
        case .theme: "circle.lefthalf.filled"
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
    @AppStorage("libraryGrid") private var libraryGrid = true
    @State private var showFileDetails = false
    @AppStorage("widgetShowCount") private var widgetShowCount = false
    @State private var showPasswordApp = false
    @State private var showHelp = false
    @State private var requests = ExternalFileRequests.shared
    @State private var section: Section = .overview
    @FocusState private var welcomeFocused: Bool
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


    var body: some View {
        Group {
            if store.password.isEmpty {
                welcome.onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { store.acceptDrop($0) }
            } else {
                NavigationSplitView {
                    sidebar
                } detail: {
                    workspaceDetail
                }
                .navigationSplitViewStyle(.balanced)
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
        .frame(minWidth: 1040, minHeight: 700)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showHelp = true } label: { Label("使用帮助", systemImage: "questionmark.circle") }
                    .disabled(store.busy)
                if !store.password.isEmpty {
                    Button { store.lockSession(); input = ""; confirmation = "" } label: { Label("锁定应用", systemImage: "lock") }
                        .disabled(store.busy)
                }
            }
        }
        .background {
            SidebarToggleHider()
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if store.busy {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small).tint(EasyLockStyle.blue)
                        Text(store.password.isEmpty && !store.guestDecrypt ? "正在安全结束当前操作…" : store.progress)
                            .font(.system(size: 11.5, weight: .medium))
                            .lineLimit(1)
                        Spacer()
                        if store.batchTotal > 0 {
                            Button(store.cancellationRequested ? "正在安全停止…" : "取消任务") { store.cancelBatch() }
                                .buttonStyle(BrandSecondaryButtonStyle())
                                .disabled(store.cancellationRequested)
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
                        }
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        if update.total > 0 {
                            ProgressView(value: min(Double(update.completed) / Double(update.total), 1))
                                .tint(EasyLockStyle.blue)
                        }
                    }
                    if store.batchTotal > 0 {
                        Text("已完成 \(store.batchCompleted)/\(store.batchTotal) 项 · 提交替换期间会先完成当前步骤")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(EasyLockStyle.surfaceRaised)
                .overlay(alignment: .top) {
                    Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                }
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
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(EasyLockStyle.secondary)
                        Text(notice)
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                        Spacer(minLength: 12)
                        Button("知道了") { store.notice = nil }
                            .buttonStyle(BrandGhostButtonStyle())
                    }
                    .padding(14)
                    .frame(maxWidth: 540)
                    .background(EasyLockStyle.surfaceRaised)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                    }
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                BrandMark(size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("EasyLock")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(EasyLockStyle.ink)
                    Text("本机文件保险箱")
                        .font(.system(size: 10))
                        .foregroundStyle(EasyLockStyle.sidebarDim)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sidebarGroup("保险箱", items: [.overview, .files, .computer])
                    sidebarGroup("安全", items: [.security, .recovery])
                    sidebarGroup("应用", items: [.general, .theme, .about])
                    #if EASYLOCK_ENABLE_LICENSING
                    sidebarGroup("许可证", items: [.membership])
                    #endif
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            Spacer(minLength: 0)
            sidebarFooter
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(EasyLockStyle.sidebar)
        .navigationSplitViewColumnWidth(min: 218, ideal: 236, max: 272)
    }

    private func sidebarGroup(_ title: String, items: [Section]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 9.5, weight: .semibold))
                .tracking(1.4)
                .foregroundStyle(EasyLockStyle.sidebarDim)
                .padding(.leading, 10)
                .padding(.bottom, 5)
            ForEach(items) { item in
                sidebarRow(item)
            }
        }
    }

    private func sidebarRow(_ item: Section) -> some View {
        let selected = section == item
        return Button { section = item } label: {
            HStack(spacing: 10) {
                Image(systemName: item.icon)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .medium))
                    .frame(width: 17)
                Text(item.rawValue)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                Spacer(minLength: 6)
                if item == .files && !store.items.isEmpty {
                    Text("\(store.items.count)")
                        .font(.system(size: 9.5, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(selected ? EasyLockStyle.blueDeep : EasyLockStyle.tertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(selected ? EasyLockStyle.blue.opacity(0.12) : EasyLockStyle.surfaceMuted, in: Capsule())
                }
                if item == .recovery && (!store.recoveries.isEmpty || !store.recoveryErrors.isEmpty) {
                    Circle()
                        .fill(EasyLockStyle.warning)
                        .frame(width: 5, height: 5)
                }
            }
            .foregroundStyle(selected ? EasyLockStyle.sidebarSelectedText : EasyLockStyle.sidebarText)
            .padding(.horizontal, 10)
            .padding(.vertical, 7.5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(EasyLockStyle.sidebarSelectedFill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 7) {
                Circle().fill(EasyLockStyle.success).frame(width: 6, height: 6)
                Text("会话已解锁")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(EasyLockStyle.ink)
                Spacer(minLength: 4)
                Button {
                    store.lockSession(); input = ""; confirmation = ""
                } label: {
                    Image(systemName: "lock")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(EasyLockStyle.sidebarText)
                        .frame(width: 24, height: 24)
                        .background(EasyLockStyle.surface, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .strokeBorder(EasyLockStyle.sidebarLine, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .disabled(store.busy)
                .help("锁定应用")
                .accessibilityLabel("锁定应用")
            }
            Text(store.autoLockMinutes == 0 ? "不按闲置时间自动锁定" : "闲置 \(store.autoLockMinutes) 分钟后自动锁定")
                .font(.system(size: 9.5))
                .foregroundStyle(EasyLockStyle.sidebarDim)
            Rectangle().fill(EasyLockStyle.sidebarLine).frame(height: 1)
            HStack(spacing: 6) {
                Image(systemName: "internaldrive").font(.system(size: 9, weight: .medium))
                Text("免费离线 · 内容不上传").font(.system(size: 9.5))
            }
            .foregroundStyle(EasyLockStyle.sidebarDim)
            Text("EASYLOCK · LOCAL VAULT")
                .font(.system(size: 8, weight: .semibold))
                .tracking(1.6)
                .foregroundStyle(EasyLockStyle.sidebarDim.opacity(0.65))
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 15)
        .overlay(alignment: .top) {
            Rectangle().fill(EasyLockStyle.sidebarLine).frame(height: 1)
        }
    }

    private var workspaceDetail: some View {
        VStack(spacing: 0) {
            Group {
                if store.password.isEmpty { welcome }
                else {
                    switch section {
                    case .overview: overview
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
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(EasyLockStyle.blue, style: StrokeStyle(lineWidth: 1.6, dash: [8, 5]))
                            .padding(10)
                            .background(EasyLockStyle.blue.opacity(0.035))
                            .allowsHitTesting(false)
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
                SheetHeader(symbol: "info.circle", title: "EasyLock", subtitle: "操作提示")
                ScrollView {
                    Text(store.notice ?? "")
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 240)
                HStack {
                    Spacer()
                    Button("知道了") { store.notice = nil }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 460)
            .background(EasyLockStyle.background)
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

    private var externalRequestsBlocked: Bool {        store.localPreview != nil || store.preview.requested || store.preview.busy || store.panels.occupied || store.nativePanelActive || store.busy || store.loadingDrop || !store.pendingURLs.isEmpty || store.showUnlock ||
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
        ZStack {
            VaultBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 30)
                        welcomeHero
                        welcomeForm.padding(.top, 26)
                        Spacer(minLength: 30)
                        welcomeFooter.padding(.top, 24)
                    }
                    .padding(.horizontal, 32)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: geo.size.height)
                }
                .scrollIndicators(.hidden)
            }
        }
        .task {
            guard !didRequestWelcomeTouchID else { return }
            didRequestWelcomeTouchID = true
            store.refreshTouchIDAvailability()
            guard store.configured, store.touchIDEnabled, store.touchIDAvailable,
                  !store.busy, !store.panels.occupied, !store.guestDecrypt, input.isEmpty else { return }
            await store.unlockWithTouchID()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                if store.password.isEmpty { welcomeFocused = true }
            }
        }
        .onDisappear { didRequestWelcomeTouchID = false; welcomeFocused = false }
    }

    private var welcomeHero: some View {
        VStack(spacing: 16) {
            if !store.pendingURLs.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 9, weight: .semibold))
                    Text("已收到 \(store.pendingURLs.count) 个项目，解锁后继续")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .foregroundStyle(EasyLockStyle.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(EasyLockStyle.surface, in: Capsule())
                .overlay { Capsule().strokeBorder(EasyLockStyle.border, lineWidth: 1) }
            }

            BrandMark(size: 104)

            VStack(spacing: 7) {
                Text("EasyLock")
                    .font(.system(size: 34, weight: .semibold))
                    .tracking(-0.9)
                Text(store.configured ? "欢迎回来" : "给文件一把专属的锁")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(store.configured
                     ? "输入主密码或使用 Touch ID，继续保护本机文件。"
                     : "设置主密码，在这台 Mac 上加密和解密自己的文件。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
            }

            HStack(spacing: 11) {
                welcomeFeature("lock.shield", "AES-256-GCM")
                welcomeDot
                welcomeFeature("internaldrive", "本机处理")
                welcomeDot
                welcomeFeature("wifi.slash", "无需账号")
            }
            .padding(.top, 3)

            if !store.pendingURLs.isEmpty {
                Button("取消本次加密") { store.pendingURLs = [] }
                    .buttonStyle(BrandGhostButtonStyle())
            }
        }
    }

    private var welcomeForm: some View {
        VStack(spacing: 13) {
            if store.configured {
                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(EasyLockStyle.tertiary)
                    SecureField("主密码", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($welcomeFocused)
                        .onSubmit { if !input.isEmpty && !store.busy { authenticate() } }
                        .accessibilityLabel("主密码")
                    Button(action: authenticate) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(input.isEmpty ? EasyLockStyle.ink.opacity(0.55) : EasyLockStyle.buttonText)
                            .frame(width: 31, height: 31)
                            .background(input.isEmpty ? EasyLockStyle.surfaceMuted : EasyLockStyle.buttonFill, in: Circle())
                            .overlay {
                                Circle().strokeBorder(input.isEmpty ? EasyLockStyle.border : .clear, lineWidth: 1)
                            }
                    }
                    .buttonStyle(.plain)
                    .disabled(store.busy || input.isEmpty)
                    .accessibilityLabel("解锁 EasyLock")
                }
                .fieldSurface(focused: welcomeFocused, height: 48)
                .frame(width: 344)

                if store.touchIDEnabled {
                    Button { Task { await store.unlockWithTouchID() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "touchid").font(.system(size: 13, weight: .medium))
                            Text("使用 Touch ID 解锁")
                            Spacer(minLength: 12)
                            Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .frame(width: 344)
                    .disabled(store.busy || !store.touchIDAvailable)
                    .help(store.touchIDReason)
                }

                HStack(spacing: 2) {
                    if store.recoveryPublicKey != nil {
                        Button("使用恢复密钥") { resettingPassword = true; showPasswordChange = true }
                            .buttonStyle(BrandGhostButtonStyle())
                    }
                    Button("直接解密文件") { store.independentDecrypt() }
                        .buttonStyle(BrandGhostButtonStyle())
                        .disabled(store.busy)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(EasyLockStyle.tertiary)
                        SecureField("主密码（至少 10 个字符）", text: $input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .focused($welcomeFocused)
                            .onSubmit { if !store.busy && !input.isEmpty { authenticate() } }
                            .accessibilityLabel("设置主密码")
                    }
                    .fieldSurface(focused: welcomeFocused, height: 48)

                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(EasyLockStyle.tertiary)
                        SecureField("再次输入密码", text: $confirmation)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                            .onSubmit { if !store.busy && !input.isEmpty { authenticate() } }
                            .accessibilityLabel("再次输入密码")
                    }
                    .fieldSurface(height: 48)

                    Text("请妥善保存密码。未启用恢复密钥的文件无法找回密码。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
                .frame(width: 344)

                Button(action: authenticate) {
                    HStack(spacing: 7) {
                        Text("设置并开始")
                        Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .frame(width: 344)
                .disabled(store.busy || input.isEmpty || confirmation.isEmpty)
            }

            if !store.pendingURLs.isEmpty || store.showUnlock {
                Label("已接收文件，解锁后继续处理", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var welcomeFooter: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: "lock.shield").font(.system(size: 9, weight: .medium))
                Text("文件只在本机处理 · 不上传、不需要账号").font(.system(size: 10))
            }
            .foregroundStyle(.secondary)
            Text("EASYLOCK · LOCAL VAULT")
                .font(.system(size: 8, weight: .semibold))
                .tracking(2.2)
                .foregroundStyle(EasyLockStyle.tertiary.opacity(0.7))
        }
    }

    private func welcomeFeature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .medium))
            Text(text).font(.system(size: 9.5, weight: .medium))
        }
        .foregroundStyle(EasyLockStyle.secondary)
    }

    private var welcomeDot: some View {
        Circle().fill(EasyLockStyle.borderStrong).frame(width: 2.5, height: 2.5)
    }

    private var overview: some View {
        OverviewView(store: store,
                     openLibrary: { section = .files },
                     openLocalFiles: { section = .computer },
                     openSecurity: { section = .security },
                     openItem: { item in
                         store.selection = [item.id]
                         section = .files
                     })
    }

    private var library: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                PageHeading(title: "加密文件",
                            subtitle: "\(store.items.count) 项本机记录 · 文件保存在原位置",
                            symbol: "lock.doc")
                Spacer(minLength: 12)
                Picker("显示方式", selection: $libraryGrid) {
                    Image(systemName: "square.grid.2x2").tag(true)
                    Image(systemName: "list.bullet").tag(false)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 84)
                .help("切换卡片或列表")
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)

            librarySummary
                .padding(.horizontal, 24)
                .padding(.bottom, 14)

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)

            if libraryGrid { gridLibrary } else { listLibrary }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background { WorkspaceBackground() }
    }

    private var librarySummary: some View {
        HStack(spacing: 12) {
            librarySummaryCard(title: "记录",
                               value: "\(store.items.count)",
                               unit: "项",
                               symbol: "lock.doc",
                               tint: EasyLockStyle.blue,
                               soft: EasyLockStyle.blueSoft)
            librarySummaryCard(title: "密文大小",
                               value: libraryTotalSize,
                               unit: nil,
                               symbol: "internaldrive",
                               tint: EasyLockStyle.blue,
                               soft: EasyLockStyle.blueSoft)
            librarySummaryCard(title: "需检查",
                               value: "\(libraryAttentionCount)",
                               unit: "项",
                               symbol: "exclamationmark.triangle.fill",
                               tint: libraryAttentionCount == 0 ? EasyLockStyle.success : EasyLockStyle.warning,
                               soft: libraryAttentionCount == 0 ? EasyLockStyle.successSoft : EasyLockStyle.warningSoft)
        }
    }

    private func librarySummaryCard(title: String,
                                    value: String,
                                    unit: String?,
                                    symbol: String,
                                    tint: Color,
                                    soft: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(soft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 17, weight: .semibold))
                        .tracking(-0.25)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if let unit {
                        Text(unit)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background { GlassPanel(radius: 16) }
    }

    private var libraryAttentionCount: Int {
        store.items.filter { $0.warning != nil || $0.originalRetained }.count
    }

    private var libraryTotalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(store.items.reduce(0) { $0 + $1.size }), countStyle: .file)
    }

    private var librarySearchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("搜索名称或路径", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除搜索")
            }
        }
        .fieldSurface(height: 36)
        .frame(maxWidth: 310)
    }

    private var libraryAddButton: some View {
        Button { store.chooseSources() } label: {
            Label("添加文件", systemImage: "plus")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(BrandPrimaryButtonStyle())
        .disabled(!store.canPresentPicker || store.busy)
    }

    private var libraryMoreMenu: some View {
        Menu {
            Button("添加文件夹…") { store.chooseSources(foldersOnly: true) }
            Button("导入已有密文…") { store.importFiles() }
            if !store.outcomes.isEmpty {
                Divider()
                Button("上次任务结果") { store.showResults = true }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EasyLockStyle.secondary)
                .frame(width: 32, height: 32)
                .background(EasyLockStyle.surface, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .disabled(!store.canPresentPicker || store.busy)
    }

    private var libraryAttentionBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.shield.fill")
                .font(.system(size: 11, weight: .semibold))
            Text(store.recoveryPublicKey == nil
                 ? "建议创建恢复密钥，保护之后新加密的文件"
                 : "有未完成的恢复任务需要检查")
                .font(.system(size: 11, weight: .medium))
            Spacer(minLength: 12)
            Button("安全设置") { section = .security }
                .buttonStyle(BrandGhostButtonStyle())
        }
        .foregroundStyle(EasyLockStyle.warning)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(EasyLockStyle.warningSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(EasyLockStyle.warning.opacity(0.20), lineWidth: 1)
        }
    }

    private var gridLibrary: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                librarySearchField
                Spacer(minLength: 8)
                Picker("筛选", selection: $attentionOnly) {
                    Text("全部").tag(false)
                    Text("需检查").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 150)
                libraryMoreMenu
                libraryAddButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if store.recoveryPublicKey == nil || !store.recoveries.isEmpty || !store.recoveryErrors.isEmpty {
                libraryAttentionBanner
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            if store.items.isEmpty {
                dropZone.padding(.horizontal, 24).padding(.bottom, 20)
            } else if filteredItems.isEmpty {
                BrowserEmptyState(symbol: "magnifyingglass",
                                  title: "没有匹配的记录",
                                  detail: "试试其他名称，或清除筛选查看所有加密文件。",
                                  actionTitle: "显示全部记录") {
                    search = ""; attentionOnly = false
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 224), spacing: 16)], spacing: 16) {
                        ForEach(filteredItems) { item in
                            LibraryItemCard(item: item,
                                            selected: store.selection.contains(item.id),
                                            touchID: store.touchIDEnabled && store.touchIDAvailable,
                                            select: { selectCard(item) },
                                            preview: { store.selection = [item.id]; previewSelection() },
                                            decrypt: { store.selection = [item.id]; decryptPassword = ""; store.showUnlock = true },
                                            reveal: { NSWorkspace.shared.activateFileViewerSelecting([item.resolve()]) })
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 2)
                    .padding(.bottom, 22)
                }
                .focusable()
                .onKeyPress(.space) {
                    guard selectedItems.count == 1, !externalRequestsBlocked else { return .ignored }
                    previewSelection(); return .handled
                }
            }

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
            HStack(spacing: 12) {
                Text("\(filteredItems.count) 项")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                if !store.selection.isEmpty {
                    Text("已选 \(store.selection.count) 项")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                } else if !filteredItems.isEmpty {
                    Button("全选") { store.selection = Set(filteredItems.map(\.id)) }
                        .buttonStyle(BrandGhostButtonStyle())
                }
                Spacer(minLength: 8)
                if !store.selection.isEmpty {
                    Button("清除") { store.selection = [] }
                        .buttonStyle(BrandGhostButtonStyle())
                    Button("查看详情") { libraryGrid = false; showFileDetails = true }
                        .buttonStyle(BrandSecondaryButtonStyle())
                    Button("解密所选…") { decryptPassword = ""; store.showUnlock = true }
                        .buttonStyle(BrandPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background(EasyLockStyle.surfaceRaised)
        }
        .disabled(store.busy)
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
                librarySearchField
                if attentionOnly || store.items.contains(where: { $0.warning != nil || $0.originalRetained }) {
                    Toggle("仅看需检查", isOn: $attentionOnly)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                }
                Spacer(minLength: 8)
                libraryMoreMenu
                libraryAddButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
            .padding(.bottom, 12)

            if store.recoveryPublicKey == nil || !store.recoveries.isEmpty || !store.recoveryErrors.isEmpty {
                libraryAttentionBanner
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
            }

            if store.items.isEmpty {
                dropZone.padding(.horizontal, 24).padding(.bottom, 20)
            } else if filteredItems.isEmpty {
                BrowserEmptyState(symbol: "magnifyingglass",
                                  title: "没有匹配的文件",
                                  detail: "换一个关键词，或查看全部记录。",
                                  actionTitle: "显示全部") {
                    search = ""; attentionOnly = false
                }
            } else {
                HStack(spacing: 0) {
                    ScrollView {
                        LazyVStack(spacing: 1) {
                            ForEach(filteredItems) { item in
                                LibraryListRow(item: item,
                                               selected: store.selection.contains(item.id),
                                               select: { selectCard(item) },
                                               preview: { store.selection = [item.id]; previewSelection() },
                                               decrypt: { store.selection = [item.id]; decryptPassword = ""; store.showUnlock = true },
                                               reveal: { NSWorkspace.shared.activateFileViewerSelecting([item.resolve()]) })
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                    .focusable()
                    .onKeyPress(.space) {
                        guard selectedItems.count == 1, !externalRequestsBlocked else { return .ignored }
                        previewSelection(); return .handled
                    }
                    if showFileDetails && !selectedItems.isEmpty {
                        Rectangle().fill(EasyLockStyle.border).frame(width: 1)
                        fileDetails.frame(width: 340)
                    }
                }
            }

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
            HStack(spacing: 10) {
                Text("\(filteredItems.count) 项")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                if !store.selection.isEmpty {
                    Text("已选 \(store.selection.count) 项")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Button("取消选择") { store.selection = [] }
                        .buttonStyle(BrandGhostButtonStyle())
                } else if !filteredItems.isEmpty {
                    Button("全选") { store.selection = Set(filteredItems.map(\.id)) }
                        .buttonStyle(BrandGhostButtonStyle())
                }
                Spacer(minLength: 8)
                if !selectedItems.isEmpty {
                    Button(showFileDetails ? "收起详情" : "详情") { showFileDetails.toggle() }
                        .buttonStyle(BrandGhostButtonStyle())
                    if selectedItems.count == 1 {
                        Button("预览", action: previewSelection)
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }
                    Button("解密…") { decryptPassword = ""; store.showUnlock = true }
                        .buttonStyle(BrandPrimaryButtonStyle())
                }
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background(EasyLockStyle.surfaceRaised)
        }
        .disabled(store.busy)
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
        FileBadge(name: item.name, locked: true, size: size)
    }

    private var fileDetails: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let item = selectedItems.first, selectedItems.count == 1 {
                    HStack(alignment: .top, spacing: 16) {
                        FileBadge(name: item.name, locked: true, size: 68)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(item.name)
                                .font(.system(size: 17, weight: .semibold))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            FileStatusPill(locked: true,
                                           needsAttention: item.warning != nil || item.originalRetained)
                        }
                    }

                    VStack(spacing: 9) {
                        Button {
                            decryptPassword = ""; store.showUnlock = true
                        } label: {
                            HStack(spacing: 7) {
                                Image(systemName: "lock.open")
                                Text("解密文件…")
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.right").font(.system(size: 9, weight: .semibold))
                            }
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())

                        HStack(spacing: 9) {
                            Button { previewSelection() } label: {
                                Label("预览", systemImage: "eye").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                            .help("选择文件后按空格预览")
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([item.resolve()])
                            } label: {
                                Label("定位", systemImage: "arrow.up.forward.square").frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        }
                    }

                    if let warning = item.warning {
                        InlineNotice(text: warning)
                    }
                    if item.originalRetained {
                        InlineNotice(text: "可能仍有明文副本，请在 Finder 中检查。")
                    }

                    VStack(alignment: .leading, spacing: 0) {
                        SectionLabel(title: "记录信息")
                            .padding(.bottom, 4)
                        detailRow("位置", value: item.path)
                        detailRow("密文大小", value: ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))
                        detailRow("登记时间", value: item.date.formatted(date: .abbreviated, time: .shortened))
                        detailRow("恢复凭据", value: "加密时的密码，或当时启用的恢复密钥")
                    }

                    Text("此处展示本机登记信息，不代表已重新校验文件。解密时会验证密文完整性。")
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)

                    InlineNotice(text: "修改后缀不会解密；无法双击打开时，请拖回 EasyLock。", kind: .info)
                } else if !selectedItems.isEmpty {
                    IconMedallion(symbol: "doc.on.doc", size: 44)
                    Text("已选择 \(selectedItems.count) 个项目")
                        .font(.system(size: 17, weight: .semibold))
                    Text("批量解密将使用同一凭据；使用不同密码的文件请分批处理。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("解密所选…") { decryptPassword = ""; store.showUnlock = true }
                        .buttonStyle(BrandPrimaryButtonStyle())
                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(selectedItems) { entry in
                            HStack(spacing: 8) {
                                FileBadge(name: entry.name, locked: true, size: 24)
                                Text(entry.name).font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                            }
                        }
                    }
                    .padding(.top, 3)
                } else {
                    ShieldMark(size: 54)
                        .padding(.bottom, 2)
                    Text("选择文件，查看详情")
                        .font(.system(size: 17, weight: .semibold))
                    Text("按住 ⌘ 可选择多个项目。也可以将文件或文件夹拖到窗口中添加。")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(EasyLockStyle.surface)
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(value)
                .font(.system(size: 11))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
        }
    }

    private var dropZone: some View {
        let empty = store.items.isEmpty
        return VStack(spacing: empty ? 15 : 12) {
            if empty {
                ZStack(alignment: .bottomTrailing) {
                    ShieldMark(size: 58)
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(EasyLockStyle.buttonText)
                        .frame(width: 20, height: 20)
                        .background(EasyLockStyle.blue, in: Circle())
                        .overlay { Circle().strokeBorder(EasyLockStyle.surface, lineWidth: 2) }
                        .offset(x: 2, y: 2)
                }
                .padding(.bottom, 2)
            }

            HStack(spacing: 9) {
                if !empty {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Text(dropTargeted ? "松开鼠标，添加到 EasyLock" : "拖入文件或文件夹")
                    .font(.system(size: empty ? 19 : 13.5, weight: .semibold))
            }

            if empty {
                Text("无需移动文件的位置，加密后在原处上锁。\n已有加密文件会自动进入解密流程。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }

            HStack(spacing: 9) {
                Button { store.chooseSources() } label: {
                    Label("添加文件", systemImage: "doc.badge.plus")
                }
                .buttonStyle(BrandPrimaryButtonStyle())

                Button { store.chooseSources(foldersOnly: true) } label: {
                    Label("添加文件夹", systemImage: "folder.badge.plus")
                }
                .buttonStyle(BrandSecondaryButtonStyle())
            }

            if empty {
                Button("导入已有加密文件") { store.importFiles() }
                    .buttonStyle(BrandGhostButtonStyle())
            }
        }
        .padding(empty ? 34 : 18)
        .frame(maxWidth: .infinity, maxHeight: empty ? .infinity : nil)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(EasyLockStyle.surface)
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(dropTargeted ? EasyLockStyle.blue : EasyLockStyle.border,
                                  style: StrokeStyle(lineWidth: dropTargeted ? 1.5 : 1,
                                                     dash: dropTargeted ? [7, 5] : [6, 5]))
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .inset(by: 8)
                    .strokeBorder(EasyLockStyle.border.opacity(0.6), lineWidth: 0.8)
            }
        }
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
            HStack(spacing: 16) {
                PageHeading(title: settingsTitle, subtitle: settingsSubtitle, symbol: section.icon)
                Spacer(minLength: 12)
                if section == .about {
                    Button { showHelp = true } label: {
                        Label("使用帮助", systemImage: "questionmark.circle")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 16)

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch section {
                    case .security: securitySettings
                    case .general: generalSettings
                    case .recovery: recoverySettings
                    case .theme: themeSettings
                    case .about: aboutSettings
                    default: EmptyView()
                    }
                }
                .frame(maxWidth: 760, alignment: .leading)
                .padding(.horizontal, 26)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background { WorkspaceBackground() }
        .disabled(store.busy)
    }

    private var settingsTitle: String {
        switch section {
        case .security: "安全与解锁"
        case .general: "常规"
        case .recovery: "恢复与检查"
        case .theme: "主题"
        case .about: "关于"
        default: "设置"
        }
    }

    private var settingsSubtitle: String {
        switch section {
        case .security: "登录方式、自动锁定与恢复密钥"
        case .general: "启动、小组件与快捷操作"
        case .recovery: "检查中断的加密任务并恢复文件"
        case .theme: "外观与加密文件默认视图"
        case .about: "版本、隐私与使用帮助"
        default: ""
        }
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.8.2"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return build.isEmpty ? version : "\(version) · \(build)"
    }

    private var securitySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsGroup("登录与解锁") {
                VStack(spacing: 0) {
                    settingRow("主密码", detail: "更改后，旧文件仍需原密码或对应恢复密钥。") {
                        Button("更改…") { resettingPassword = false; showPasswordChange = true }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        Button("存入“密码”App…") { showPasswordApp = true }
                            .buttonStyle(BrandSecondaryButtonStyle())
                    }
                    rowDivider
                    settingRow("闲置后锁定", detail: "锁屏、睡眠和切换用户时也会锁定；不会自动加密已解密文件。") {
                        Picker("闲置后锁定", selection: Binding(get: { store.autoLockMinutes }, set: { store.setAutoLockMinutes($0) })) {
                            Text("1 分钟").tag(1)
                            Text("5 分钟").tag(5)
                            Text("15 分钟").tag(15)
                            Text("不按闲置锁定").tag(0)
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }
                    rowDivider
                    settingRow("Touch ID", detail: store.touchIDAvailable ? "更改指纹后需重新启用；凭据保存在本机钥匙串。" : store.touchIDReason) {
                        Toggle("Touch ID", isOn: Binding(get: { store.touchIDEnabled }, set: { value in Task { await store.setTouchID(value) } }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(!store.touchIDAvailable && !store.touchIDEnabled)
                    }
                }
            }
            recoveryKeySettings
            recoveryPanel
        }
    }

    private var recoverySettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            recoveryKeySettings
            recoveryPanel
        }
    }

    private var recoveryKeySettings: some View {
        settingsGroup("恢复密钥") {
            VStack(alignment: .leading, spacing: 12) {
                settingRow(store.recoveryPublicKey == nil ? "尚未创建恢复密钥" : "已为新文件启用",
                           detail: "仅适用于启用后新加密的文件。请自行保存完整密钥；更换后保留旧密钥。") {
                    Button(store.recoveryPublicKey == nil ? "创建…" : "更换…", action: beginRecoverySetup)
                        .buttonStyle(BrandSecondaryButtonStyle())
                }
                if let key = store.recoveryPublicKey {
                    HStack(spacing: 8) {
                        Text("密钥标识")
                            .font(.system(size: 9, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(.secondary)
                        Text(RecoveryKey.identifier(key))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(EasyLockStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsGroup("启动与小组件") {
                VStack(spacing: 0) {
                    settingRow("登录时启动 EasyLock") {
                        Toggle("登录时启动 EasyLock", isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) }))
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                    rowDivider
                    settingRow("小组件显示记录数量", detail: "默认隐藏，不共享文件名、路径或密码；系统刷新可能延迟。") {
                        Toggle("小组件显示记录数量", isOn: $widgetShowCount)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: widgetShowCount) { _, _ in WidgetSummary.publish(count: store.items.count) }
                    }
                }
            }

            settingsGroup("快捷操作") {
                VStack(spacing: 0) {
                    shortcutRow(keys: ["space"], title: "预览选中的文件或文件夹")
                    rowDivider
                    shortcutRow(keys: ["⌘", "点击"], title: "选择多个项目")
                    rowDivider
                    shortcutRow(keys: ["esc"], title: "关闭本机文件预览")
                }
            }

            InlineNotice(text: "Finder 中右键选择“服务 → 使用 EasyLock 进行加密或解密”。服务是否显示由 macOS 管理。",
                         kind: .info)
        }
    }

    private var themeSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            settingsGroup("外观主题") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("界面主题", selection: $appearanceMode) {
                        Text("跟随系统").tag("system")
                        Text("浅色").tag("light")
                        Text("深色").tag("dark")
                    }
                    .pickerStyle(.segmented)
                    Text("立即应用到 EasyLock 界面。界面使用无彩色设计，颜色仅用于提示需要检查的项目；动画遵循 macOS 辅助功能设置。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            settingsGroup("加密文件默认视图") {
                settingRow("默认视图", detail: "下次打开“加密文件”页面时使用。") {
                    Picker("默认视图", selection: $libraryGrid) {
                        Text("卡片").tag(true)
                        Text("列表").tag(false)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
            }
        }
    }

    private var aboutSettings: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                BrandMark(size: 76)
                VStack(alignment: .leading, spacing: 6) {
                    Text("EasyLock")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.5)
                    Text("免费的 macOS 离线文件加密工具")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 6) {
                        Text("v\(appVersion)")
                            .font(.system(size: 9.5, design: .monospaced))
                        Text("·")
                        Text(DistributionChannel.name)
                            .font(.system(size: 9.5))
                    }
                    .foregroundStyle(EasyLockStyle.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .background { GlassPanel(radius: 20) }

            HStack(spacing: 0) {
                aboutStat(symbol: "lock.shield", title: "AES-256-GCM", detail: "本地加密")
                statDivider
                aboutStat(symbol: "internaldrive", title: "本机处理", detail: "内容不上传")
                statDivider
                aboutStat(symbol: "person.crop.circle.badge.xmark", title: "无需账号", detail: "不限设备")
            }
            .padding(.vertical, 16)
            .background { GlassPanel(radius: 16) }

            settingsGroup("关于此版本") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(DistributionChannel.updateDescription)
                    Text("云盘与苹果“密码”的同步由相应服务和系统设置管理。")
                    Rectangle().fill(EasyLockStyle.border).frame(height: 1).padding(.vertical, 3)
                    DisclosureGroup("文件保护范围") {
                        Text("实际恢复并校验后才替换原件。支持的文件内容与元数据会恢复，macOS 管理的标记由系统维护。加密不会清除历史缓存、备份及其他明文副本；操作前请关闭编辑这些文件的程序。")
                            .padding(.top, 8)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }

            Button { showHelp = true } label: {
                Label("使用帮助与隐私说明", systemImage: "questionmark.circle")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
        }
    }

    private func settingsGroup<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title)
            GroupBox { content() }
        }
    }

    private func settingRow<Actions: View>(_ title: String, detail: String? = nil, @ViewBuilder actions: () -> Actions) -> some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 8, content: actions)
        }
        .padding(.vertical, 11)
    }

    private func shortcutRow(keys: [String], title: String) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(keys, id: \.self) { KeyCap(text: $0) }
            }
            .frame(width: 92, alignment: .leading)
            Text(title).font(.system(size: 11.5))
            Spacer(minLength: 8)
        }
        .padding(.vertical, 9)
    }

    private func aboutStat(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(EasyLockStyle.ink)
            Text(title).font(.system(size: 11, weight: .semibold))
            Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(EasyLockStyle.border).frame(width: 1, height: 42)
    }

    private var rowDivider: some View {
        Rectangle().fill(EasyLockStyle.border).frame(height: 1)
    }

    private var recoveryPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                IconMedallion(symbol: "arrow.counterclockwise", size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("中断任务恢复").font(.system(size: 12.5, weight: .semibold))
                    Text("扫描曾处理过的目录").font(.system(size: 9.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("刷新") { Task { await store.scanRecoveries() } }
                    .buttonStyle(BrandSecondaryButtonStyle())
                Button("检查目录…") { store.chooseRecoveryFolder() }
                    .buttonStyle(BrandSecondaryButtonStyle())
            }
            Text("启动时检查曾处理过的目录。离线磁盘连接后可刷新；未记录的位置可手动选择。恢复不会覆盖同名文件，也不会删除已发布的结果。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if store.recoveries.isEmpty && store.recoveryErrors.isEmpty {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle")
                    Text("没有发现未完成任务。")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }

            ForEach(store.recoveryErrors, id: \.self) { error in
                InlineNotice(text: error)
            }

            ForEach(store.recoveries) { item in
                Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 8) {
                        Text(item.source.lastPathComponent)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text(item.canRestore ? "可恢复" : "需检查")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(item.canRestore ? EasyLockStyle.success : EasyLockStyle.warning)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(EasyLockStyle.surfaceMuted, in: Capsule())
                    }
                    Text(item.explanation)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        if item.canRestore {
                            Button("恢复任务开始前的文件") { Task { await store.recover(item) } }
                                .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        if item.canDiscard {
                            Button("清理未提交的临时副本") { Task { await store.recover(item, discard: true) } }
                                .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        if item.canDiscard || item.canRestore {
                            Button("重新授权并重试…") { Task { await store.recover(item, discard: item.canDiscard, reauthorize: true) } }
                                .buttonStyle(BrandSecondaryButtonStyle())
                        }
                        Button("在 Finder 中检查") {
                            NSWorkspace.shared.activateFileViewerSelecting([item.folder])
                        }
                        .buttonStyle(BrandGhostButtonStyle())
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(20)
        .background { GlassPanel(radius: EasyLockStyle.cardRadius) }
    }

    private var resultsSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(symbol: "checkmark.seal",
                        title: "任务结果",
                        subtitle: "成功 \(store.outcomes.filter { $0.status == "成功" }.count) 项 · 其他 \(store.outcomes.filter { $0.status != "成功" }.count) 项")
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(store.outcomes) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.status == "成功" ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(item.status == "成功" ? EasyLockStyle.success : EasyLockStyle.warning)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(2)
                                Text(item.detail)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            Spacer(minLength: 12)
                            Text(item.status)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(item.status == "成功" ? EasyLockStyle.success : EasyLockStyle.warning)
                        }
                        .padding(.vertical, 11)
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
            HStack(spacing: 10) {
                if !store.recoveries.isEmpty {
                    Button("查看恢复任务") { store.showResults = false; section = .security }
                        .buttonStyle(BrandSecondaryButtonStyle())
                }
                Spacer()
                Button("完成") { store.showResults = false }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 560)
        .background(EasyLockStyle.background)
    }

    #if EASYLOCK_ENABLE_LICENSING
    private var membership: some View { LicenseView() }
    #endif

    private var encryptionSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(symbol: "lock.doc",
                        title: "原地加密",
                        subtitle: "已选择 \(store.pendingURLs.count) 个项目。加密后仍在原位置，原名称后添加 .easylock。")

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(store.pendingURLs.enumerated()), id: \.element) { index, url in
                        HStack(spacing: 9) {
                            FileBadge(name: url.lastPathComponent, locked: false, size: 22)
                            Text(url.lastPathComponent)
                                .font(.system(size: 11))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 6)
                        if index < store.pendingURLs.count - 1 {
                            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(EasyLockStyle.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxHeight: 130)

            InlineNotice(text: "完成加密、实际恢复与完整校验后，移除原件，仅保留密文。任何校验失败都会中止替换。",
                         kind: .info)

            VStack(alignment: .leading, spacing: 7) {
                SectionLabel(title: "检查")
                ScrollView {
                    Text(store.preflightText)
                        .font(.system(size: 10))
                        .foregroundStyle(store.preflightFailed ? EasyLockStyle.warning : EasyLockStyle.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 100)

                if store.inspectingSources {
                    ProgressView().controlSize(.small).tint(EasyLockStyle.blue)
                }
            }

            if store.preflightFailed {
                HStack(spacing: 9) {
                    Button("授权所在文件夹并重新检查…") { Task { await store.authorizePendingSources() } }
                        .buttonStyle(BrandSecondaryButtonStyle())
                        .disabled(store.inspectingSources)
                    Button("重新检查") { Task { await store.inspectPendingSources() } }
                        .buttonStyle(BrandGhostButtonStyle())
                }
            }

            HStack(spacing: 10) {
                Button("取消") { store.pendingURLs = [] }
                    .buttonStyle(BrandSecondaryButtonStyle())
                Spacer()
                Button("确认原地加密") { Task { await store.encryptPending() } }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .disabled(store.inspectingSources || store.preflightFailed)
            }
        }
        .padding(28)
        .frame(width: 460)
        .background(EasyLockStyle.background)
        .task { await store.inspectPendingSources() }
    }

    private var passwordChangeSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: resettingPassword ? "key.fill" : "lock.rotation",
                        title: resettingPassword ? "重设主密码" : "更改主密码",
                        subtitle: "这不会给已有文件换密码。旧文件仍需原密码，或加密时已启用的恢复密钥。")

            VStack(spacing: 10) {
                if resettingPassword {
                    SecureField("本机对应的恢复密钥", text: $recoveryInput)
                        .textFieldStyle(.plain)
                        .fieldSurface(height: 42)
                } else if currentPasswordVerifiedByTouchID {
                    HStack(spacing: 9) {
                        Label("已通过 Touch ID 验证当前密码", systemImage: "touchid")
                            .font(.system(size: 11))
                        Spacer()
                        Button("改用密码") { currentPassword = ""; currentPasswordVerifiedByTouchID = false }
                            .buttonStyle(BrandGhostButtonStyle())
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 8)
                    .background(EasyLockStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                } else {
                    SecureField("当前主密码", text: $currentPassword)
                        .textFieldStyle(.plain)
                        .fieldSurface(height: 42)
                }
                SecureField("新主密码（至少 10 个字符）", text: $newPassword)
                    .textFieldStyle(.plain)
                    .fieldSurface(height: 42)
                SecureField("再次输入新密码", text: $newConfirmation)
                    .textFieldStyle(.plain)
                    .fieldSurface(height: 42)
            }

            InlineNotice(text: "Touch ID 会关闭，之后可重新启用。旧文件不会自动获得新密码。", kind: .info)

            Toggle("我理解旧文件仍需原有解密凭据", isOn: $changeAcknowledged)
                .font(.system(size: 11.5))

            HStack(spacing: 10) {
                Button("取消") { showPasswordChange = false }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(store.busy)
                Spacer()
                Button("确认更改") {
                    Task {
                        if await store.changeMasterPassword(current: currentPassword, new: newPassword, confirmation: newConfirmation, recovery: resettingPassword ? recoveryInput : nil) { showPasswordChange = false }
                    }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(!changeAcknowledged || store.busy || newPassword.count < 10 || newPassword != newConfirmation)
            }
        }
        .padding(28)
        .frame(width: 470)
        .background(EasyLockStyle.background)
        .disabled(store.busy)
        .interactiveDismissDisabled(store.busy)
        .task {
            store.refreshTouchIDAvailability()
            guard !resettingPassword, store.touchIDEnabled, store.touchIDAvailable, currentPassword.isEmpty else { return }
            if let verified = await store.verifyCurrentPasswordWithTouchID(), showPasswordChange, !Task.isCancelled {
                currentPassword = verified; currentPasswordVerifiedByTouchID = true
            }
        }
        .onDisappear {
            currentPasswordVerifiedByTouchID = false; currentPassword = ""; newPassword = ""
            newConfirmation = ""; recoveryInput = ""; changeAcknowledged = false
        }
    }

    private var recoverySetupSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeader(symbol: "key.fill",
                        title: "保存你的恢复密钥",
                        subtitle: "持有密钥的人可以解密对应文件。请单独保管，应用无法重新显示它。更换密钥时，旧密钥仍需保留。")

            Text(recoveryDraft)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(EasyLockStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                }

            HStack(spacing: 10) {
                Button(recoveryExported ? "已导出，可再次保存…" : "导出密钥…") {
                    recoveryExported = store.exportRecovery(recoveryDraft)
                }
                .buttonStyle(BrandSecondaryButtonStyle())
                Spacer()
                Text("此密钥只显示这一次")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            SecureField("重新输入已保存的完整密钥", text: $recoveryConfirmation)
                .textFieldStyle(.plain)
                .fieldSurface(height: 42)

            InlineNotice(text: "只有确认后才用于新加密文件。已有文件不会自动获得恢复能力。", kind: .info)

            HStack(spacing: 10) {
                Button("取消") { showRecoverySetup = false }
                    .buttonStyle(BrandSecondaryButtonStyle())
                Spacer()
                Button("确认已保存并启用") {
                    if store.enableRecovery(recoveryDraft, confirmation: recoveryConfirmation) { showRecoverySetup = false }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(recoveryConfirmation.trimmingCharacters(in: .whitespacesAndNewlines) != recoveryDraft)
            }
        }
        .padding(28)
        .frame(width: 510)
        .background(EasyLockStyle.background)
    }

    private var prefersDecryptionTouchID: Bool {
        store.touchIDEnabled && store.touchIDAvailable && !useRecovery && decryptPassword.isEmpty
    }

    private var decryptionSheet: some View {
        VStack(alignment: .leading, spacing: 18) {
            SheetHeader(symbol: "lock.open",
                        title: "解密后访问",
                        subtitle: "已选择 \(store.selection.count) 个加密文件。即使后缀被改动，也需要原密码或对应恢复密钥才能恢复。")

            Picker("解密凭据", selection: $useRecovery) {
                Text("文件密码").tag(false)
                Text("恢复密钥").tag(true)
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 7) {
                if useRecovery {
                    SecureField("完整 ELRK1 恢复密钥", text: $recoveryInput)
                        .textFieldStyle(.plain)
                        .fieldSurface(height: 44)
                    Text("仅适用于加密时已启用此密钥的文件；旧文件仍需原密码。")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                } else {
                    SecureField("文件加密密码", text: $decryptPassword)
                        .textFieldStyle(.plain)
                        .fieldSurface(height: 44)
                }
            }

            Toggle("恢复到其他位置，并保留密文", isOn: $restoreElsewhere)
                .font(.system(size: 11.5))

            if restoreElsewhere {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(restoreFolder?.path ?? "尚未选择目录")
                        .font(.system(size: 10.5))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("选择目录…") {
                        if let folder = store.chooseRestoreFolder() { restoreFolder = folder }
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(EasyLockStyle.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                }
            }

            if store.touchIDEnabled && !useRecovery {
                InlineNotice(text: "优先使用 Touch ID。取消验证后可输入密码；其他密码加密的文件需输入对应密码。", kind: .info)
            }

            Text(restoreElsewhere
                 ? "在所选目录恢复原名称和内容，保留原密文。遇到同名文件会停止，不覆盖。"
                 : "在当前目录恢复加密前的原名称与格式。成功后移除密文；遇到其他同名文件会停止，不覆盖。")
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("取消") { store.showUnlock = false; decryptPassword = "" }
                    .buttonStyle(BrandSecondaryButtonStyle())
                Spacer()
                Button(restoreElsewhere ? "恢复副本" : "原地解密") {
                    let secret = decryptPassword; let key = useRecovery ? recoveryInput : nil
                    let destination = restoreElsewhere ? restoreFolder : nil
                    decryptPassword = ""; recoveryInput = ""
                    Task { await store.decryptSelected(with: secret, destination: destination, recovery: key) }
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .keyboardShortcut(prefersDecryptionTouchID ? nil : .defaultAction)
                .disabled((useRecovery ? recoveryInput.isEmpty : decryptPassword.isEmpty) || (restoreElsewhere && restoreFolder == nil))
                if store.touchIDEnabled && store.touchIDAvailable && !useRecovery {
                    Button {
                        let destination = restoreElsewhere ? restoreFolder : nil
                        Task { await store.unlockWithTouchID(decrypt: true, destination: destination) }
                    } label: {
                        Label("Touch ID 解密", systemImage: "touchid")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .keyboardShortcut(prefersDecryptionTouchID ? .defaultAction : nil)
                    .disabled(restoreElsewhere && restoreFolder == nil)
                }
            }
        }
        .padding(28)
        .frame(width: 470)
        .background(EasyLockStyle.background)
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

/// Hides the system sidebar toggle so the light sidebar header stays clean.
/// Navigation remains available from the sidebar itself.
private struct SidebarToggleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { HiderView() }
    func updateNSView(_ view: NSView, context: Context) { (view as? HiderView)?.hideToggle() }

    final class HiderView: NSView {
        private var observers: [NSObjectProtocol] = []

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            hideToggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.hideToggle() }
            if observers.isEmpty {
                let center = NotificationCenter.default
                for name in [NSWindow.didBecomeKeyNotification,
                             NSWindow.didEnterFullScreenNotification,
                             NSWindow.didExitFullScreenNotification] {
                    observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                        self?.hideToggle()
                    })
                }
            }
        }

        func hideToggle() {
            guard let toolbar = window?.toolbar else { return }
            for index in toolbar.items.indices.reversed()
            where toolbar.items[index].itemIdentifier.rawValue.contains("toggleSidebar") {
                toolbar.removeItem(at: index)
            }
        }

        deinit {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }
}

#Preview {
    ContentView(store: VaultStore())
}
