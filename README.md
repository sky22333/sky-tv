## sky-tv

sky-tv 是一个现代化跨平台视频播放器空壳应用，支持导入用户自己的影视源和 IPTV 直播源，用于搜索、分类、播放、收藏和继续观看。

[界面预览图](https://github.com/sky22333/sky-tv/blob/main/docs/img/README.md)

### 声明

sky-tv 只是个空壳播放器：

- 不内置任何影视、直播、频道、节目单或解析服务。
- 不提供任何视频内容、下载内容或版权资源。

## 主要功能

- 影视源订阅导入，支持 MacCMS V10 常见接口。
- IPTV 订阅导入，支持 M3U、M3U8、TXT 和 JSON 订阅。
- 视频搜索、分类浏览、详情页、选集播放。
- 直播频道分组、搜索、播放和换台。
- 收藏、观看历史、继续观看。
- 自定义 User-Agent 请求头。
- 浅色、深色和跟随系统主题。
- Android、iOS、Windows、macOS、Linux 多平台构建。

## 订阅格式

影视源 JSON 示例：

```json
[
  {
    "name": "示例影视源",
    "api_url": "https://example.com/api.php/provide/vod"
  }
]
```

IPTV JSON 示例：

```json
{
  "iptv": [
    {
      "name": "示例直播源",
      "url": "https://example.com/live.m3u"
    }
  ]
}
```

IPTV 也可以直接导入公开 M3U、M3U8 或 TXT 订阅地址。

## 本地运行

```bash
flutter pub get
flutter run
```

## Star 趋势
[![Star 趋势](https://starchart.cc/sky22333/sky-tv.svg?variant=adaptive)](https://starchart.cc/sky22333/sky-tv)
