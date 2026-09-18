# Mac解霸 (MacUnzip) v1.2.1

## 重大变更
- **彻底移除激活机制与 Pro/Lite 区分**：全部功能永久免费，无需激活码、无需许可证
- 删除 LicenseManager / LicenseGate / 激活界面 / 内嵌激活码
- 删除所有 Pro 门禁、Pro 徽章、菜单 Pro 后缀
- 移除激活码生成与嵌入脚本
- 官网与产品文案统一为完全开源免费

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
官网：https://gerymk.qd.je/
