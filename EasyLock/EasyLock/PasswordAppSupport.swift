import AppKit
import SwiftUI

@MainActor enum PasswordAppSupport {
    private static let clipboard = SensitiveClipboard()
    static func copy(_ password: String) { clipboard.copy(password) }
    static func clearOwnedClipboard() { clipboard.clearOwnedContents() }
    static func open() -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Passwords") else { return false }
        return NSWorkspace.shared.open(url)
    }
}

struct PasswordAppSheet: View {
    let password: String
    @Environment(\.dismiss) private var dismiss
    @State private var message = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("保存到“密码”", systemImage: "key.horizontal.fill").font(.title2.bold())
            Text("在苹果“密码”App 中新建一条记录，将复制的主密码粘贴保存。EasyLock 不会自动确认或覆盖你的密码记录。")
            Text("建议标题：EasyLock · 本机 · \(Date.now.formatted(date: .numeric, time: .omitted))").font(.callout).textSelection(.enabled)
            Label("旧文件可能仍需旧密码，请保留旧记录。", systemImage: "clock.arrow.circlepath").foregroundStyle(.secondary)
            Text("复制的密码将在 30 秒后从当前剪贴板清除；若已复制其他内容，则不会清除。密码同步由你的苹果账户设置决定。").font(.caption).foregroundStyle(.secondary)
            if !message.isEmpty { Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
            HStack {
                Button("完成") { dismiss() }
                Spacer()
                Button("复制密码") { PasswordAppSupport.copy(password); message = "已复制，请在“密码”App 中粘贴保存。" }.disabled(password.isEmpty)
                Button("打开“密码”") {
                    message = PasswordAppSupport.open() ? "请点击新增并保存。完成前不要覆盖旧密码记录。" : "此系统未找到独立的“密码”App。请在系统的密码管理界面手动添加，或升级系统后使用。"
                }.buttonStyle(.borderedProminent)
            }
        }.padding(28).frame(width: 550)
    }
}
