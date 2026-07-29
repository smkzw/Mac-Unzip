# MacUnzip 中文官网

## 项目说明

这是一个完全使用中文撰写的高质量商业网站首页，专为 MacUnzip macOS 解压工具设计。整体风格对标小米商城、华为消费者网站等顶级中国品牌官网。

## 核心特性

### 🎨 设计理念
- **正宗中国风**：所有文案均为原创中文营销语言，非机翻
- **色彩体系**：采用小米红 (#E60012) 作为主色调
- **字体优化**：PingFang SC + HarmonyOS Sans + Microsoft YaHei UI
- **信息密度**：比欧美站点提高 40-50%，更符合中国用户阅读习惯

### 📱 响应式设计
- 桌面端：1280px 最大宽度
- 平板：768px 断点
- 移动端：480px 断点
- 单文件 HTML，所有 CSS/JS 内嵌

### ✨ 交互动效
- FAQ 折叠动画（带高度平滑过渡）
- 数字计数器（下载量、用户数、满意度）
- 滚动渐入效果（Intersection Observer）
- 定价卡片悬停放大
- 按钮点击涟漪效果
- Hero 图片视差滚动

## 页面结构

### 1. 导航栏 (Navigation)
- 固定顶部，毛玻璃效果
- 移动端汉堡菜单

### 2. Hero 区域
- 大标题："一键解压，极速体验"
- 格式标签："支持 ZIP/RAR/7Z/TAR 等 30+ 格式"
- 双 CTA：¥79/年立即购买 / 免费下载试用
- 信任指标：★★★★★ 1,200+ 评价 | 500,000+ 下载
- 产品截图 + "全新升级"徽章

### 3. 功能网格 (Features)
6 个功能卡片：
- ⚡ 毫秒级解压 (3x 更快)
- 📦 30+ 格式全覆盖
- 🔐 密码保护 (AES-256)
- 🖼️ 媒体文件预览
- 📂 嵌套文件夹浏览
- 🛡️ 零数据追踪

### 4. 对比表格 (Comparison)
Lite (免费) vs Pro (专业版) 功能对比
- 突出显示价格优势：立省 40 元 vs BetterZip
- 永久授权 · 持续免费升级

### 5. 定价方案 (Pricing)
三栏布局：
- **个人版** ¥79/年 - 基础解压功能
- **专业版** ¥79/年（原价¥119）- 热销推荐
- **企业版** ¥299/年 - 团队协作

优惠标识：
- 原价划线
- 折扣标签："立省 40 元"
- 支付方式：VISA/MC/微信/支付宝
- 分期选项：花呗 3 期免息

### 6. 信任建设 (Trust)
- 认证标识行：ICP 备、公安备案、软著登记
- 统计数据：500,000+ 下载 | 1,200 活跃用户 | 98% 满意度
- 用户评价卡片（含实名认证徽章）

### 7. FAQ 区域
5 个问题 accordion：
- 支持的 macOS 版本
- 免费试用期
- 发票开具
- 使用期限
- 多设备授权

知乎社区链接

### 8. 页脚 (Footer)
- 四栏布局：About / 产品 / 支持 / 客服
- 社交媒体图标：微信/微博/B 站
- 客服专线：400-XXX-XXXX
- 在线咨询按钮
- 合规声明：ICP 备案号 | 公安备案号

## SEO 优化

```html
<title>MacUnzip - 专业 macOS 解压工具 | ZIP RAR 7Z 快速解压软件</title>
<meta name="description" content="MacUnzip 是一款专业的 macOS 解压软件...">
<meta name="keywords" content="macOS 解压工具，RAR 解压，压缩包软件...">

<!-- Open Graph -->
<meta property="og:title" ...>
<meta property="og:description" ...>

<!-- Structured Data (Schema.org) -->
<script type="application/ld+json">
{
    "@type": "SoftwareApplication",
    "name": "MacUnzip",
    "operatingSystem": "macOS",
    ...
}
</script>
```

## 技术参数

- 文件大小：~76KB
- 行数：2070 行
- 纯单文件 HTML
- Google Fonts 预连接
- Baidu Tongji 埋点占位符
- Schema.org 结构化数据

## 浏览器兼容性

- Chrome/Safari/Edge/Firefox 最新版本
- iOS Safari + Android Chrome
- 优雅降级至旧版浏览器

## 使用说明

直接用浏览器打开 `index-zh.html` 即可预览完整效果。

无需构建工具，无需依赖任何外部资源（除了 Google Fonts 和 Unsplash 图片）。

## 自定义替换

需要替换的内容：
1. 产品截图 URL（当前为 Unsplash 示例图）
2. ICP 备案号
3. 公安备案号
4. 客服电话 400-XXX-XXXX
5. Baidu Tongji 统计代码
6. 实际支付网关链接

---

**设计灵感来源**：mi.com、consumer.huawei.com、www.bytedance.com
