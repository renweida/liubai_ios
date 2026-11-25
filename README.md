# 留白

留白是一款原生 iOS 阅读 App，从服务器获取中文哲学与心理学短文。首页上下滑动可以切换文章，点开后可连续滚动正文。点击首页的「内容风格」可选择均衡阅读、哲学思辨、心理觉察或温柔疗愈。确定后从下一篇开始优先展示相关内容，并在本机记住偏好。

## 在 Xcode 里运行

使用 Xcode 26 或更新版本打开 `Liubai.xcodeproj`，选择 `Liubai` scheme 和 iOS 26 或更新版本的模拟器，按 **⌘R**。连接真机时，在 Signing & Capabilities 选择开发团队，并设置可用的 Bundle Identifier。按 **⌘U** 可运行 UI 测试。

## 笔记与备份

- 笔记工具栏支持粗体、斜体、下划线、两级标题、引用、项目列表和编号列表。界面直接编辑排版后的文字，存储内容是 Markdown。下划线使用 Markdown 内嵌的 `<u>` 标签。
- 喜欢、收藏夹及笔记保存在 App 私有目录，该目录排除在系统备份之外。设置里的 JSON 导出可将资料保存到你选择的位置。
- 导入会合并喜欢和收藏关系。相同 ID 的收藏夹沿用本机名称，同一篇文章的笔记保留修改时间较新的一份。导入依赖文章 ID，服务端更新正文时需要保留原 ID。

## 接入文章 API

在 App target 的 Build Settings 中将 `ARTICLE_FEED_URL` 设置为完整的 HTTPS 地址，例如 `https://你的域名/api/v1/articles`。

首页每次请求一篇文章。首次请求只传 `style`，后续请求同时传服务端上次返回的 `nextCursor`。风格值为 `balanced`（均衡阅读）、`philosophy`（哲学思辨）、`psychology`（心理觉察）和 `comfort`（温柔疗愈）。

```http
GET /api/v1/articles?style=psychology
GET /api/v1/articles?style=psychology&cursor=eyJwIjoyfQ
```

用 HTTP 200 返回一个文章对象和下一页游标。最后一篇将 `nextCursor` 设为 `null`。当前请求无文章可返回时使用 HTTP 204，响应体留空。游标使用 URL 安全字符，同一风格下按服务端排序逐篇推进。

```json
{
  "article": {
    "id": "return-to-now",
    "category": "心理学",
    "theme": "当下",
    "title": "把自己带回",
    "subtitle": "此刻",
    "excerpt": "当思绪跑得太远，试着回到眼前这件小事。",
    "minutes": 3,
    "source": "AI 生成",
    "markdown": "## 觉察从哪里开始\n\n感受此刻正在发生的一件事。"
  },
  "nextCursor": "eyJwIjoyfQ"
}
```

服务端负责按风格推荐。客户端切换风格时重启该风格的游标序列，保留眼前和此前的文章，并在本机跳过重复 ID。风格偏好、喜欢、收藏和笔记都保存在本机。首页预取下一篇，加载失败时可以重试。

书架通过 `GET /api/v1/articles/{id}` 获取未在本次会话中读取的正文。用 HTTP 200 直接返回同结构的单个文章对象，找不到文章时返回 HTTP 404。`id` 必须唯一且稳定，标题无需分行时将 `subtitle` 设为空字符串。两种接口的单次响应体最多为 8,000,000 字节。

## 打赏

本地运行使用 `Tips.storekit` 的三个消耗型商品。发布前需要在 App Store Connect 为实际 App 创建同 ID 的消耗型内购商品并分别配置价格及上架信息。

- `app.liubai.reader.tip.small`
- `app.liubai.reader.tip.medium`
- `app.liubai.reader.tip.large`

## 字体

标题采用随 App 打包的 [Adobe 思源宋体](https://github.com/adobe-fonts/source-han-serif)，按 SIL Open Font License 1.1 分发。许可证随字体文件提供。
