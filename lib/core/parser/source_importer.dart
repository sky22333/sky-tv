import 'dart:convert';

import '../models/video_source.dart';

class SourceImportResult {
  const SourceImportResult({required this.sources, required this.errors});

  final List<VideoSource> sources;
  final List<String> errors;
}

SourceImportResult importSourcesFromJson(String input) {
  final decoded = jsonDecode(input);
  final list = switch (decoded) {
    final List<Object?> value => value,
    final Map<String, Object?> value when value['sources'] is List<Object?> =>
      value['sources'] as List<Object?>,
    _ => throw const FormatException('订阅源 JSON 必须是数组或包含 sources 数组的对象'),
  };

  final sourcesById = <String, VideoSource>{};
  final errors = <String>[];
  for (var i = 0; i < list.length; i++) {
    final item = list[i];
    try {
      if (item is! Map<String, Object?>) {
        throw const FormatException('源配置必须是对象');
      }
      final source = VideoSource.fromJson(item);
      sourcesById[source.sourceId] = source;
    } on FormatException catch (error) {
      errors.add('第 ${i + 1} 项：${error.message}');
    } catch (error) {
      errors.add('第 ${i + 1} 项：$error');
    }
  }
  return SourceImportResult(
    sources: sourcesById.values.toList(),
    errors: errors,
  );
}
