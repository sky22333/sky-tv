import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/models/media_models.dart';
import '../../core/models/video_source.dart';
import '../../core/parser/source_importer.dart';
import '../../core/source/source_id.dart';
import '../storage/app_database.dart';

class SourceRepository {
  SourceRepository(this._db, {Map<String, String> headers = const {}})
    : _headers = Map.unmodifiable(headers);

  final AppDatabase _db;
  final Map<String, String> _headers;

  List<VideoSource> sources() => _db.loadSources();

  VideoSource? findById(String sourceId) {
    for (final source in sources()) {
      if (source.sourceId == sourceId) {
        return source;
      }
    }
    return null;
  }

  SourceImportResult importJson(String input) {
    final result = importSourcesFromJson(input);
    if (result.sources.isNotEmpty) {
      _db.upsertSources(result.sources);
    }
    return result;
  }

  Future<SourceImportResult> importSubscriptionUrl(
    String name,
    String url,
  ) async {
    final normalizedUrl = url.trim();
    final uri = Uri.tryParse(normalizedUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('订阅地址只支持 http/https');
    }

    final id = buildHash(normalizedUrl).substring(0, 16);
    final response = await http
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('订阅拉取失败：HTTP ${response.statusCode}');
    }
    final body = utf8.decode(response.bodyBytes);
    final hash = buildHash(body);
    final old = _db.loadSubscription(id);
    final now = DateTime.now();

    if (old != null && old.contentHash == hash) {
      _db.upsertSubscription(
        SourceSubscription(
          id: id,
          name: old.name,
          url: normalizedUrl,
          contentHash: hash,
          enabled: old.enabled,
          lastCheckedAt: now,
          lastUpdatedAt: old.lastUpdatedAt,
        ),
      );
      return const SourceImportResult(sources: [], errors: []);
    }

    final result = importJson(body);
    if (result.sources.isNotEmpty) {
      _db.upsertSources(result.sources);
    }
    _db.upsertSubscription(
      SourceSubscription(
        id: id,
        name: name.trim().isEmpty ? uri.host : name.trim(),
        url: normalizedUrl,
        contentHash: hash,
        enabled: true,
        lastCheckedAt: now,
        lastUpdatedAt: now,
      ),
    );
    return result;
  }

  Future<void> refreshDueSubscriptions() async {
    final subscriptions = _db.loadDueSubscriptions();
    for (final subscription in subscriptions) {
      await importSubscriptionUrl(subscription.name, subscription.url);
    }
  }

  Future<LatencyTestResult> testLatencies(List<VideoSource> sources) async {
    final active = sources.where((source) => !source.disabled).toList();
    final queue = List<VideoSource>.from(active);
    const maxConcurrent = 16;
    var running = 0;
    var completed = 0;
    var succeeded = 0;
    final done = Completer<void>();
    final client = http.Client();

    void pump() {
      while (running < maxConcurrent && queue.isNotEmpty) {
        final source = queue.removeAt(0);
        running++;
        unawaited(
          _testLatency(client, source)
              .then((latency) {
                _db.updateSourceLatency(source.sourceId, latency);
                if (latency != null) {
                  succeeded++;
                }
              })
              .whenComplete(() {
                running--;
                completed++;
                if (completed == active.length) {
                  done.complete();
                } else {
                  pump();
                }
              }),
        );
      }
    }

    if (active.isEmpty) {
      client.close();
      return const LatencyTestResult(total: 0, succeeded: 0);
    }
    try {
      pump();
      await done.future;
      return LatencyTestResult(total: active.length, succeeded: succeeded);
    } finally {
      client.close();
    }
  }

  void setDisabled(String sourceId, bool disabled) {
    _db.updateSourceDisabled(sourceId, disabled);
  }

  void delete(String sourceId) {
    _db.deleteSource(sourceId);
  }

  Future<int?> _testLatency(http.Client client, VideoSource source) async {
    final uri = Uri.parse(
      source.apiUrl,
    ).replace(queryParameters: const {'ac': 'list'});
    final watch = Stopwatch()..start();
    try {
      final response = await client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) {
        return null;
      }
      return watch.elapsedMilliseconds;
    } catch (_) {
      return null;
    }
  }
}

class LatencyTestResult {
  const LatencyTestResult({required this.total, required this.succeeded});

  final int total;
  final int succeeded;
}
