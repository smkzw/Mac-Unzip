# Mac解霸 (MacUnzip) v1.1.8

## 本次更新
- **创建压缩包默认保存到源文件所在目录**，无需再手选路径：
  - 单个文件/文件夹 → 同目录下同名压缩包（如 `报告.pdf` → `报告.zip`）
  - 多个文件 → 第一项所在目录下的 `归档.zip`（英文界面为 `Archive.zip`）
  - 面板中仍可随时点「选择…」改位置
- 其余同 v1.1.7：多选解压、保存保留选中、7z 符号链接防护

## 下载
https://github.com/smkzw/Mac-Unzip/releases/download/v1.1.8/MacUnzip-1.1.8.dmg

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/MacUnzip.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.1.8.dmg.sha256`。

## 开源
源码：https://github.com/smkzw/Mac-Unzip  
官网：https://gerymk.qd.je/
