# Mac解霸 (MacUnzip) v1.2.1

## 重大变更
- 统一应用分发版本，开放全部应用功能。
- 发布页提供应用下载和源码入口

## 本版功能
- RAR 解压 fallback（7zz 不支持的压缩方法自动改用 RARLAB rar）
- 7zz 引擎 26.03
- 拖入文件夹/文件自动开启新建压缩包
- 默认保存到源文件目录
- 多选解压（含跨层级）
- 文件列表列宽可调整
- 7z 符号链接防护

## 下载
https://github.com/smkzw/Mac-Unzip/releases/download/v1.2.1/MacUnzip-1.2.1.dmg

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/MacUnzip.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.2.1.dmg.sha256`。

## 开源
源码：https://github.com/smkzw/Mac-Unzip
