# Mac解霸 (MacUnzip) v1.1.2

> 历史版本记录。当前版本见 [GitHub Releases](https://github.com/smkzw/Mac-Unzip/releases)。

## 本次更新
- 引擎更新 opt-in 检测：设置→引擎新增「检测引擎更新」开关（默认关）。开启后可点击「检测更新」，仅读取版本号并提示前往官网更新；不下载、不写入任何可执行文件，保持零下载与供应链安全
- 其余同 v1.1.1：编码自动修复可视化徽标、扁平头栏、Windows 兼容拦截、双击修复

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/Mac解霸.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.1.2.dmg.sha256`。
