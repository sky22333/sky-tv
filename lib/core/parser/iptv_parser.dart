import '../models/iptv_models.dart';
import '../source/source_id.dart';

List<IptvChannel> parseIptvChannels(String input, String subscriptionId) {
  final lines = input
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n');
  final channels = <String, IptvChannel>{};
  var sortOrder = 0;
  var currentGroup = '未分组';
  _ExtInf? pending;

  for (final rawLine in lines) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('#EXTINF')) {
      pending = _parseExtInf(line);
      if (pending.group != null && pending.group!.isNotEmpty) {
        currentGroup = pending.group!;
      }
      continue;
    }
    if (line.startsWith('#')) {
      continue;
    }

    final simple = pending == null
        ? _parseSimpleLine(line, currentGroup)
        : null;
    if (simple?.genre == true) {
      currentGroup = simple!.group;
      continue;
    }
    final name = pending?.name ?? simple?.name;
    final url = pending == null ? simple?.url : line;
    final group = pending?.group ?? simple?.group ?? currentGroup;
    final logo = pending?.logo;
    final tvgId = pending?.tvgId;
    final tvgName = pending?.tvgName;
    pending = null;

    if (name == null || url == null || !_isPlayableUrl(url)) {
      continue;
    }
    final id = buildHash('$subscriptionId|$name|$url').substring(0, 24);
    channels[id] = IptvChannel(
      id: id,
      subscriptionId: subscriptionId,
      name: name,
      url: url,
      group: group.isEmpty ? '未分组' : group,
      logo: logo,
      tvgId: tvgId,
      tvgName: tvgName,
      sortOrder: sortOrder++,
    );
  }
  return channels.values.toList();
}

_ExtInf _parseExtInf(String line) {
  final comma = line.lastIndexOf(',');
  final title = comma >= 0 ? line.substring(comma + 1).trim() : '';
  final attributes = comma >= 0 ? line.substring(0, comma) : line;
  final values = <String, String>{};
  for (final match in RegExp(r'([\w-]+)="([^"]*)"').allMatches(attributes)) {
    values[match.group(1)!] = match.group(2)!.trim();
  }
  final name = values['tvg-name']?.isNotEmpty == true
      ? values['tvg-name']!
      : title;
  return _ExtInf(
    name: name,
    group: values['group-title'],
    logo: values['tvg-logo'],
    tvgId: values['tvg-id'],
    tvgName: values['tvg-name'],
  );
}

_SimpleChannel? _parseSimpleLine(String line, String currentGroup) {
  final comma = line.indexOf(',');
  if (comma <= 0 || comma == line.length - 1) {
    return null;
  }
  final name = line.substring(0, comma).trim();
  final url = line.substring(comma + 1).trim();
  if (url == '#genre#') {
    return _SimpleChannel(name: '', url: '', group: name, genre: true);
  }
  return _SimpleChannel(name: name, url: url, group: currentGroup);
}

bool _isPlayableUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null && (uri.scheme == 'http' || uri.scheme == 'https');
}

class _ExtInf {
  const _ExtInf({
    required this.name,
    this.group,
    this.logo,
    this.tvgId,
    this.tvgName,
  });

  final String name;
  final String? group;
  final String? logo;
  final String? tvgId;
  final String? tvgName;
}

class _SimpleChannel {
  const _SimpleChannel({
    required this.name,
    required this.url,
    required this.group,
    this.genre = false,
  });

  final String name;
  final String url;
  final String group;
  final bool genre;
}
