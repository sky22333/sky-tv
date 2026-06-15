import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/video_source.dart';
import '../models/media_models.dart';
import '../parser/maccms_parser.dart';

class MacCmsApi {
  MacCmsApi({
    http.Client? client,
    MacCmsParser? parser,
    Map<String, String> headers = const {},
  }) : _headers = Map.unmodifiable(headers),
       _client = client ?? http.Client(),
       _parser = parser ?? MacCmsParser();

  final Map<String, String> _headers;
  final http.Client _client;
  final MacCmsParser _parser;

  Future<Map<String, Object?>> _get(
    VideoSource source,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse(source.apiUrl).replace(queryParameters: query);
    final response = await _client
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('${source.name} 请求失败：HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, Object?>) {
      throw Exception('${source.name} 响应不是 JSON 对象');
    }
    return decoded;
  }

  Future<List<MediaItem>> search(
    VideoSource source,
    String keyword,
    int page,
  ) async {
    final json = await _get(source, {
      'ac': 'videolist',
      'wd': keyword,
      'pg': '$page',
    });
    return _parser.parseMediaList(json, source);
  }

  Future<List<MediaItem>> categoryVideos(
    VideoSource source,
    String categoryId,
    int page,
  ) async {
    final json = await _get(source, {
      'ac': 'videolist',
      't': categoryId,
      'pg': '$page',
    });
    return _parser.parseMediaList(json, source);
  }

  Future<List<MediaItem>> recentVideos(
    VideoSource source, {
    required int hours,
    int page = 1,
  }) async {
    final json = await _get(source, {
      'ac': 'videolist',
      'h': '$hours',
      'pg': '$page',
    });
    return _parser.parseMediaList(json, source);
  }

  Future<List<SourceCategory>> categories(VideoSource source) async {
    final json = await _get(source, {'ac': 'list'});
    return _parser.parseCategories(json, source);
  }

  Future<MediaDetail?> detail(VideoSource source, String mediaId) async {
    final json = await _get(source, {'ac': 'videolist', 'ids': mediaId});
    final detail = _parser.parseDetail(json, source);
    if (detail != null) {
      return detail;
    }
    final fallback = await _get(source, {'ac': 'detail', 'ids': mediaId});
    return _parser.parseDetail(fallback, source);
  }

  void close() => _client.close();
}
