import Foundation
import Darwin

/// Shared only by preview extensions. Never links crypto, keychain, file indexing or decryption code.
enum LockedPreview {
    enum State: Equatable { case locked, unsupported, invalid, unavailable }
    static func inspect(_ url: URL) -> State {
        guard url.isFileURL else { return .invalid }
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
        guard fd >= 0 else { return .unavailable }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { return .invalid }
        let prefix = Data("EASYLOCK\u{0}".utf8)
        var bytes = [UInt8](repeating: 0, count: prefix.count + 2)
        var count = 0
        while count < bytes.count {
            let capacity = bytes.count - count
            let readCount = bytes.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress!.advanced(by: count), capacity) }
            if readCount < 0 && errno == EINTR { continue }
            guard readCount > 0 else { return readCount == 0 ? .invalid : .unavailable }
            count += readCount
        }
        let header = Data(bytes)
        guard header.starts(with: prefix) else { return .invalid }
        let version = String(decoding: header.suffix(2), as: UTF8.self)
        return ["01", "02", "03", "04"].contains(version) ? .locked : .unsupported
    }
    static func html(_ state: State) -> Data {
        let title: String, subtitle: String, action: String
        switch state {
        case .locked:
            title = "此项目已加密"
            subtitle = "请解密后访问。预览不会显示文件内容。"
            action = "关闭预览后双击文件，在 EasyLock 中输入密码或对应恢复密钥。"
        case .unsupported:
            title = "需要较新版本的 EasyLock"
            subtitle = "此项目使用了当前预览扩展尚不支持的文件格式。"
            action = "请使用兼容版本的 EasyLock 打开；修改后缀不会解密。"
        case .invalid:
            title = "无法识别此文件"
            subtitle = "没有识别到受支持的 EasyLock 文件头。"
            action = "仅修改后缀不会加密文件。请在 EasyLock 中检查，避免误认为内容已受保护。"
        case .unavailable:
            title = "暂时无法读取此项目"
            subtitle = "文件可能不在本机，或缺少读取权限。"
            action = "请确认文件已下载、所在磁盘已连接，再用 EasyLock 打开。"
        }
        let icon = state == .locked ? "<div class='lock' aria-hidden='true'></div>" : "<div class='unrecognized' aria-hidden='true'>?</div>"
        // Only static strings enter this document. No filenames, paths, payload bytes or remote resources.
        return Data("""
        <!doctype html><html lang="zh-CN"><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <meta name="color-scheme" content="light dark">
        <style>
        body{margin:0;padding:48px 32px;background:#ffffff;color:#282b48;font:15px -apple-system,BlinkMacSystemFont,sans-serif;text-align:center}
        .lock{position:relative;width:78px;height:62px;margin:55px auto 30px;border-radius:16px;border:2px solid #171717;background:#5778d6}
        .lock:before{content:'';position:absolute;width:40px;height:38px;border:9px solid #5778d6;border-bottom:0;border-radius:28px 28px 0 0;left:10px;top:-32px}
        .lock:after{content:'';position:absolute;left:34px;top:22px;width:10px;height:22px;border-radius:8px;background:#c16eb3}
        .unrecognized{margin:40px auto 25px;font-size:70px;color:#6b708a}
        h1{font-size:25px;font-weight:600;letter-spacing:-.5px}p{line-height:1.7;margin:12px auto;max-width:460px;color:#6b708a}
        footer{margin-top:35px;font-size:12px;letter-spacing:2px;color:#7d829e}
        @media(prefers-color-scheme:dark){body{background:#1d2030;color:#eef0ff}p{color:#aeb4d4}.lock{background:#939cff}.lock:before{border-color:#939cff}.lock:after{background:#303653}}
        </style>\(icon)
        <h1>\(title)</h1><p>\(subtitle)</p><p>\(action)</p><footer>EASYLOCK · 本地隐私保护</footer></html>
        """.utf8)
    }
}
