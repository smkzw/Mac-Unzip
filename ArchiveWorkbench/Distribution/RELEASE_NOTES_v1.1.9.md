# Mac解霸 (MacUnzip) v1.1.9

## 本次更新
- **拖入即压缩**：将文件夹、普通文件或多选混合拖入 App 窗口或 Dock 图标，自动开启新建压缩包流程（默认保存到源文件所在目录）
  - 全部是压缩包 → 打开第一个（原行为不变）
  - 含文件夹或普通文件 → 自动弹出新建压缩包面板
- 修复 Xcode 27 / Swift 6.4 类型检查超时：通知处理逻辑拆分为独立 ViewModifier
- 其余同 v1.1.8：默认保存到源文件目录、多选解压、7z 符号链接防护

## 下载
https://github.com/smkzw/Mac-Unzip/releases/download/v1.1.9/MacUnzip-1.1.9.dmg

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/MacUnzip.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.1.9.dmg.sha256`。

## 开源
源码：https://github.com/smkzw/Mac-Unzip  
官网：https://gerymk.qd.je/
