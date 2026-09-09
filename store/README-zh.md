# MacUnzip 中文官网

## 项目说明

MacUnzip 官网（中文 `index-zh.html` / 英文 `index.html`）。产品已全面开源，免费下载，无付费购买流程。

## 当前产品定位

- **完全开源**：主仓库 https://github.com/smkzw/Mac-Unzip（已公开）
- **永久免费**：无购买、无订阅、无许可证、无账号
- **主 CTA**：免费下载 DMG（直链 GitHub Release）
- **次 CTA**：查看 GitHub 源码
- **Lite 精简版**：https://github.com/smkzw/MacUnzip-Lite
- **联系邮箱**：smkzw@163.com
- **版本**：v1.1.6，macOS 26+，Apple Silicon only

## 页面结构

### 1. 导航栏
- 固定顶部，毛玻璃效果
- 移动端汉堡菜单
- 主 CTA：免费下载 DMG

### 2. Hero 区域
- 标题：一键解压，极速体验
- 双 CTA：免费下载 DMG / 查看源码
- 标注：免费开源 · 永久免费 · 无订阅

### 3. 功能网格
6 个功能卡片：原生极速解压、40+ 格式、密码保护、媒体预览、嵌套浏览、零数据追踪

### 4. 对比表格
Lite（免费） vs 完整版（免费）功能对比。两个版本都免费，完整版功能全部包含在开源构建中。

### 5. 免费开源区（原定价区）
两栏布局：
- **Lite 开源版**：免费，链接到 MacUnzip-Lite 仓库
- **MacUnzip 完整版**：免费，下载 DMG + 查看源码

### 6. 信任区
- 开源可审计 / 8 层安全防护 / 40+ 格式
- 统计数据：40+ 格式 / 8 层防护 / 0 遥测

### 7. FAQ
- 支持的 macOS 版本
- 是否完全免费
- 源码在哪里
- 是否需要账号或激活码
- Gatekeeper 首次打开说明（右键打开 / xattr 去隔离）
- 是否收集数据
- 技术支持方式

### 8. 页脚
- GitHub 主仓库 / Releases / Lite 仓库 / 支持邮箱
- 版本 v1.1.6
- 语言切换（`/` 中文、`/en.html` 英文）

## 部署

部署合同见 [DEPLOY.md](DEPLOY.md)。

线上地址：
- 中文：https://gerymk.qd.je/
- 英文：https://gerymk.qd.je/en.html

## 设计说明

- 中文页：小米红主色，PingFang SC 字体栈
- 英文页：深色主题，Inter 字体
- 单文件 HTML，CSS/JS 内嵌
- 响应式：桌面 / 平板 / 移动端
- Intersection Observer 滚动动画（含无 JS 兜底）
