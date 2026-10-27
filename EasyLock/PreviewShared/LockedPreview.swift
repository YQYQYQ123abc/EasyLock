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
        let locked = state == .locked
        let accent = locked ? "#1D55F0" : "#D97706"
        let shade = locked ? "#5B8DEF" : "#F5C26B"
        let deep = locked ? "#1746D1" : "#B45309"
        let badge = locked ? "已上锁" : "需检查"
        let emblemAction = locked ? """
        <path d="M41 53 v-7 a9 9 0 0 1 18 0 v7" fill="none" stroke="#fff" stroke-width="4.6" stroke-linecap="round"/>
        <rect x="34" y="50" width="32" height="25" rx="6" fill="#fff"/>
        <circle cx="50" cy="59" r="3.1" fill="\(deep)"/><path d="M48.2 61 h3.6 v6.5 h-3.6z" fill="\(deep)"/>
        """ : """
        <rect x="47" y="36" width="6" height="25" rx="3" fill="#fff"/>
        <circle cx="50" cy="70" r="3.2" fill="#fff"/>
        """
        // Only static strings enter this document. No filenames, paths, payload bytes or remote resources.
        return Data("""
        <!doctype html><html lang="zh-CN"><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <meta name="color-scheme" content="light dark">
        <style>
        :root{--paper:#F5F8FD;--surface:#FFFFFF;--ink:#101828;--muted:#667085;--faint:#98A2B3;--line:#DCE7F7;--accent:#1D55F0;--soft:#E8F1FF;--halo:#FFFFFF}
        @media(prefers-color-scheme:dark){:root{--paper:#090B10;--surface:#111827;--ink:#F2F4F7;--muted:#98A2B3;--faint:#667085;--line:#263244;--accent:#7AA2FF;--soft:#16233A;--halo:#17233A}}
        *{box-sizing:border-box}
        body{margin:0;min-height:100vh;padding:44px 28px 30px;display:flex;flex-direction:column;align-items:center;justify-content:center;
          background:radial-gradient(ellipse at 50% -10%,var(--halo) 0%,var(--paper) 62%);color:var(--ink);
          font:14px/1.65 -apple-system,BlinkMacSystemFont,"SF Pro Text",sans-serif;text-align:center}
        .badge{display:inline-flex;align-items:center;gap:6px;margin-bottom:13px;padding:4px 10px;border:1px solid var(--line);
          border-radius:99px;background:var(--soft);color:var(--accent);font-size:10px;font-weight:600;letter-spacing:.3px}
        .badge i{width:5px;height:5px;border-radius:50%;background:var(--accent);display:block}
        .seal{width:94px;height:104px;margin-bottom:20px;filter:drop-shadow(0 12px 20px rgba(29,85,240,.18))}
        .seal svg{width:100%;height:100%;display:block}
        h1{font-size:25px;line-height:1.3;font-weight:600;letter-spacing:-.4px;margin:0 0 9px}
        .sub{font-size:14px;color:var(--muted);margin:0 auto 18px;max-width:420px}
        .action{font-size:13px;line-height:1.9;color:var(--muted);margin:0 auto;max-width:440px;white-space:pre-line}
        footer{margin-top:28px;padding:6px 14px;border:1px solid var(--line);border-radius:99px;
          background:var(--surface);font-size:9.5px;font-weight:600;letter-spacing:1.8px;color:var(--faint)}
        </style>
        <div class="badge"><i></i>\(badge)</div>
        <div class="seal" aria-hidden="true"><svg viewBox="0 0 100 110" xmlns="http://www.w3.org/2000/svg">
        <defs><linearGradient id="shield" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stop-color="\(shade)"/><stop offset=".58" stop-color="\(accent)"/><stop offset="1" stop-color="\(deep)"/>
        </linearGradient></defs>
        <path d="M50 2 L87 17 C94 20 96 25 95 33 C92 62 76 90 50 106 C24 90 8 62 5 33 C4 25 6 20 13 17 Z" fill="url(#shield)"/>
        <path d="M50 13 L80 25 C85 27 86 30 85 35 C82 59 69 81 50 94 C31 81 18 59 15 35 C14 30 15 27 20 25 Z" fill="none" stroke="#fff" stroke-opacity=".52" stroke-width="1.6"/>
        \(emblemAction)
        </svg></div>
        <h1>\(title)</h1><p class="sub">\(subtitle)</p><p class="action">\(action)</p><footer>EASYLOCK · LOCAL VAULT</footer></html>
        """.utf8)
    }

}
