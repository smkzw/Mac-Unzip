# MacUnzip 静态站部署指南

部署源为当前仓库的 `store/` 和下表所列仓库文件。请先核对目标站点和静态目录归属，再在选定站点发布这些文件。站点根路径默认使用英文页，中文页为 `/index-zh.html`。

| 仓库源文件 | 静态站路径 |
| --- | --- |
| [store/index.html](index.html) | `/index.html` |
| [store/index-zh.html](index-zh.html) | `/index-zh.html` |
| [store/site.css](site.css) | `/site.css` |
| [store/robots.txt](robots.txt) | `/robots.txt` |
| [ArchiveWorkbench/Assets/Logo.svg](../ArchiveWorkbench/Assets/Logo.svg) | `/ArchiveWorkbench/Assets/Logo.svg` |
| [ArchiveWorkbench/Assets/screenshots/app_media_light.png](../ArchiveWorkbench/Assets/screenshots/app_media_light.png) | `/ArchiveWorkbench/Assets/screenshots/app_media_light.png` |
| [ArchiveWorkbench/Assets/screenshots/app_media_dark.png](../ArchiveWorkbench/Assets/screenshots/app_media_dark.png) | `/ArchiveWorkbench/Assets/screenshots/app_media_dark.png` |
| [LICENSE](../LICENSE) | `/LICENSE` |

保留上述相对位置。发布后打开双语页面，检查语言切换、图片、MIT 文本和 [GitHub Releases](https://github.com/smkzw/Mac-Unzip/releases) 下载入口。站点源未配置正式域名。若需要 canonical URL、sitemap 或旧页面重定向，请在确定实际域名和路由后配置。

## 引擎版本检查

[engine-versions.json](engine-versions.json)保存 `7zz` 和 `rar` 的版本字符串。它属于应用更新提示的数据源。仓库里的文件路径应保留为 `store/engine-versions.json`。

当前 [SettingsView.swift](../ArchiveWorkbench/App/Sources/SettingsView.swift) 依次尝试以下端点：

- `gerymk.qd.je` 上的 `/engine-versions.json` 和 `/store/engine-versions.json`。
- GitHub raw 文件，按 `release`、`main` 顺序读取 `store/engine-versions.json`。
- GitHub Contents API，按 `release`、`main` 顺序读取同一文件。

以上是现有客户端中写入的地址。若另行迁移清单，应先验证旧客户端对原路径和 GitHub 回退的兼容性，并用实际客户端确认读取成功。
