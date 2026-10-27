import SwiftUI
import AppKit

struct OverviewView: View {
    @Bindable var store: VaultStore
    let openLibrary: () -> Void
    let openLocalFiles: () -> Void
    let openSecurity: () -> Void
    let openItem: (LockedItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if !store.recoveries.isEmpty || !store.recoveryErrors.isEmpty {
                    recoveryBanner
                }
                HStack(alignment: .top, spacing: 16) {
                    heroCard
                    metricGrid.frame(width: 318)
                }
                HStack(alignment: .top, spacing: 16) {
                    securityCard
                    activityCard
                }
                recentCard
            }
            .padding(24)
        }
        .background { WorkspaceBackground() }
        .scrollIndicators(.hidden)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("概览")
                    .font(.system(size: 26, weight: .semibold))
                    .tracking(-0.6)
                Text("本机保险箱的状态、检查项和最近记录")
                    .font(.system(size: 12))
                    .foregroundStyle(EasyLockStyle.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)

            HStack(spacing: 6) {
                Circle().fill(EasyLockStyle.success).frame(width: 6, height: 6)
                Text("本机 · 已解锁")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(EasyLockStyle.success)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(EasyLockStyle.successSoft, in: Capsule())
            .overlay { Capsule().strokeBorder(EasyLockStyle.success.opacity(0.18), lineWidth: 1) }

            Menu {
                Button("添加文件…") { store.chooseSources() }
                Button("添加文件夹…") { store.chooseSources(foldersOnly: true) }
                Divider()
                Button("导入已有密文…") { store.importFiles() }
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
            .help("更多添加方式")

            Button { store.chooseSources() } label: {
                Label("添加文件", systemImage: "plus")
            }
            .buttonStyle(BrandPrimaryButtonStyle())
            .disabled(!store.canPresentPicker || store.busy)
        }
        .padding(.bottom, 18)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                IconMedallion(symbol: "lock.shield", size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机保险箱")
                        .font(.system(size: 15, weight: .semibold))
                    Text("所有加密、预览与恢复都在本机完成")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(store.items.count)")
                            .font(.system(size: 40, weight: .semibold))
                            .tracking(-1.2)
                            .monospacedDigit()
                        Text("项")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("加密记录 · \(totalSize)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(store.items.isEmpty ? "还没有加密文件" : "最近登记于 \(latestDate)")
                        .font(.system(size: 10))
                        .foregroundStyle(EasyLockStyle.tertiary)
                }
                Spacer(minLength: 8)
                SecurityRing(completed: completedChecks, total: checks.count, size: 88)
            }

            HStack(spacing: 9) {
                Button { store.chooseSources() } label: {
                    Label("添加文件", systemImage: "doc.badge.plus")
                }
                .buttonStyle(BrandPrimaryButtonStyle())
                .disabled(!store.canPresentPicker || store.busy)

                Button { openLocalFiles() } label: {
                    Label("浏览本机", systemImage: "internaldrive")
                }
                .buttonStyle(BrandSecondaryButtonStyle())

                Spacer(minLength: 4)

                Button("安全设置") { openSecurity() }
                    .buttonStyle(BrandGhostButtonStyle())
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .bottomTrailing) {
                GlassPanel(radius: 22)
                ShieldShape()
                    .stroke(EasyLockStyle.blue.opacity(0.065), lineWidth: 1.4)
                    .frame(width: 270, height: 300)
                    .offset(x: 64, y: 92)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
    }

    private var metricGrid: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                metricCard(title: "加密文件",
                           value: "\(store.items.count)",
                           unit: "项",
                           detail: "本机记录",
                           symbol: "lock.doc",
                           tint: EasyLockStyle.blue,
                           soft: EasyLockStyle.blueSoft)
                metricCard(title: "密文大小",
                           value: sizeValue,
                           unit: sizeUnit,
                           detail: "全部密文",
                           symbol: "internaldrive",
                           tint: EasyLockStyle.blue,
                           soft: EasyLockStyle.blueSoft,
                           valueSize: 22)
            }
            HStack(spacing: 12) {
                metricCard(title: "恢复密钥",
                           value: store.recoveryPublicKey == nil ? "未启用" : "已启用",
                           detail: store.recoveryPublicKey == nil ? "建议创建" : "新文件可恢复",
                           symbol: "key.fill",
                           tint: store.recoveryPublicKey == nil ? EasyLockStyle.warning : EasyLockStyle.success,
                           soft: store.recoveryPublicKey == nil ? EasyLockStyle.warningSoft : EasyLockStyle.successSoft,
                           valueSize: 16)
                metricCard(title: "需检查",
                           value: "\(attentionCount)",
                           unit: "项",
                           detail: attentionCount == 0 ? "暂无异常" : "请检查记录",
                           symbol: "exclamationmark.triangle.fill",
                           tint: attentionCount == 0 ? EasyLockStyle.success : EasyLockStyle.warning,
                           soft: attentionCount == 0 ? EasyLockStyle.successSoft : EasyLockStyle.warningSoft)
            }
        }
    }

    private func metricCard(title: String,
                            value: String,
                            unit: String? = nil,
                            detail: String,
                            symbol: String,
                            tint: Color,
                            soft: Color,
                            valueSize: CGFloat = 24) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 21, height: 21)
                    .background(soft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: valueSize, weight: .semibold))
                    .tracking(-0.4)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let unit {
                    Text(unit)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(detail)
                .font(.system(size: 9.5))
                .foregroundStyle(EasyLockStyle.tertiary)
                .lineLimit(1)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        .background { GlassPanel(radius: 18) }
    }

    // MARK: - Security

    private var securityCard: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EasyLockStyle.blue)
                Text("安全检查")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text("\(completedChecks) / \(checks.count)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(completedChecks == checks.count ? EasyLockStyle.success : EasyLockStyle.blueDeep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(completedChecks == checks.count ? EasyLockStyle.successSoft : EasyLockStyle.blueSoft, in: Capsule())
            }

            Text("仅汇总本机设置，不代表独立安全审计")
                .font(.system(size: 9))
                .foregroundStyle(EasyLockStyle.tertiary)

            VStack(spacing: 2) {
                ForEach(checks) { check in
                    Button { openSecurity() } label: {
                        HStack(spacing: 10) {
                            Image(systemName: check.done ? "checkmark" : "exclamationmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(check.done ? EasyLockStyle.success : EasyLockStyle.warning)
                                .frame(width: 22, height: 22)
                                .background(check.done ? EasyLockStyle.successSoft : EasyLockStyle.warningSoft, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(check.title)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .foregroundStyle(EasyLockStyle.ink)
                                Text(check.detail)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(EasyLockStyle.tertiary)
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button { openSecurity() } label: {
                HStack(spacing: 5) {
                    Text(completedChecks == checks.count ? "查看安全设置" : "完成剩余检查项")
                    Image(systemName: "arrow.right").font(.system(size: 8, weight: .semibold))
                }
            }
            .buttonStyle(BrandGhostButtonStyle())
            .padding(.leading, -6)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GlassPanel(radius: 22) }
    }

    // MARK: - Activity

    private var activityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EasyLockStyle.blue)
                Text("近 7 天登记")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Text("\(weekTotal) 项")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(EasyLockStyle.blueDeep)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(EasyLockStyle.blueSoft, in: Capsule())
            }

            HStack(alignment: .bottom, spacing: 8) {
                ForEach(Array(weekDays.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 6) {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(index == weekDays.count - 1
                                  ? AnyShapeStyle(LinearGradient(colors: [EasyLockStyle.blue, EasyLockStyle.blueDeep],
                                                                 startPoint: .top, endPoint: .bottom))
                                  : AnyShapeStyle(EasyLockStyle.blue.opacity(day.count > 0 ? 0.30 : 0.12)))
                            .frame(height: barHeight(day.count))
                        Text(day.label)
                            .font(.system(size: 8.5, weight: index == weekDays.count - 1 ? .semibold : .regular))
                            .foregroundStyle(index == weekDays.count - 1 ? EasyLockStyle.blueDeep : EasyLockStyle.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 96, alignment: .bottom)
            .padding(.top, 2)

            HStack(spacing: 6) {
                Image(systemName: "internaldrive")
                    .font(.system(size: 9))
                Text("来自本机登记记录，不上传")
                    .font(.system(size: 9))
                Spacer(minLength: 0)
            }
            .foregroundStyle(EasyLockStyle.tertiary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GlassPanel(radius: 22) }
    }

    private func barHeight(_ count: Int) -> CGFloat {
        let maxCount = max(1, weekDays.map(\.count).max() ?? 0)
        guard count > 0 else { return 4 }
        return max(8, CGFloat(count) / CGFloat(maxCount) * 76)
    }

    // MARK: - Recent files

    private var recentCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(EasyLockStyle.blue)
                Text("最近文件")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 6)
                Button("查看全部") { openLibrary() }
                    .buttonStyle(BrandGhostButtonStyle())
            }
            .padding(.bottom, 8)

            if recentItems.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(EasyLockStyle.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("还没有加密记录")
                            .font(.system(size: 11.5, weight: .medium))
                        Text("添加文件后，这里会显示最近的记录。")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button { store.chooseSources() } label: {
                        Label("添加文件", systemImage: "plus")
                    }
                    .buttonStyle(BrandSecondaryButtonStyle())
                    .disabled(!store.canPresentPicker || store.busy)
                }
                .padding(.vertical, 14)
            } else {
                ForEach(recentItems) { item in
                    Button { openItem(item) } label: {
                        HStack(spacing: 12) {
                            FileBadge(name: item.name, locked: true, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.system(size: 11.5, weight: .medium))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text("\(shortDate(item.date)) · \(ByteCountFormatter.string(fromByteCount: Int64(item.size), countStyle: .file))")
                                    .font(.system(size: 9))
                                    .foregroundStyle(EasyLockStyle.tertiary)
                            }
                            Spacer(minLength: 8)
                            FileStatusPill(locked: true,
                                           needsAttention: item.warning != nil || item.originalRetained)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .semibold))
                                .foregroundStyle(EasyLockStyle.tertiary)
                        }
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if item.id != recentItems.last?.id {
                        Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background { GlassPanel(radius: 22) }
    }

    private var recoveryBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.counterclockwise.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(EasyLockStyle.warning)
            Text("有未完成的恢复任务需要检查")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(EasyLockStyle.warning)
            Spacer(minLength: 8)
            Button("检查") { openSecurity() }
                .buttonStyle(BrandGhostButtonStyle())
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(EasyLockStyle.warningSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(EasyLockStyle.warning.opacity(0.22), lineWidth: 1)
        }
    }

    // MARK: - Data

    private var attentionCount: Int {
        store.items.filter { $0.warning != nil || $0.originalRetained }.count
    }

    private var totalBytes: Int {
        store.items.reduce(0) { $0 + $1.size }
    }

    private var totalSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
    }

    private var sizeValue: String {
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        return formatted.split(separator: " ").first.map(String.init) ?? formatted
    }

    private var sizeUnit: String? {
        let formatted = ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)
        let parts = formatted.split(separator: " ")
        return parts.count > 1 ? String(parts[1]) : nil
    }

    private var latestDate: String {
        guard let latest = store.items.map(\.date).max() else { return "—" }
        return shortDate(latest)
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .month(.abbreviated)
                .day()
                .hour()
                .minute()
                .locale(Locale(identifier: "zh_CN"))
        )
    }

    private var recentItems: [LockedItem] {
        Array(store.items.sorted { $0.date > $1.date }.prefix(4))
    }

    private var checks: [SecurityCheck] {
        [
            SecurityCheck(id: "recovery",
                          title: "恢复密钥",
                          detail: store.recoveryPublicKey == nil ? "建议为新文件启用" : "已启用恢复密钥",
                          done: store.recoveryPublicKey != nil),
            SecurityCheck(id: "touchid",
                          title: "Touch ID",
                          detail: store.touchIDEnabled ? "已启用本机指纹解锁" : (store.touchIDAvailable ? "尚未启用" : "当前不可用"),
                          done: store.touchIDEnabled),
            SecurityCheck(id: "autolock",
                          title: "闲置自动锁定",
                          detail: store.autoLockMinutes == 0 ? "当前不会自动锁定" : "闲置 \(store.autoLockMinutes) 分钟后锁定",
                          done: store.autoLockMinutes > 0),
            SecurityCheck(id: "records",
                          title: "记录检查",
                          detail: attentionCount == 0 ? "没有需要检查的记录" : "\(attentionCount) 项记录需要检查",
                          done: attentionCount == 0)
        ]
    }

    private var completedChecks: Int { checks.filter(\.done).count }

    private var weekTotal: Int { weekDays.reduce(0) { $0 + $1.count } }

    private struct WeekDay {
        let label: String
        let count: Int
    }

    private var weekDays: [WeekDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EEEEE"
        return (0..<7).map { offset in
            let date = calendar.date(byAdding: .day, value: offset - 6, to: today) ?? today
            let count = store.items.filter { calendar.isDate($0.date, inSameDayAs: date) }.count
            return WeekDay(label: formatter.string(from: date), count: count)
        }
    }

    private struct SecurityCheck: Identifiable {
        let id: String
        let title: String
        let detail: String
        let done: Bool
    }
}

private struct SecurityRing: View {
    let completed: Int
    let total: Int
    var size: CGFloat = 100

    private var progress: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(completed) / CGFloat(total)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(EasyLockStyle.blueSoft, lineWidth: size * 0.09)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    AngularGradient(colors: [EasyLockStyle.blue, EasyLockStyle.blueDeep, EasyLockStyle.blue],
                                    center: .center),
                    style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(completed)/\(total)")
                    .font(.system(size: size * 0.21, weight: .semibold))
                    .tracking(-0.5)
                    .monospacedDigit()
                Text("检查项")
                    .font(.system(size: size * 0.082, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("安全检查项 \(completed) / \(total)")
    }
}
