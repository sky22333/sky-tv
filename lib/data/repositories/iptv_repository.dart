import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:http/http.dart' as http;

import '../../core/models/iptv_models.dart';
import '../../core/parser/iptv_parser.dart';
import '../../core/source/source_id.dart';
import '../storage/app_database.dart';

class IptvRepository {
  IptvRepository(this._db, {Map<String, String> headers = const {}})
    : _headers = Map.unmodifiable(headers);

  final AppDatabase _db;
  final Map<String, String> _headers;

  IptvLibrary library({String? group, String? keyword}) {
    return IptvLibrary(
      subscriptions: _db.loadIptvSubscriptions(),
      channels: _db.loadIptvChannels(group: group, keyword: keyword),
      groups: _db.loadIptvGroups(),
    );
  }

  IptvChannel? channel(String id) => _db.loadIptvChannel(id);

  Future<IptvImportResult> importSubscriptionUrl(
    String name,
    String url,
  ) async {
    final normalizedUrl = url.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('IPTV 订阅地址只支持 http/https');
    }
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw Exception('IPTV 订阅拉取失败：HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    return importPlaylistText(
      name.trim().isEmpty ? uri.host : name.trim(),
      normalizedUrl,
      body,
    );
  }

  Future<IptvImportResult> importPlaylistText(
    String name,
    String url,
    String body,
  ) async {
    final id = buildHash(url).substring(0, 16);
    final hash = buildHash(body);
    final old = _db.loadIptvSubscription(id);
    final now = DateTime.now();
    if (old != null && old.contentHash == hash) {
      _db.upsertIptvSubscription(
        IptvSubscription(
          id: id,
          name: old.name,
          url: url,
          contentHash: hash,
          enabled: old.enabled,
          lastCheckedAt: now,
          lastUpdatedAt: old.lastUpdatedAt,
        ),
        const [],
      );
      return const IptvImportResult(channels: 0, errors: []);
    }

    final channels = await Isolate.run(() => parseIptvChannels(body, id));
    _db.upsertIptvSubscription(
      IptvSubscription(
        id: id,
        name: name,
        url: url,
        contentHash: hash,
        enabled: true,
        lastCheckedAt: now,
        lastUpdatedAt: now,
      ),
      channels,
    );
    return IptvImportResult(channels: channels.length, errors: const []);
  }

  Future<IptvImportResult> importJson(String input) async {
    final decoded = jsonDecode(input);
    final list = switch (decoded) {
      final List<Object?> value => value,
      final Map<String, Object?> value when value['iptv'] is List<Object?> =>
        value['iptv'] as List<Object?>,
      final Map<String, Object?> value
          when value['iptv_sources'] is List<Object?> =>
        value['iptv_sources'] as List<Object?>,
      _ => throw const FormatException('IPTV JSON 必须是数组或包含 iptv 数组的对象'),
    };
    var imported = 0;
    final errors = <String>[];
    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      try {
        if (item is! Map<String, Object?>) {
          throw const FormatException('订阅配置必须是对象');
        }
        final url = (item['url'] ?? item['api_url']) as String?;
        if (url == null || url.trim().isEmpty) {
          throw const FormatException('url 不能为空');
        }
        final name = ((item['name'] as String?) ?? '').trim();
        final result = await importSubscriptionUrl(name, url);
        imported += result.channels;
      } catch (error) {
        errors.add('第 ${i + 1} 项：$error');
      }
    }
    return IptvImportResult(channels: imported, errors: errors);
  }

  Future<void> refreshDueSubscriptions() async {
    final subscriptions = _db.loadDueIptvSubscriptions();
    for (final subscription in subscriptions) {
      await importSubscriptionUrl(subscription.name, subscription.url);
    }
  }

  void deleteSubscription(String id) {
    _db.deleteIptvSubscription(id);
  }
}
