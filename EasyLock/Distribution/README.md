# EasyLock 免费离线版发布准备

截至 2026-10-13，当前为 0.8 开发预览版，尚不是已完成公证或商店审核的发行版本。官网独立版与 Mac App Store 版共用文件格式，均免费、无需账号或激活，不限制设备数量。

## 当前发行策略

- 默认构建不定义 `EASYLOCK_ENABLE_LICENSING`，因此许可证菜单、页面、联网客户端均不编译。历史源码和 LicenseServer 目录保留，不需要部署授权或支付服务。
- 主应用及扩展不申请出站网络权限。应用没有遥测、上传或内置联网更新检查；官网版手动下载更新，商店版由系统 App Store 更新。
- 苹果“密码”、用户选择的云盘目录可能通过系统或其他应用同步；这不属于 EasyLock 自建联网服务，隐私说明需区分这些行为。
- 加密、解密、Touch ID、恢复密钥和小组件不需要许可证。不能因历史授权缓存或激活状态限制用户访问文件。

## 本地验证

从项目目录运行：

```sh
xcodebuild -project EasyLock.xcodeproj -scheme EasyLock -configuration Release -xcconfig Distribution/Direct.xcconfig -derivedDataPath /tmp/EasyLock-offline-direct "ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
xcodebuild -project EasyLock.xcodeproj -scheme EasyLock -configuration Release -xcconfig Distribution/AppStore.xcconfig -derivedDataPath /tmp/EasyLock-offline-store "ARCHS=arm64 x86_64" ONLY_ACTIVE_ARCH=NO build
python3 Tests/check-offline-build.py /tmp/EasyLock-offline-direct/Build/Products/Release/EasyLock.app
python3 Tests/check-offline-build.py /tmp/EasyLock-offline-store/Build/Products/Release/EasyLock.app
```

本地 Release build 仍使用项目的开发签名，不等于发行 Archive、Developer ID 公证或商店分发签名。

## 本次验证结果（2026-10-13）

- 官网与商店分支均通过 Release 双架构构建（arm64 + x86_64），尚未完成 Intel 实机运行验证。
- 两个产物的主应用与三个扩展均通过签名完整性检查，均启用沙盒且没有出站/入站网络权限。
- 检查可执行文件符号，未发现 LicenseStore、LicenseView、许可证重定向代理或 URLSession 引用。此检查用于防止误编入历史客户端，不替代运行时审计。
- 主应用和三个扩展的隐私清单，以及应用内离线隐私正文，已在两个渠道实际产物中验证存在并符合预期。
- 已重新运行 Tests/run-tests.sh 全部测试及 Tests/run-sandbox-tests.sh，全部通过；真实沙盒中的 DOCX、文件夹与 .DS_Store 隔离属性往返和恢复密钥复制恢复均通过。
- 未完成真实界面操作复验、发行 Archive、公证、商店提交或外部安全审查；本次未改动加密算法与文件替换流程。

## 上线前必须完成（按优先级）

### 1. 文件安全与真实使用验收

- [ ] 对加密格式、密钥管理、原件删除与异常恢复流程做独立安全审查。
- [ ] 在有备份的测试数据上完成大文件、深层目录、中文名称、资源分支、标签、ACL、外置盘、磁盘写满、移除磁盘及断电后恢复验证。
- [ ] 真机测试 Touch ID、锁屏、自动锁定、取消任务、改密码后旧文件解密、恢复密钥、跨电脑恢复。不能仅凭编译或单元测试宣称完成。
- [ ] 回归面板重复问题：快速重复点击、连续拖放、操作中打开密文、关闭窗口再打开、错误与结果同时到达。
- [ ] 最低 macOS 14 与当前系统、Apple Silicon 与 Intel 实机矩阵。双架构编译只能证明能构建，不能替代实机运行。

已有程序化验证覆盖原地往返、内容/元数据比对、损坏密文、进程中断恢复、隔离属性、恢复密钥、预览隐私及面板排队；发布前仍需运行完整回归并保存记录。

### 2. 隐私及产品说明

- [x] 主程序及三个扩展已补齐 `PrivacyInfo.xcprivacy`，按实际用途声明文件元数据、磁盘空间、闲置计时及偏好设置，详情见 [隐私清单维护说明](Privacy-Implementation.md)。仍需通过最终归档/商店校验。
- [x] 应用内帮助已包含离线隐私说明；[测试版验收步骤](Testing-Guide.md) 已准备。
- [ ] 将隐私正文发布到公开页面，补齐正式支持方式与下载说明；不需要运行授权服务器。
- [ ] 明确不能找回未备份的密码/恢复密钥，加密不能清除历史备份/缓存/快照；密码 App 当前是手动保存流程。
- [ ] 统一最终 AppIcon、版本号、应用分类、截图及“开发预览版”标识。应用加密功能尚未实现，不应列入宣传。

### 3. 官网独立分发

- [ ] 核实 Developer ID 发布证书及主应用、Preview、Thumbnail、Widget 三个扩展的签名与 App Group 配置。
- [ ] 生成发行 Archive/安装包，完成公证与票据附加。
- [ ] 从实际下载链接在干净 Mac 验证 Gatekeeper、安装、升级、卸载重装及旧文件解密。
- [ ] 提供明确的手动更新渠道、更新日志及版本回退说明。

### 4. Mac App Store 分发

- [ ] 配置 App Store Connect 应用、免费价格、商店签名及扩展标识；不需要 StoreKit 商品或恢复购买流程。
- [ ] 填写隐私披露、加密出口合规、支持及隐私 URL、截图和审核说明。
- [ ] 通过归档验证与商店测试，验收 sandbox 文件夹授权、登录启动、钥匙串、App Group、小组件及 Finder 扩展。

## Finder / Quick Look / Widget 验收

最终安装位置启动后检查：Finder 服务多选文件/文件夹、双击密文冷启动、任务中连续打开、关窗后再次打开、混合普通文件与密文、空格预览、大小图标与深浅色外观。预览只显示固定提示，不读取明文；解密回到主应用。手动修改密文后缀不改变加密内容，但 Finder 的类型关联不保证自动打开 EasyLock；拖入应用应识别文件头。

小组件只共享用户选择显示的记录数量与更新时间，不共享文件名、路径或凭据；实测添加、刷新及各入口，允许系统刷新延迟。

Apple 参考：
- [独立分发与公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
- [隐私清单](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
- [Required-reason API](https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api)
- [发行准备](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution)
