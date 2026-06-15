import '../models/media_models.dart';

List<PlayLine> parsePlayLines(String? playFrom, String? playUrl) {
  if (playUrl == null || playUrl.trim().isEmpty) {
    return const [];
  }

  final names = (playFrom ?? '')
      .split(r'$$$')
      .map((name) => name.trim())
      .where((name) => name.isNotEmpty)
      .toList();
  final rawLines = playUrl.split(r'$$$');
  final lines = <PlayLine>[];

  for (var i = 0; i < rawLines.length; i++) {
    final episodes = rawLines[i]
        .split('#')
        .map(_parseEpisode)
        .whereType<Episode>()
        .toList();
    if (episodes.isEmpty) {
      continue;
    }
    lines.add(
      PlayLine(
        name: i < names.length ? names[i] : '线路 ${i + 1}',
        episodes: episodes,
      ),
    );
  }
  return lines;
}

Episode? _parseEpisode(String raw) {
  final value = raw.trim();
  if (value.isEmpty) {
    return null;
  }
  final split = value.indexOf(r'$');
  if (split <= 0 || split == value.length - 1) {
    final url = value.trim();
    return _isPlayableUrl(url) ? Episode(title: '播放', url: url) : null;
  }
  final title = value.substring(0, split).trim();
  final url = value.substring(split + 1).trim();
  if (!_isPlayableUrl(url)) {
    return null;
  }
  return Episode(title: title.isEmpty ? '播放' : title, url: url);
}

bool _isPlayableUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}
