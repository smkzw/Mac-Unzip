# Mac解霸 (MacUnzip) v1.1.6

> 历史版本记录。当前版本见 [GitHub Releases](https://github.com/smkzw/Mac-Unzip/releases)。

## 本次更新
- 修复从压缩包**拖出文件/文件夹到 Finder** 失效：
  - 拖出的文件/文件夹目标路径重复导致拷贝失败
  - 文件夹拖出时临时解压目录未创建，导致失败
  - 压缩包内由路径隐含的文件夹（无显式目录条目）此前无法拖出
- 修复反复双击/Finder 打开压缩包导致窗口越开越多的问题（改为复用主窗口）
- 其余同 v1.1.5：Finder 双击/拖入打开、解压默认同目录、长中文文件名支持

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/Mac解霸.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.1.6.dmg.sha256`。
