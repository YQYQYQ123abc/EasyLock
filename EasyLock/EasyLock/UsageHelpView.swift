import SwiftUI

struct UsageHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                IconMedallion(symbol: "lock.shield", size: 42)
                VStack(alignment: .leading, spacing: 4) {
                    Text("使用 EasyLock")
                        .font(.system(size: 20, weight: .semibold))
                        .tracking(-0.3)
                    Text("加密、预览与恢复的完整流程")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("帮助")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(EasyLockStyle.surfaceMuted, in: Capsule())
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    tip(1, symbol: "lock.doc", title: "加密文件或文件夹", body: "拖入 EasyLock，或使用“添加文件”“添加文件夹”。也可以在 Finder 右键菜单的“服务”中选择“使用 EasyLock 加密或解密”。首次操作可能需要授权所在文件夹，以便在原位置替换文件。")
                    tip(2, symbol: "lock.shield", title: "查看上锁状态", body: "加密后，原名称后添加 .easylock。空格预览只显示锁定提示，缩略图只显示锁形图案。预览窗口不读取密码、不显示原始内容；关闭预览并双击文件即可解密。")
                    tip(3, symbol: "space", title: "应用内按空格预览", body: "解锁应用后，在文件列表选择一个项目并按空格，或点击详情中的“预览”。验证文件密码、对应恢复密钥或 Touch ID 后查看，文件夹可双击展开。原密文不会修改；关闭或锁定后清理应用临时明文。系统预览可能保留缓存，敏感文件请按需使用。")
                    tip(4, symbol: "lock.open", title: "安全解密", body: "双击 .easylock 文件，输入加密时使用的密码，或对应恢复密钥。也可以选择“解密到其他文件夹”，保留密文并生成可访问的副本。更改主密码不会更改已有文件的密码。")
                    tip(5, symbol: "key.fill", title: "忘记密码前做好准备", body: "在“安全与解锁”中启用并保存恢复密钥。它只适用于启用后新加密的文件。Touch ID 是这台 Mac 的快捷验证方式，不能替代异机恢复所需的密码或恢复密钥。")
                    tip(nil, symbol: "key.horizontal", title: "保存到苹果“密码”", body: "在“安全与解锁”中选择保存主密码，复制后打开苹果“密码”App 并新建记录。复制内容 30 秒后清除。保留旧密码记录，因为更改主密码不会更改已有密文。")
                    tip(nil, symbol: "square.grid.2x2", title: "桌面小组件", body: "在 macOS 的编辑小组件界面搜索 EasyLock，选择小号或中号组件。点击进入应用后验证身份，再添加文件。默认不显示数量；可在安全设置中开启，系统刷新可能稍有延迟。")
                    tip(nil, symbol: "puzzlepiece.extension", title: "Finder 未出现入口或预览", body: "请先从固定的安装位置运行一次 EasyLock；如果系统要求，请在系统设置中允许 EasyLock 的扩展或服务。安装多个开发版本可能影响系统选择的扩展，正式发布前需在干净环境验证。")
                    tip(nil, symbol: "textformat", title: "关于修改后缀", body: "修改后缀只会影响 macOS 选择哪个应用打开文件，不会解密。若改名后双击未进入 EasyLock，请将文件拖回应用。EasyLock 无法拦截其他应用对任意后缀文件的打开请求。")

                    DisclosureGroup {
                        Text(privacyPolicy)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 8)
                    } label: {
                        Text("隐私说明（离线可读）")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .padding(13)
                    .background(EasyLockStyle.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                    }
                    .padding(.top, 14)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 10) {
                Text("EASYLOCK · LOCAL VAULT")
                    .font(.system(size: 8, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(EasyLockStyle.tertiary)
                Spacer()
                Button("知道了") { dismiss() }
                    .buttonStyle(BrandPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 600, height: 620)
        .background(EasyLockStyle.background)
    }

    private var privacyPolicy: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "隐私说明资源未能读取，请从正式发布渠道重新安装。"
        }
        return text
    }

    private func tip(_ number: Int?, symbol: String, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if let number {
                    Text("\(number)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(EasyLockStyle.buttonText)
                        .frame(width: 22, height: 22)
                        .background(EasyLockStyle.blue, in: Circle())
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(EasyLockStyle.blueDeep.opacity(0.85))
                        .frame(width: 22, height: 22)
                        .background(EasyLockStyle.surfaceMuted, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(EasyLockStyle.border, lineWidth: 1)
                        }
                }
            }
            .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(body)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .overlay(alignment: .bottom) {
            Rectangle().fill(EasyLockStyle.border).frame(height: 1)
        }
    }
}
