# 隐私清单维护说明

2026-10-13，适用于默认免费离线构建。每个可执行目标有自己的 PrivacyInfo.xcprivacy；源文件存在不代表打包成功，必须检查最终 .app 与全部 .appex 的 Contents/Resources。

## 主程序

- FileTimestamp / C617.1、3B52.1：FileMetadata、LockEngine、StreamArchive 使用 lstat/fstat 检查授权文件与内部事务文件的类型、大小和元数据，用于安全归档与恢复。
- DiskSpace / E174.1、85F4.1：SpacePreflight 使用 statfs，空间不足时阻止写入，并向用户显示需要和可用的空间。
- SystemBootTime / 35F9.1：AutoLockController 使用 systemUptime 计算应用内闲置时间，触发自动锁定，不上传系统启动时间。
- UserDefaults / CA92.1：VaultStore、WidgetSummary、ContentView 保存本应用偏好与授权书签；小组件共享使用独立 JSON 文件，不是共享 UserDefaults。

## 预览与缩略图

各声明 FileTimestamp / 3B52.1。共同的 LockedPreview 使用 fstat 验证系统交付的预览文件为普通文件，再读取固定长度密文标识；即便只读取文件类型，也按所使用的 API 声明。

## 小组件

当前应用代码读取 App Group 中的 summary.json，不直接调用 required-reason API，访问类别为空。后续加入 UserDefaults 或文件属性访问时需重新检查。

## 数据披露

所有目标声明不跟踪、无跟踪域名、无由本应用收集上传的数据。此声明不表示本机没有文件列表、访问书签或操作恢复记录。用户可在应用帮助中展开隐私说明，完整正文为 ../EasyLock/PrivacyPolicy.txt。公开发布前应将同一正文放在可公开访问的页面，并填写正式支持联系方式。

检查脚本 Tests/check-offline-build.py 会校验每个产物的清单、用途代码、隐私正文、离线权限与签名完整性。它不能代替 App Store 校验或对将来新增 API 的人工检查。不要为消除警告而添加与真实功能不符的用途。

依据：[Apple 的 API 类别及批准用途](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)。
