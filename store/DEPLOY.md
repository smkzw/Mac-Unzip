# MacUnzip 官网部署说明（gerymk.qd.je）

> **产品模式：完全开源、免费下载。**  
> 付费购买 / 支付宝扫码 / 激活码 / 退款等文案已从官网全部移除。  
> 主 CTA 为「免费下载 DMG」，直链 GitHub Release。

## 源文件布局（本仓库 `store/`）

| 源文件 | 线上路径 | 说明 |
|---|---|---|
| `index-zh.html` | `/` | 中文首页（主语言） |
| `index.html` | `/en.html` | 英文页 |
| `engine-versions.json` | `/engine-versions.json` **且** `/store/engine-versions.json` | App 引擎更新清单（仅版本号，无二进制） |
| `robots.txt` | `/robots.txt` | |
| `sitemap.xml` | `/sitemap.xml` | |
| `mockups/*` | `/mockups/*` | |

## 一键 rsync（在开发机执行）

```bash
SRC="/Users/smkzw/Documents/AI Products/.worktrees/build-opt/store"
# 将 DST 换成你的 VPS webroot，例如 root@gerymk.qd.je:/var/www/gerymk.qd.je/html
DST="root@gerymk.qd.je:/var/www/gerymk.qd.je/html"

# 映射源文件到线上路径
rsync -avz --delete \
  --exclude 'README-zh.md' \
  --exclude 'test.html' \
  --exclude 'mockups.zip' \
  "$SRC/mockups/" "$DST/mockups/"
rsync -avz "$SRC/index-zh.html" "$DST/index.html"
rsync -avz "$SRC/index.html" "$DST/en.html"
rsync -avz "$SRC/engine-versions.json" "$DST/engine-versions.json"
rsync -avz "$SRC/engine-versions.json" "$DST/store/engine-versions.json"
rsync -avz "$SRC/robots.txt" "$DST/robots.txt"
rsync -avz "$SRC/sitemap.xml" "$DST/sitemap.xml"
```

## 部署后自检

```bash
curl -sI https://gerymk.qd.je/ | head -5
curl -sI https://gerymk.qd.je/en.html | head -5
curl -s https://gerymk.qd.je/engine-versions.json
curl -s https://gerymk.qd.je/store/engine-versions.json
curl -sI https://gerymk.qd.je/robots.txt
curl -sI https://gerymk.qd.je/sitemap.xml
curl -sI https://gerymk.qd.je/mockups/app-interface-dark.svg
```

期望：全部 200；`engine-versions.json` 返回 `{"7zz":"26.02","rar":"7.23"}`。

## 下载链接（官网直接引用）

- DMG 直链：`https://github.com/smkzw/Mac-Unzip/releases/download/v1.1.6/MacUnzip-1.1.6.dmg`
- 最新 Release 页：`https://github.com/smkzw/Mac-Unzip/releases/latest`
- 主仓库（已公开）：`https://github.com/smkzw/Mac-Unzip`
- Lite 精简版：`https://github.com/smkzw/MacUnzip-Lite`

## App 侧依赖

`SettingsView` 引擎更新会依次请求：

1. `https://gerymk.qd.je/engine-versions.json`
2. `https://gerymk.qd.je/store/engine-versions.json`
3. `raw.githubusercontent.com/.../release/store/engine-versions.json`
4. `raw.githubusercontent.com/.../main/store/engine-versions.json`
5. GitHub API contents（release / main）

只要部署上面两份 json，端点 1/2 即可用。
