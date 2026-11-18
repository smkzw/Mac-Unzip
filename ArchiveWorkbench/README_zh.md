# Mac 解霸工程入口

[项目首页](../README_zh.md)提供下载、格式说明和使用介绍。应用采用 [MIT 许可证](../LICENSE)。

- 在配有 Swift 6.2 工具链的 Xcode 26 中打开 [MacUnzip.xcodeproj](MacUnzip.xcodeproj)，选择 **MacUnzip** scheme 开发应用和运行测试。
- v1.3.0 的 Release 构建内置 `7zz` 26.03（arm64），使用 7z 无需 Homebrew。源码 Debug 构建可使用检测到的外部 `7zz`。创建 RAR 需另行安装 RARLAB 官方 `rar`。
- [project.yml](project.yml) 是 XcodeGen 工程源，应与仓库中的 Xcode 工程同步。
- [ArchiveKit](Packages/ArchiveKit/Package.swift) 是本地 Swift 软件包，提供归档引擎、文件操作和安全策略。
- 本地构建和分发见[构建指南](Distribution/BUILD_PROFILES.md)、[签名与公证指南](Distribution/SIGNING_RUNBOOK.md)及[第三方许可声明](Distribution/THIRD_PARTY_NOTICES.md)。
- [网站源码](../store/README-zh.md)位于仓库的 `store/` 目录。

[English](README.md)
