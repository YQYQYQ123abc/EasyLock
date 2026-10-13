#if EASYLOCK_ENABLE_LICENSING
import SwiftUI

struct LicenseView: View {
    #if !EASYLOCK_APP_STORE
    @State private var license = LicenseStore()
    @State private var input = ""
    @State private var removal: LicenseReceipt.Device?
    #endif
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 16) { BrandMark(size: 70); Text("EasyLock 许可证").font(.largeTitle.bold()) }
                Text(DistributionChannel.name).foregroundStyle(.secondary)
                #if EASYLOCK_APP_STORE
                Text("商店购买尚未开放").font(.title2)
                Text("此版本将使用 App Store 购买与恢复购买。商品尚未配置；不会接受官网许可证作为商店内的购买入口。").foregroundStyle(.secondary)
                #else
                HStack(alignment: .firstTextBaseline) {
                    Text(license.active ? "已激活" : "开发预览版").font(.title2.bold())
                    Spacer()
                    Text("\(license.receipt?.devices.count ?? 0) / 3 台 Mac").font(.title3.monospacedDigit())
                }
                Text("一份许可证最多同时激活三台 Mac，支持解绑换机。当前预览功能可直接使用。").foregroundStyle(.secondary)
                if license.configured {
                    Text("激活时向授权服务发送许可证、设备标识和设备名称，不发送加密密码或文件内容。").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        SecureField("输入许可证", text: $input).textFieldStyle(.roundedBorder)
                        Button("查看设备") { Task { await license.perform("inspect", license: input); input = "" } }.disabled(input.isEmpty || license.busy)
                        Button("激活本机") { Task { await license.perform("activate", license: input); input = "" } }.disabled(input.isEmpty || license.busy)
                    }
                    if let receipt = license.receipt {
                        Text("授权编号：\(receipt.licenseID.suffix(8))").font(.caption.monospaced())
                        ForEach(receipt.devices) { device in
                            HStack {
                                Label(device.name, systemImage: "laptopcomputer")
                                if device.id == license.deviceID { Text("本机").font(.caption).foregroundStyle(.secondary) }
                                Spacer()
                                Button("解绑") { removal = device }.disabled(license.busy)
                            }.padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        }
                        Text("离线凭据有效至 \(Date(timeIntervalSince1970: receipt.expiresAt).formatted())").font(.caption).foregroundStyle(.secondary)
                        Button("刷新授权") { Task { await license.perform("refresh") } }.disabled(license.busy)
                    }
                    if license.busy { ProgressView("正在验证许可证…") }
                    if let text = license.message { Text(text).font(.callout).textSelection(.enabled) }
                } else {
                    Label("购买与激活尚未开放", systemImage: "clock").font(.headline)
                    Text("正式许可证服务接入后，可在这里激活并管理三台设备。").foregroundStyle(.secondary)
                }
                #endif
                Divider()
                Label("已有文件始终可以解密", systemImage: "lock.open").font(.headline)
                Text("断网、许可证到期或解绑设备，不影响取回你自己的文件。").foregroundStyle(.secondary)
                Text(DistributionChannel.updateDescription).font(.caption).foregroundStyle(.secondary)
            }.padding(36).frame(maxWidth: 680, alignment: .leading)
        }
        #if !EASYLOCK_APP_STORE
        .safeAreaInset(edge: .bottom) {
            if let device = removal {
                VStack(alignment: .leading, spacing: 10) {
                    Text("解绑“\(device.name)”？").font(.headline)
                    Text("释放一个激活名额。离线设备的缓存授权最多 7 天后失效；解密始终可用。").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button("取消") { removal = nil }
                        Spacer()
                        Button("确认解绑", role: .destructive) {
                            removal = nil
                            Task { await license.perform("deactivate", target: device.id) }
                        }.disabled(license.busy)
                    }
                }.padding(20).background(.bar)
            }
        }
        #endif
    }
}

#endif
