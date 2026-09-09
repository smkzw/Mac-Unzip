# Mac解霸 (MacUnzip) v1.1.7

## 本次更新
- **多选解压**：文件列表支持 ⌘/⇧ 多选，可同时选中不同层级的文件与文件夹；右键「解压选中（N 项）」批量解压。选中父文件夹时自动忽略其子孙，避免重复解压。
- **保存后保留界面上下文**：⌘S / 另存为不再重置选中项、多选集合、视图模式与目录。
- **7z/RAR/DMG/ISO 安全**：解析 7zz 列表中的符号链接并在打开时拒绝；解压前预检不再空转，避免 `7zz x` 穿越 symlink 写出。
- **构建与发布**：CI 覆盖 `release` 分支并跑 ArchiveKit/单元测试；打包脚本版本对齐 project.yml；嵌入 dylib 重签加 `--timestamp`；删除死嵌套 workflow。
- **完全开源**：产品与 Releases 已公开，官网改为免费下载 DMG（无购买/激活码）。

## 下载
https://github.com/smkzw/Mac-Unzip/releases/download/v1.1.7/MacUnzip-1.1.7.dmg

## 首次打开提示
本版本为 ad-hoc 签名、未经 Apple 公证。若系统提示无法打开，请在 Finder 中右键该应用 → 打开；或在终端执行：

```
xattr -dr com.apple.quarantine /Applications/MacUnzip.app
```

## 校验
SHA-256 见随附文件 `MacUnzip-1.1.7.dmg.sha256`。

## 开源
源码：https://github.com/smkzw/Mac-Unzip  
官网：https://gerymk.qd.je/
