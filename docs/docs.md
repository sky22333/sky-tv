# 项目开发指南

本文档面向参与 sky-tv 开发、审查、重构和发版的 AI 编码代理。任何改动前必须先阅读本文档，并以当前仓库真实代码为准。

开发迭代前务必阅读：https://github.com/flutter/skills

## 项目定位

sky-tv 是一个现代化跨平台视频播放器空壳应用。

项目只提供播放器、MacCMS 影视源管理、搜索、分类浏览、收藏、继续观看、首页推荐和 IPTV 直播能力，不内置、不托管、不分发任何影视、直播、频道、节目单或版权资源。

所有源地址和播放内容由用户自行导入，用户必须自行确保内容合法合规。

## 核心原则

- 最少代码实现最佳方案。
- 先理解当前真实代码，再分析问题和修改。
- 修 Bug 必须定位根因，禁止靠猜测堆补丁。
- 一个问题只保留一条清晰实现路径。
- 新增实现时同步清理被替代的旧代码。
- 不为低概率假设增加复杂兜底。
- 不保留新项目不需要的历史兼容逻辑。
- UI 风格必须统一、整齐、干净。
- 交互流程必须闭环，错误状态必须可理解。
- 性能优先考虑真实使用场景，避免主线程阻塞和无意义重复请求。

## 当前技术栈

- Flutter / Dart（SDK 见 `pubspec.yaml`）
- Riverpod 状态管理
- GoRouter 路由
- media_kit / media_kit_video / media_kit_libs_video 播放器
- sqlite3 本地持久化（`path_provider` 定位数据目录）
- http 网络请求
- shared_preferences 轻量设置
- FlexColorScheme / Material 3 主题
- cached_network_image 图片缓存
- screen_brightness / volume_controller 播放器手势辅助
- GitHub Actions 手动发布流水线

依赖版本以 `pubspec.yaml` 和 `pubspec.lock` 为准。升级第三方依赖前必须确认当前版本文档、源码或变更说明，不能根据旧经验判断。

## 导航与路由

底部导航（`lib/app/shell.dart`）共 5 项；宽屏（≥700px）使用 `NavigationRail`，窄屏使用 `NavigationBar`。

| Tab | 路径 | 页面 |
| --- | --- | --- |
| 首页 | `/` | `HomePage` |
| 搜索 | `/search` | `SearchPage` |
| 直播 | `/live` | `LivePage` |
| 影视 | `/sources` | `SourcesPage` |
| 设置 | `/settings` | `SettingsPage` |

壳外独立路由（`lib/app/router.dart`，无底部导航）：

| 路径 | 页面 | 说明 |
| --- | --- | --- |
| `/detail/:sourceId/:mediaId` | `DetailPage` | 影片详情 |
| `/player/:sourceId/:mediaId` | `PlayerPage` | 点播播放；query：`line`、`episode`、`resume` |
| `/category/:sourceId/:categoryId` | `CategoryPage` | 分类列表 |
| `/live/:channelId` | `LivePlayerPage` | 直播播放 |

路径辅助：`lib/app/routes.dart`（`SkyRoutes`）。

## 数据流

```text
UI（features/）
  → Riverpod Provider（data/repositories/app_providers.dart）
    → Repository（source / media / iptv / settings）
      → AppDatabase（sqlite3）或 MacCmsApi / http 上游
```

规则：

- 页面不直接请求上游，不直接解析 MacCMS/IPTV 原始字段。
- 网络请求头统一由 `requestHeadersProvider` 注入（含自定义 UA）。
- Provider 定义集中在 `app_providers.dart`，不在页面层散落。

## 文件结构

```text
lib/
  main.dart                 入口：MediaKit 初始化、ProviderScope、SkyTvApp

  app/
    app.dart                  MaterialApp.router、主题绑定
    router.dart               GoRouter 路由表
    routes.dart               SkyRoutes 路径构造
    shell.dart                底部导航 / 侧栏导航壳

  core/
    models/
      media_models.dart       分类、MediaItem/Detail、PlayLine、续看、订阅模型
      video_source.dart       MacCMS 影视源模型
      iptv_models.dart        IPTV 订阅与频道模型
    parser/
      maccms_parser.dart      MacCMS JSON → 领域模型
      play_url_parser.dart      播放地址分集解析
      source_importer.dart    影视源 JSON 导入
      iptv_parser.dart        M3U/M3U8/TXT/JSON 频道解析
    source/
      source_id.dart          源 ID、名称、URL 规范化
    upstream/
      maccms_api.dart         MacCMS 上游请求（categories/search/detail/recent）

  data/
    repositories/
      app_providers.dart      全部 Riverpod Provider
      source_repository.dart  影视源读写、订阅导入/刷新、测速
      media_repository.dart   搜索并发、缓存、首页推荐、收藏/续看
      iptv_repository.dart    IPTV 订阅导入/刷新、频道库
      settings_repository.dart 主题、自定义 UA（shared_preferences）
    storage/
      app_database.dart       sqlite3 表结构与 CRUD

  features/
    home/
      home_page.dart          搜索入口、为你推荐、续看、收藏
    search/
      search_page.dart        多源并发搜索、分批加载
    sources/
      sources_page.dart       影视浏览（分类预览）+ 源管理/导入
    category/
      category_page.dart      分类影片网格
    detail/
      detail_page.dart        详情、收藏、选集入口
    player/
      player_page.dart        点播页：内联/弹层选集、续看、下一集
      player_scaffold.dart    竖屏/宽屏播放页壳、固定播放器布局
      player_surface.dart     media_kit 控制条主题、全屏、手势
      live_player_page.dart   直播播放、切台
    live/
      live_page.dart          直播列表、分组、搜索
      live_channel_tile.dart  频道卡片
      live_group_selector.dart 分组选择器
    settings/
      settings_page.dart      主题、UA、缓存清理、数据刷新

  ui/
    theme/
      app_theme.dart          FlexColorScheme 亮/暗主题
      app_system_ui.dart      状态栏、全屏、SystemUiRestorer
    widgets/
      app_dialogs.dart        确认弹窗、统一文本输入弹窗
      app_search_field.dart   搜索框
      app_logo.dart           品牌标题组件
      poster_card.dart        PosterImage / PosterCard / ContinueWatchCard
      poster_row.dart         横向海报行（推荐、续看、收藏）
      poster_fallback.dart    海报占位（统一图标）
      state_views.dart        Loading/Empty/Error/SectionHeader 等

test/
  maccms_parser_test.dart
  source_importer_test.dart
  play_url_parser_test.dart
  iptv_parser_test.dart

docs/
  docs.md                     本文件（AI 开发规范入口）

assets/
  brand/logo.png              应用内品牌图标

.github/workflows/
  release.yml                 手动生产发布流水线

AGENTS.md                     指向 ./docs/docs.md
```

## 关键业务边界

### 影视源（MacCMS）

- 影视源身份以 `name + api_url` 生成稳定 ID（`core/source/source_id.dart`）。
- 不使用独立 `key` 字段。
- MacCMS 请求集中在 `MacCmsApi`；响应解析在 `MacCmsParser`。
- 源本地读写、订阅拉取、测速集中在 `SourceRepository`。
- `SourcesPage` 同时承担**浏览**（源切换、分类预览、进详情/分类）和**管理**（导入 JSON、订阅 URL、测速、启用/删除）；管理入口在 AppBar「源管理」。
- 直接粘贴 JSON 导入的源**不会**写入 `source_subscriptions`，因此不参与自动订阅刷新。

### 影视数据（MediaRepository）

- 搜索：对启用源并发请求，批次大小与并发上限见 `MediaRepository` 常量；结果以 `Stream<SearchEvent>` 推送。
- 详情、搜索、分类预览、首页推荐均有内存缓存，带条目上限与 TTL。
- 首页推荐（`homeRecommendProvider`）：优先续看所在源，最多尝试 3 个源；调用 `MacCmsApi.recentVideos(h=72)`；过滤已在续看/收藏中的条目；10 分钟内存缓存。
- 分类列表持久化在 `source_categories` 表；预览行在 `categoryPreviewRowsProvider`。
- 收藏、续看、最近搜索关键词持久化在 sqlite；续看主键为 `(source_id, media_id)`。

### 订阅自动刷新

- 影视订阅：进入 `SourcesPage` 后 `addPostFrameCallback` 触发 `SourceRepository.refreshDueSubscriptions()`。
- IPTV 订阅：进入 `LivePage` 后同样方式触发 `IptvRepository.refreshDueSubscriptions()`。
- 规则：距上次检查超过 6 小时才拉取；影视每次最多 5 条、IPTV 每次最多 3 条；内容 hash 不变则只更新检查时间，不重导源。
- 不在 `app_providers.dart` Provider 创建时触发刷新。

### IPTV

- 支持 M3U、M3U8、TXT 和 JSON 订阅。
- 大量频道解析不得阻塞主线程（`iptv_parser.dart` 保持异步或 isolate）。
- 直播列表与直播播放页复用 `IptvChannel` 与 `live_channel_tile.dart`。
- 切台只切换播放器媒体，不反复创建页面路由。

### 播放器

- 核心使用 `media_kit` + `media_kit_video`；控制条主题与全屏逻辑在 `player_surface.dart`。
- 竖屏点播页：`player_scaffold.dart` 固定顶部播放器 + 下方滚动内容；黑色状态栏（`playerPortraitSystemUi`）。
- 宽屏断点 `playerWideBreakpoint = 1000`：AppBar + 左右分栏；侧栏内联选集。
- 播放器内部手势优先使用官方 controls API（音量/亮度/seek/双击/长按加速）。
- 不自定义复杂手势层；不恢复曾造成严重问题的全屏锁定逻辑。
- 全屏返回/退出须在 fullscreen 控件自身 `BuildContext` 上调用 `exitFullscreen`；弹层关闭须在弹层内 `Navigator.pop`。
- 点播下一集、直播下一频道由业务层（`player_page.dart` / `live_player_page.dart`）控制；控制条通过 `onNext`、`selectorAction` 暴露回调。
- 选集单路径：页面内联 / BottomSheet / 全屏·宽屏侧栏共用 `_EpisodeList → _EpisodeGrid → _EpisodeTile`；`overlay` 区分深色侧栏与扁平 BottomSheet 样式。

### 自定义 UA

- UA 存储在 `SettingsRepository`（shared_preferences）。
- `requestHeadersProvider` 统一注入；MacCMS、订阅拉取、测速、IPTV 拉取、播放请求复用同一份 header。
- 页面层不应重复拼接 header。

### 设置与缓存

- 主题：系统 / 浅色 / 深色。
- 「刷新首页数据」：`invalidate(homeDataProvider)` + `invalidate(homeRecommendProvider)`。
- 「清理缓存」：清理 Repository 内存缓存与数据库中的分类缓存等（见 `settings_page.dart` 实现）。

## UI 规范

- 默认优先移动端体验；宽屏布局在各自页面用 `LayoutBuilder` 分支（常见断点：700、1000px）。
- 页面遵守系统安全区；`AppSystemUi` / `SystemUiRestorer` 管理状态栏与全屏。
- 底部导航、状态栏和背景色协调。
- 列表密度适中，信息层级清晰。
- 删除、清理等破坏性操作必须二次确认（`confirmActionDialog`）。
- 文本输入统一走 `showAppTextInputDialog`（`app_dialogs.dart`）。
- 搜索、导入、加载、空状态和错误状态有清晰反馈（`state_views.dart`）。
- 不使用无意义装饰动画或复杂视觉噪声。
- 海报统一走 `PosterImage`（`cached_network_image` + `PosterFallback`）；列表卡片用 `PosterCard`（底部渐变叠标题与 meta）。
- 首页「为你推荐 / 继续观看 / 我的收藏」均为 `PosterRow` / `ContinueWatchRow` 横向滚动（宽 118，2:3）；分类页用 `densePosterGridDelegate`。
- 解码尺寸由 `posterMemCacheFor(展示宽度)` 按 DPR 计算，勿在页面层重复写 `CachedNetworkImage`。

## 性能规范

- 避免在 `build` 中做网络请求、数据库写入或重计算。
- 首页等 Provider 适当使用 `skipLoadingOnReload: true`，避免刷新时闪全屏 loading。
- 直播/直播播放页搜索使用防抖，避免每个字符触发过滤重算。
- 分类切换、搜索过滤等本地操作不应重新触发整页 loading。
- 大量 IPTV 频道解析不得阻塞主线程。
- 搜索和详情缓存必须有容量边界。
- 图片加载统一 `PosterImage`；占位见 `PosterFallback`。
- 并发请求要有限流，避免耗电和源站压力过大。

## 修改流程

1. 阅读当前真实代码和相关文档。
2. 明确根因或需求边界。
3. 选择最小、最清晰、可维护的实现。
4. 修改前确认不会覆盖用户未提交改动。
5. 使用 `apply_patch` 做手工代码编辑。
6. 同步删除被替代的旧代码。
7. 执行静态验收。
8. 在本地维护 `docs/开发记录.md`（该文件已 gitignore，不提交仓库）。
9. 用中文总结改动、验证结果和人工验收点。

## 验收标准

常规代码改动后必须执行：

```bash
dart format lib test
flutter analyze lib
dart test
git diff --check
```

涉及 Android Gradle、依赖、播放器、sqlite3 native assets、签名或发布配置时，额外执行：

```bash
flutter build apk --debug
```

涉及 GitHub Actions 时，至少检查：

- YAML 结构清晰。
- 工作流为手动触发。
- 构建前先执行静态检查。
- 多平台构建可并行。
- Android 签名只来自 Secrets 或环境变量。
- 不把签名文件、密码或临时产物写入仓库。

无法执行某项验收时，必须在最终回复和开发记录中明确说明原因。

## 禁止事项

- 禁止根据 README 或项目名称猜实现。
- 禁止未读代码直接改。
- 禁止大范围重构来解决局部问题。
- 禁止添加多套并行实现。
- 禁止为了「保险」堆叠无意义兜底逻辑。
- 禁止提交密钥、签名文件、Token、代理配置或本地绝对路径。
- 禁止删除用户未明确要求删除的改动。
- 禁止把版权内容、内置源、默认源地址或灰色资源写入项目。

## 开发记录要求

每轮开发在本地更新 `docs/开发记录.md`（不提交 git），至少包含：

- 目标
- 修改文件
- 完成内容
- 静态验收结果
- 待人工验收点

记录必须使用中文，保持简洁准确，不写无依据推测。

## 规范目标

核心目标：

- 最少代码
- 最小复杂度
- 单一最佳方案
- 长期可维护
- 真实场景优先
- UI 现代统一
- 跨平台可靠
- 性能和省电可控

任何新增功能都必须让系统更清晰，而不是更臃肿。

## 最高原则

| 原则 | 要求 |
| --- | --- |
| 先理解再改动 | 修改前必须阅读真实代码和调用链 |
| 一个问题一个方案 | 不保留多套并行实现 |
| 最小可行实现 | 不为假设需求提前扩展 |
| 删除旧逻辑 | 新方案替代旧方案时必须清理旧代码 |
| 数据流单向清晰 | UI 不直接请求网络，不直接解析上游字段 |
| 依赖克制 | 只有明确降低复杂度时才新增依赖 |
| 测试跟随风险 | 核心解析、数据库、搜索并发、播放器状态必须有测试 |
