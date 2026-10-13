import SwiftUI

struct UsageHelpView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("使用 EasyLock", systemImage: "lock.shield").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    tip("1. 加密文件或文件夹", "拖入 EasyLock，或使用“添加文件”“添加文件夹”。也可以在 Finder 右键菜单的“服务”中选择“使用 EasyLock 加密或解密”。首次操作可能需要授权所在文件夹，以便在原位置替换文件。")
                    tip("2. 查看上锁状态", "加密后，原名称后添加 .easylock。空格预览只显示锁定提示，缩略图只显示锁形图案。预览窗口不读取密码、不显示原始内容；关闭预览并双击文件即可解密。")
                    tip("3. 安全解密", "双击 .easylock 文件，输入加密时使用的密码，或对应恢复密钥。也可以选择“解密到其他文件夹”，保留密文并生成可访问的副本。更改主密码不会更改已有文件的密码。")
                    tip("4. 忘记密码前做好准备", "在“安全与设置”中启用并保存恢复密钥。它只适用于启用后新加密的文件。Touch ID 是这台 Mac 的快捷验证方式，不能替代异机恢复所需的密码或恢复密钥。")
                    tip("保存到苹果“密码”", "在“安全与设置”中选择保存主密码，复制后打开苹果“密码”App 并新建记录。复制内容 30 秒后清除。保留旧密码记录，因为更改主密码不会更改已有密文。")
                    tip("桌面小组件", "在 macOS 的编辑小组件界面搜索 EasyLock，选择小号或中号组件。点击进入应用后验证身份，再添加文件。默认不显示数量；可在安全设置中开启，系统刷新可能稍有延迟。")
                    tip("Finder 未出现入口或预览", "请先从固定的安装位置运行一次 EasyLock；如果系统要求，请在系统设置中允许 EasyLock 的扩展或服务。安装多个开发版本可能影响系统选择的扩展，正式发布前需在干净环境验证。")
                    DisclosureGroup("隐私说明（离线可读）") {
                        Text(privacyPolicy).font(.callout).foregroundStyle(.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                    tip("关于修改后缀", "修改后缀只会影响 macOS 选择哪个应用打开文件，不会解密。若改名后双击未进入 EasyLock，请将文件拖回应用。EasyLock 无法拦截其他应用对任意后缀文件的打开请求。")
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack { Spacer(); Button("知道了") { dismiss() }.keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width: 590, height: 590)
    }
    private var privacyPolicy: String {
        guard let url = Bundle.main.url(forResource: "PrivacyPolicy", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "隐私说明资源未能读取，请从正式发布渠道重新安装。"
        }
        return text
    }
    private func tip(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.headline)
            Text(body).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
