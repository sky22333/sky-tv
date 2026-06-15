import '../source/source_id.dart';

class VideoSource {
  const VideoSource({
    required this.sourceId,
    required this.name,
    required this.apiUrl,
    this.disabled = false,
    this.sortOrder = 0,
    this.avgLatencyMs = 0,
    this.lastSuccessAt,
    this.lastFailureAt,
  });

  factory VideoSource.create({
    required String name,
    required String apiUrl,
    bool disabled = false,
  }) {
    final normalizedName = normalizeSourceName(name);
    final normalizedApiUrl = normalizeApiUrl(apiUrl);
    return VideoSource(
      sourceId: buildSourceId(normalizedName, normalizedApiUrl),
      name: normalizedName,
      apiUrl: normalizedApiUrl,
      disabled: disabled,
    );
  }

  factory VideoSource.fromJson(Map<String, Object?> json) {
    final name = (json['name'] ?? json['source_name']) as String?;
    final apiUrl = (json['api_url'] ?? json['apiUrl']) as String?;
    if (name == null || name.trim().isEmpty) {
      throw const FormatException('视频源 name 不能为空');
    }
    if (apiUrl == null || apiUrl.trim().isEmpty) {
      throw const FormatException('视频源 api_url 不能为空');
    }
    return VideoSource.create(
      name: name,
      apiUrl: apiUrl,
      disabled: json['disabled'] == true,
    );
  }

  final String sourceId;
  final String name;
  final String apiUrl;
  final bool disabled;
  final int sortOrder;
  final int avgLatencyMs;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  VideoSource copyWith({
    String? sourceId,
    String? name,
    String? apiUrl,
    bool? disabled,
    int? sortOrder,
    int? avgLatencyMs,
    DateTime? lastSuccessAt,
    DateTime? lastFailureAt,
  }) {
    return VideoSource(
      sourceId: sourceId ?? this.sourceId,
      name: name ?? this.name,
      apiUrl: apiUrl ?? this.apiUrl,
      disabled: disabled ?? this.disabled,
      sortOrder: sortOrder ?? this.sortOrder,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
      lastFailureAt: lastFailureAt ?? this.lastFailureAt,
    );
  }
}
