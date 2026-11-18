# MacUnzip 网站源码

本目录包含 Mac 解霸的静态双语页面。英文入口为 [index.html](index.html)，中文入口为 [index-zh.html](index-zh.html)。两页共用样式，并引用仓库中的图标和示例截图。应用下载入口为 [GitHub Releases](https://github.com/smkzw/Mac-Unzip/releases)。

从仓库根目录运行 `python3 -m http.server --bind 127.0.0.1 8000`，访问 `http://127.0.0.1:8000/store/index-zh.html` 或 `http://127.0.0.1:8000/store/index.html`，即可在本机预览。

v1.3.0 的 Release 构建内置 `7zz` 26.03（arm64），7z 无需 Homebrew。源码 Debug 构建可使用已检测到的外部 `7zz`。创建 RAR 需另装 RARLAB 官方 `rar`。

应用采用 [MIT 许可证](../LICENSE)。[engine-versions.json](engine-versions.json)供应用内可选的引擎版本检查使用。静态文件布局和现有端点见[部署指南](DEPLOY.md)。
