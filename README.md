<p align="center"><img src="icon/Icon-iOS-Default-128@2x.png" width="112" alt="EasyLock 图标"></p>
<h1 align="center">EasyLock</h1>
<p align="center">免费的 macOS 离线文件加密工具 · Swift / SwiftUI</p>
<p align="center">无需账号 · 无需激活 · 不限设备数量 · 文件在本机处理</p>

> **开发预览版**：尚未完成正式公证、独立安全审查和完整实机验收。请仅使用有独立备份的测试文件。Release 中的测试包采用开发签名，其他 Mac 可能无法直接运行。

[查看测试版本](https://github.com/YQYQYQ123abc/EasyLock/releases) · [使用支持](https://yqyqyq123abc.github.io/EasyLock/support.html) · [隐私说明](https://yqyqyq123abc.github.io/EasyLock/privacy.html) · [反馈问题](https://github.com/YQYQYQ123abc/EasyLock/issues)

## 0.8.2 Preview 2 · 构建 31

新增本机文件浏览与加解密操作，统一简洁界面和原生浮动预览；修复只读预览副本清理和目录切换失败问题。完整变更、测试范围和升级步骤见 [发布说明](EasyLock/Distribution/ReleaseNotes/0.8.2-preview.2.md)。

## 可以做什么

- **文件与文件夹加密**：支持添加、多选和拖放；原地转换为单个 `.easylock` 密文文件。
- **解密与恢复**：支持批量解密，或解密到其他位置并保留密文。
- **本机快捷解锁**：支持 Touch ID、闲置自动锁定及系统会话锁定。
- **可选恢复密钥**：适用于启用后新加密的文件；完整密钥由你自行保管。
- **Finder 集成**：服务菜单、锁定预览和缩略图；桌面小组件提供快捷入口。
- **离线使用**：没有账号、付费激活、广告或应用内遥测；许可证历史代码保留但默认停用。

## 使用流程

1. 设置并妥善保存主密码，按需创建恢复密钥。
2. 拖入文件/文件夹，检查确认信息后加密；`合同.pdf` 会变成 `合同.pdf.easylock`。
3. 双击密文或拖回应用，使用加密时的密码或对应恢复密钥解密。

更改主密码不会给旧文件换密码。修改文件后缀也不会解密；如果 Finder 不再识别，请拖回 EasyLock。

## 保护范围与限制

应用采用 AES-256-GCM 加密，并在原地替换前进行实际恢复与内容校验。这些实现和现有测试**不等于独立安全审计或零数据丢失保证**。

加密不能清除历史缓存、备份、快照和其他明文副本。符号链接、硬链接、特殊文件及应用程序加密当前不支持。文件系统底层属性不保证完全相同；支持范围见[详细说明](EasyLock/README.md)。

开发者无法找回遗失的密码或恢复密钥。苹果“密码”的保存目前需要用户手动完成；云盘和系统密码同步由相应服务管理。

## 构建与验证

最低 macOS 14，使用支持该项目的 Xcode 打开 `EasyLock/EasyLock.xcodeproj`，选择 `EasyLock` scheme。当前已验证 Intel / Apple Silicon 双架构 Release 构建，完整实机兼容性测试尚未完成。

在 `EasyLock/` 项目目录运行：

```sh
bash Tests/run-tests.sh
bash Tests/run-sandbox-tests.sh
```

两个发行渠道的构建方式、隐私清单检查和剩余事项见[发布清单](EasyLock/Distribution/README.md)。

## 文档与反馈

- [功能与格式说明](EasyLock/README.md)
- [真机验收步骤](EasyLock/Distribution/Testing-Guide.md)
- [隐私清单维护](EasyLock/Distribution/Privacy-Implementation.md)
- [应用内隐私正文](EasyLock/EasyLock/PrivacyPolicy.txt)

反馈请附版本、系统、芯片和复现步骤；不要提交密码、恢复密钥、私人文件或未经处理的完整路径。

免费使用不等于已授予源码再分发许可；仓库当前尚未选定开源许可证。
