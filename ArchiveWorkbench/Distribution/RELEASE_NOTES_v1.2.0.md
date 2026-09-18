# Mac解霸 (MacUnzip) v1.2.0

## 本次更新
- **RAR 解压 fallback**：当 7zz 引擎不支持某种 RAR 压缩方法（如 RAR 7.23 method m1）时，自动改用 RARLAB `rar` 工具解压
- **7zz 引擎升级** 26.02 → 26.03
- **列宽可调整**：文件列表所有列现在支持拖动调整宽度
- **错误提示改进**：RAR 不支持的压缩方法会明确提示原因和替代方案
- 其余同 v1.1.9：拖入即压缩、默认保存到源目录、多选解压、7z 符号链接防护

## 依赖说明
- RAR 解压 fallback 需要本机安装 RARLAB `rar` 工具：`brew install rar`
- 未安装 rar 时，7zz 能处理的 RAR 照常工作

## 下载
https://github.com/smkzw/Mac-Unzip/releases/download/v1.2.0/MacUnzip-1.2.0.dmg

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/MacUnzip.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.2.0.dmg.sha256`。

## 开源
源码：https://github.com/smkzw/Mac-Unzip  
官网：https://gerymk.qd.je/
