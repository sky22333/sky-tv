import '../models/media_models.dart';
import '../models/video_source.dart';
import 'play_url_parser.dart';

class MacCmsParser {
  List<SourceCategory> parseCategories(
    Map<String, Object?> json,
    VideoSource source,
  ) {
    final raw = json['class'];
    if (raw is! List) {
      return const [];
    }
    return raw
        .whereType<Map>()
        .map((item) {
          final id = _string(item['type_id'] ?? item['id']);
          final name = _string(item['type_name'] ?? item['name']);
          if (id.isEmpty || name.isEmpty) {
            return null;
          }
          return SourceCategory(
            id: id,
            sourceId: source.sourceId,
            sourceName: source.name,
            name: name,
          );
        })
        .whereType<SourceCategory>()
        .toList();
  }

  List<MediaItem> parseMediaList(
    Map<String, Object?> json,
    VideoSource source,
  ) {
    return _list(json).map((item) => _mediaItem(item, source)).toList();
  }

  MediaDetail? parseDetail(Map<String, Object?> json, VideoSource source) {
    final list = _list(json);
    if (list.isEmpty) {
      return null;
    }
    final item = list.first;
    final media = _mediaItem(item, source);
    return MediaDetail(
      id: media.id,
      sourceId: media.sourceId,
      sourceName: media.sourceName,
      title: media.title,
      poster: media.poster,
      year: media.year,
      category: media.category,
      description: media.description,
      playLines: parsePlayLines(
        _optionalString(item['vod_play_from']),
        _optionalString(item['vod_play_url']),
      ),
    );
  }

  List<Map> _list(Map<String, Object?> json) {
    final raw = json['list'];
    if (raw is! List) {
      return const [];
    }
    return raw.whereType<Map>().toList();
  }

  MediaItem _mediaItem(Map item, VideoSource source) {
    final id = _string(item['vod_id'] ?? item['id']);
    final title = _string(item['vod_name'] ?? item['name']);
    if (id.isEmpty || title.isEmpty) {
      throw const FormatException('MacCMS 响应缺少 vod_id 或 vod_name');
    }
    return MediaItem(
      id: id,
      sourceId: source.sourceId,
      sourceName: source.name,
      title: title,
      poster: _optionalString(item['vod_pic']),
      year: _optionalString(item['vod_year']),
      category: _optionalString(item['type_name']),
      description: _cleanHtml(_optionalString(item['vod_content'])),
    );
  }

  String _string(Object? value) => value?.toString().trim() ?? '';

  String? _optionalString(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  String? _cleanHtml(String? value) {
    if (value == null) {
      return null;
    }
    return value.replaceAll(RegExp('<[^>]*>'), '').trim();
  }
}
