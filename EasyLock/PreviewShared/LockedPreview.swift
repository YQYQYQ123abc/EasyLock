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
    static func messages(_ state: State) -> (title: String, subtitle: String, action: String) {
        let title: String, subtitle: String, action: String
        switch state {
        case .locked:
            title = "此文件或文件夹已上锁"
            subtitle = "内容已加密保护，Finder 不会显示原始内容。"
            action = "关闭预览后双击文件，在 EasyLock 中验证身份并解密。\n更多信息与使用说明，请打开 EasyLock 查看。"
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
        return (title, subtitle, action)
    }
    static func html(_ state: State) -> Data {
        let (title, subtitle, action) = messages(state)
        let icon = state == .locked ? "<div class='lock' aria-hidden='true'></div>" : "<div class='unrecognized' aria-hidden='true'>?</div>"
        // Only static strings enter this document. No filenames, paths, payload bytes or remote resources.
        return Data("""
        <!doctype html><html lang="zh-CN"><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <meta name="color-scheme" content="light dark">
        <style>
        body{margin:0;padding:36px 32px;background:radial-gradient(ellipse at top left,#e9eefc,transparent 65%),radial-gradient(ellipse at bottom right,#f3e3f2,transparent 65%),#f7f8fc;color:#252940;font:15px -apple-system,BlinkMacSystemFont,sans-serif;text-align:center}
        .lock{position:relative;width:94px;height:94px;margin:25px auto 28px;border-radius:28px;background:linear-gradient(135deg,#5b7fe8,#bf74bd);box-shadow:0 12px 28px #647cce30}
        .lock:before{content:'';position:absolute;width:26px;height:27px;border:5px solid white;border-radius:18px 18px 0 0;left:29px;top:19px}
        .lock:after{content:'';position:absolute;left:23px;top:42px;width:48px;height:34px;border-radius:8px;background:radial-gradient(ellipse at center,#7f70c5 0 13%,white 15%)}
        .unrecognized{margin:25px auto;font-size:64px;color:#8b79b1}
        h1{font-size:26px;font-weight:600;letter-spacing:-.5px}p{line-height:1.8;margin:12px auto;max-width:440px;color:#70768b}
        footer{display:inline-block;margin-top:22px;padding:7px 16px;border:1px solid #dce1ef;border-radius:99px;font-size:11px;letter-spacing:2px;color:#68779f}
        @media(prefers-color-scheme:dark){body{background:radial-gradient(ellipse at top left,#263052,transparent 65%),#171924;color:#eef0ff}p{color:#aeb4cc}footer{border-color:#3b4259;color:#adbce5}}
        </style>\(icon)
        <h1>\(title)</h1><p>\(subtitle)</p><p>\(action)</p><footer>EASYLOCK · 本地隐私保护</footer></html>
        """.utf8)
    }
}
