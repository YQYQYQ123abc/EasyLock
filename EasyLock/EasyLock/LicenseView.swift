#if EASYLOCK_ENABLE_LICENSING
import SwiftUI

struct LicenseView: View {
    #if !EASYLOCK_APP_STORE
    @State private var license = LicenseStore()
    @State private var input = ""
    @State private var removal: LicenseReceipt.Device?
    #endif
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                PageHeading(title: "许可证", subtitle: DistributionChannel.name, symbol: "seal")
                Spacer(minLength: 12)
                #if !EASYLOCK_APP_STORE
                statusChip
                #endif
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)

            Rectangle().fill(EasyLockStyle.border).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(spacing: 18) {
                        BrandMark(size: 76)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("EasyLock 许可证")
                                .font(.system(size: 22, weight: .semibold))
                                .tracking(-0.4)
                            Text("一份许可证最多同时激活三台 Mac，支持解绑换机。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text("当前预览功能可直接使用。")
                                .font(.system(size: 10))
                                .foregroundStyle(EasyLockStyle.tertiary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(22)
                    .background { GlassPanel(radius: 20) }

                    #if EASYLOCK_APP_STORE
                    settingsCard("商店购买") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("商店购买尚未开放").font(.system(size: 14, weight: .semibold))
                            Text("此版本将使用 App Store 购买与恢复购买。商品尚未配置；不会接受官网许可证作为商店内的购买入口。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    #else
                    if license.configured {
                        settingsCard("激活与设备") {
                            VStack(alignment: .leading, spacing: 14) {
                                Text("激活时向授权服务发送许可证、设备标识和设备名称，不发送加密密码或文件内容。")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                HStack(spacing: 9) {
                                    HStack(spacing: 8) {
                                        Image(systemName: "key.fill")
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundStyle(EasyLockStyle.tertiary)
                                        SecureField("输入许可证", text: $input)
                                            .textFieldStyle(.plain)
                                            .font(.system(size: 11.5))
                                    }
                                    .fieldSurface(height: 38)

                                    Button("查看设备") {
                                        Task { await license.perform("inspect", license: input); input = "" }
                                    }
                                    .buttonStyle(BrandSecondaryButtonStyle())
                                    .disabled(input.isEmpty || license.busy)

                                    Button("激活本机") {
                                        Task { await license.perform("activate", license: input); input = "" }
                                    }
                                    .buttonStyle(BrandPrimaryButtonStyle())
                                    .disabled(input.isEmpty || license.busy)
                                }

                                if let receipt = license.receipt {
                                    Text("授权编号：\(receipt.licenseID.suffix(8))")
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)

                                    VStack(spacing: 6) {
                                        ForEach(receipt.devices) { device in
                                            HStack(spacing: 9) {
                                                Image(systemName: "laptopcomputer")
                                                    .font(.system(size: 11))
                                                    .foregroundStyle(.secondary)
                                                Text(device.name).font(.system(size: 11.5))
                                                if device.id == license.deviceID {
                                                    Text("本机")
                                                        .font(.system(size: 8.5, weight: .semibold))
                                                        .padding(.horizontal, 6)
                                                        .padding(.vertical, 2)
                                                        .background(EasyLockStyle.surfaceMuted, in: Capsule())
                                                }
                                                Spacer()
                                                Button("解绑") { removal = device }
                                                    .buttonStyle(BrandGhostButtonStyle())
                                                    .disabled(license.busy)
                                            }
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 9)
                                            .background(EasyLockStyle.surfaceRaised, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                                    .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                                            }
                                        }
                                    }

                                    HStack(spacing: 10) {
                                        Text("离线凭据有效至 \(Date(timeIntervalSince1970: receipt.expiresAt).formatted())")
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                        Spacer()
                                        Button("刷新授权") { Task { await license.perform("refresh") } }
                                            .buttonStyle(BrandSecondaryButtonStyle())
                                            .disabled(license.busy)
                                    }
                                }

                                if license.busy {
                                    ProgressView("正在验证许可证…")
                                        .font(.system(size: 10.5))
                                        .tint(EasyLockStyle.ink)
                                }
                                if let text = license.message {
                                    InlineNotice(text: text, kind: .info)
                                }
                            }
                        }
                    } else {
                        settingsCard("购买与激活") {
                            VStack(alignment: .leading, spacing: 7) {
                                Label("购买与激活尚未开放", systemImage: "clock")
                                    .font(.system(size: 13, weight: .semibold))
                                Text("正式许可证服务接入后，可在这里激活并管理三台设备。")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    #endif

                    settingsCard("始终可解密") {
                        VStack(alignment: .leading, spacing: 7) {
                            Label("已有文件始终可以解密", systemImage: "lock.open")
                                .font(.system(size: 13, weight: .semibold))
                            Text("断网、许可证到期或解绑设备，不影响取回你自己的文件。")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(DistributionChannel.updateDescription)
                                .font(.system(size: 10))
                                .foregroundStyle(EasyLockStyle.tertiary)
                        }
                    }
                }
                .frame(maxWidth: 700, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .background { WorkspaceBackground() }
        #if !EASYLOCK_APP_STORE
        .safeAreaInset(edge: .bottom) {
            if let device = removal {
                VStack(alignment: .leading, spacing: 10) {
                    Text("解绑“\(device.name)”？")
                        .font(.system(size: 13, weight: .semibold))
                    Text("释放一个激活名额。离线设备的缓存授权最多 7 天后失效；解密始终可用。")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("取消") { removal = nil }
                            .buttonStyle(BrandSecondaryButtonStyle())
                        Spacer()
                        Button("确认解绑", role: .destructive) {
                            removal = nil
                            Task { await license.perform("deactivate", target: device.id) }
                        }
                        .buttonStyle(BrandPrimaryButtonStyle())
                        .disabled(license.busy)
                    }
                }
                .padding(20)
                .background(EasyLockStyle.surfaceRaised)
                .overlay(alignment: .top) {
                    Rectangle().fill(EasyLockStyle.border).frame(height: 1)
                }
            }
        }
        #endif
    }

    #if !EASYLOCK_APP_STORE
    private var statusChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(license.active ? EasyLockStyle.ink : EasyLockStyle.tertiary)
                .frame(width: 5, height: 5)
            Text(license.active ? "已激活" : "开发预览版")
                .font(.system(size: 9.5, weight: .semibold))
            Text("· \(license.receipt?.devices.count ?? 0) / 3 台")
                .font(.system(size: 9.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(EasyLockStyle.surface, in: Capsule())
        .overlay { Capsule().strokeBorder(EasyLockStyle.border, lineWidth: 1) }
    }
    #endif

    private func settingsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: title)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                .background { GlassPanel(radius: EasyLockStyle.cardRadius) }
        }
    }
}

#endif
