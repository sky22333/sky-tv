import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../core/models/media_models.dart';
import '../../core/models/iptv_models.dart';
import '../../core/models/video_source.dart';

class AppDatabase {
  AppDatabase._(this._db);

  final Database _db;

  static Future<AppDatabase> open() async {
    final dir = await getApplicationSupportDirectory();
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final db = sqlite3.open(p.join(dir.path, 'skytv.sqlite'));
    final appDb = AppDatabase._(db);
    appDb._migrate();
    return appDb;
  }

  void _migrate() {
    _db.execute('''
      CREATE TABLE IF NOT EXISTS source_subscriptions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_checked_at INTEGER,
        last_updated_at INTEGER
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS video_sources (
        source_id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        api_url TEXT NOT NULL,
        disabled INTEGER NOT NULL DEFAULT 0,
        sort_order INTEGER NOT NULL DEFAULT 0,
        avg_latency_ms INTEGER NOT NULL DEFAULT 0,
        last_success_at INTEGER,
        last_failure_at INTEGER
      );
    ''');
    _addColumnIfMissing(
      'video_sources',
      'avg_latency_ms',
      'INTEGER NOT NULL DEFAULT 0',
    );
    _addColumnIfMissing('video_sources', 'last_success_at', 'INTEGER');
    _addColumnIfMissing('video_sources', 'last_failure_at', 'INTEGER');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS source_categories (
        source_id TEXT NOT NULL,
        category_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        name TEXT NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (source_id, category_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS favorites (
        source_id TEXT NOT NULL,
        media_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        title TEXT NOT NULL,
        poster TEXT,
        created_at INTEGER NOT NULL,
        PRIMARY KEY (source_id, media_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS watch_records (
        source_id TEXT NOT NULL,
        media_id TEXT NOT NULL,
        source_name TEXT NOT NULL,
        title TEXT NOT NULL,
        poster TEXT,
        line_index INTEGER NOT NULL,
        episode_index INTEGER NOT NULL,
        position_ms INTEGER NOT NULL,
        duration_ms INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (source_id, media_id)
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS recent_searches (
        keyword TEXT PRIMARY KEY,
        updated_at INTEGER NOT NULL
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_subscriptions (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        content_hash TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        last_checked_at INTEGER,
        last_updated_at INTEGER
      );
    ''');
    _db.execute('''
      CREATE TABLE IF NOT EXISTS iptv_channels (
        id TEXT PRIMARY KEY,
        subscription_id TEXT NOT NULL,
        name TEXT NOT NULL,
        url TEXT NOT NULL,
        group_name TEXT,
        logo TEXT,
        tvg_id TEXT,
        tvg_name TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      );
    ''');
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_iptv_channels_group ON iptv_channels(group_name, sort_order)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_iptv_channels_subscription ON iptv_channels(subscription_id)',
    );
    _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_iptv_channels_name ON iptv_channels(name)',
    );
  }

  List<VideoSource> loadSources() {
    final rows = _db.select('''
      SELECT * FROM video_sources
      ORDER BY
        disabled ASC,
        CASE WHEN avg_latency_ms > 0 THEN 0 ELSE 1 END ASC,
        avg_latency_ms ASC,
        sort_order ASC
    ''');
    return rows.map((row) {
      return VideoSource(
        sourceId: row['source_id'] as String,
        name: row['name'] as String,
        apiUrl: row['api_url'] as String,
        disabled: (row['disabled'] as int) == 1,
        sortOrder: row['sort_order'] as int,
        avgLatencyMs: row['avg_latency_ms'] as int,
        lastSuccessAt: _date(row['last_success_at']),
        lastFailureAt: _date(row['last_failure_at']),
      );
    }).toList();
  }

  SourceSubscription? loadSubscription(String id) {
    final rows = _db.select(
      'SELECT * FROM source_subscriptions WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _subscription(rows.first);
  }

  List<SourceSubscription> loadDueSubscriptions() {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 6))
        .millisecondsSinceEpoch;
    final rows = _db.select(
      '''
      SELECT * FROM source_subscriptions
      WHERE enabled = 1 AND (last_checked_at IS NULL OR last_checked_at < ?)
      ORDER BY last_checked_at ASC
      LIMIT 5
    ''',
      [cutoff],
    );
    return rows.map(_subscription).toList();
  }

  void upsertSubscription(SourceSubscription subscription) {
    _db.execute(
      '''
      INSERT INTO source_subscriptions (
        id, name, url, content_hash, enabled, last_checked_at, last_updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        url = excluded.url,
        content_hash = excluded.content_hash,
        enabled = excluded.enabled,
        last_checked_at = excluded.last_checked_at,
        last_updated_at = excluded.last_updated_at
    ''',
      [
        subscription.id,
        subscription.name,
        subscription.url,
        subscription.contentHash,
        subscription.enabled ? 1 : 0,
        _millis(subscription.lastCheckedAt),
        _millis(subscription.lastUpdatedAt),
      ],
    );
  }

  void upsertSources(List<VideoSource> sources) {
    _db.execute('BEGIN');
    try {
      final statement = _db.prepare('''
        INSERT INTO video_sources (
          source_id, name, api_url, disabled, sort_order,
          avg_latency_ms, last_success_at, last_failure_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(source_id) DO UPDATE SET
          name = excluded.name,
          api_url = excluded.api_url
      ''');
      try {
        for (final source in sources) {
          statement.execute([
            source.sourceId,
            source.name,
            source.apiUrl,
            source.disabled ? 1 : 0,
            source.sortOrder,
            source.avgLatencyMs,
            _millis(source.lastSuccessAt),
            _millis(source.lastFailureAt),
          ]);
        }
      } finally {
        statement.close();
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void updateSourceDisabled(String sourceId, bool disabled) {
    _db.execute('UPDATE video_sources SET disabled = ? WHERE source_id = ?', [
      disabled ? 1 : 0,
      sourceId,
    ]);
  }

  void updateSourceLatency(String sourceId, int? latencyMs) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (latencyMs == null) {
      _db.execute(
        '''
        UPDATE video_sources SET
          avg_latency_ms = 0,
          last_failure_at = ?
        WHERE source_id = ?
      ''',
        [now, sourceId],
      );
      return;
    }
    _db.execute(
      '''
      UPDATE video_sources SET
        avg_latency_ms = ?,
        last_success_at = ?,
        last_failure_at = NULL
      WHERE source_id = ?
    ''',
      [latencyMs, now, sourceId],
    );
  }

  void deleteSource(String sourceId) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM source_categories WHERE source_id = ?', [
        sourceId,
      ]);
      _db.execute('DELETE FROM video_sources WHERE source_id = ?', [sourceId]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void saveCategories(String sourceId, List<SourceCategory> categories) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM source_categories WHERE source_id = ?', [
        sourceId,
      ]);
      final statement = _db.prepare('''
        INSERT INTO source_categories (source_id, category_id, source_name, name, updated_at)
        VALUES (?, ?, ?, ?, ?)
      ''');
      try {
        for (final category in categories) {
          statement.execute([
            category.sourceId,
            category.id,
            category.sourceName,
            category.name,
            now,
          ]);
        }
      } finally {
        statement.close();
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<SourceCategory> loadFreshCategories(String sourceId) {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch;
    final rows = _db.select(
      'SELECT * FROM source_categories WHERE source_id = ? AND updated_at >= ? ORDER BY name ASC',
      [sourceId, cutoff],
    );
    return rows.map(_category).toList();
  }

  List<WatchRecord> loadWatchRecords() {
    final rows = _db.select(
      'SELECT * FROM watch_records ORDER BY updated_at DESC LIMIT 100',
    );
    return rows.map(_watchRecord).toList();
  }

  WatchRecord? loadWatchRecord(String sourceId, String mediaId) {
    final rows = _db.select(
      'SELECT * FROM watch_records WHERE source_id = ? AND media_id = ? LIMIT 1',
      [sourceId, mediaId],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _watchRecord(rows.first);
  }

  void saveWatchRecord(WatchRecord record) {
    _db.execute(
      '''
      INSERT INTO watch_records (
        source_id, media_id, source_name, title, poster, line_index, episode_index,
        position_ms, duration_ms, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(source_id, media_id) DO UPDATE SET
        source_name = excluded.source_name,
        title = excluded.title,
        poster = excluded.poster,
        line_index = excluded.line_index,
        episode_index = excluded.episode_index,
        position_ms = excluded.position_ms,
        duration_ms = excluded.duration_ms,
        updated_at = excluded.updated_at
    ''',
      [
        record.sourceId,
        record.mediaId,
        record.sourceName,
        record.title,
        record.poster,
        record.lineIndex,
        record.episodeIndex,
        record.positionMs,
        record.durationMs,
        record.updatedAt.millisecondsSinceEpoch,
      ],
    );
  }

  List<MediaItem> loadFavorites() {
    final rows = _db.select('SELECT * FROM favorites ORDER BY created_at DESC');
    return rows.map(_favorite).toList();
  }

  bool isFavorite(String sourceId, String mediaId) {
    final rows = _db.select(
      'SELECT 1 FROM favorites WHERE source_id = ? AND media_id = ? LIMIT 1',
      [sourceId, mediaId],
    );
    return rows.isNotEmpty;
  }

  void toggleFavorite(MediaItem item) {
    if (isFavorite(item.sourceId, item.id)) {
      _db.execute(
        'DELETE FROM favorites WHERE source_id = ? AND media_id = ?',
        [item.sourceId, item.id],
      );
      return;
    }
    _db.execute(
      '''
      INSERT INTO favorites (source_id, media_id, source_name, title, poster, created_at)
      VALUES (?, ?, ?, ?, ?, ?)
    ''',
      [
        item.sourceId,
        item.id,
        item.sourceName,
        item.title,
        item.poster,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  }

  List<String> loadRecentSearches() {
    final rows = _db.select(
      'SELECT keyword FROM recent_searches ORDER BY updated_at DESC LIMIT 20',
    );
    return rows.map((row) => row['keyword'] as String).toList();
  }

  void saveRecentSearch(String keyword) {
    final value = keyword.trim();
    if (value.isEmpty) {
      return;
    }
    _db.execute(
      '''
      INSERT INTO recent_searches (keyword, updated_at) VALUES (?, ?)
      ON CONFLICT(keyword) DO UPDATE SET updated_at = excluded.updated_at
    ''',
      [value, DateTime.now().millisecondsSinceEpoch],
    );
  }

  IptvSubscription? loadIptvSubscription(String id) {
    final rows = _db.select(
      'SELECT * FROM iptv_subscriptions WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _iptvSubscription(rows.first);
  }

  List<IptvSubscription> loadIptvSubscriptions() {
    final rows = _db.select(
      'SELECT * FROM iptv_subscriptions ORDER BY last_updated_at DESC, name ASC',
    );
    return rows.map(_iptvSubscription).toList();
  }

  List<IptvSubscription> loadDueIptvSubscriptions() {
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 6))
        .millisecondsSinceEpoch;
    final rows = _db.select(
      '''
      SELECT * FROM iptv_subscriptions
      WHERE enabled = 1 AND (last_checked_at IS NULL OR last_checked_at < ?)
      ORDER BY last_checked_at ASC
      LIMIT 3
    ''',
      [cutoff],
    );
    return rows.map(_iptvSubscription).toList();
  }

  List<IptvChannel> loadIptvChannels({String? group, String? keyword}) {
    final where = <String>[];
    final args = <Object?>[];
    if (group != null && group.isNotEmpty) {
      where.add('group_name = ?');
      args.add(group);
    }
    if (keyword != null && keyword.trim().isNotEmpty) {
      where.add('name LIKE ?');
      args.add('%${keyword.trim()}%');
    }
    final sql = StringBuffer('SELECT * FROM iptv_channels');
    if (where.isNotEmpty) {
      sql.write(' WHERE ${where.join(' AND ')}');
    }
    sql.write(' ORDER BY group_name ASC, sort_order ASC, name ASC LIMIT 2000');
    return _db.select(sql.toString(), args).map(_iptvChannel).toList();
  }

  IptvChannel? loadIptvChannel(String id) {
    final rows = _db.select(
      'SELECT * FROM iptv_channels WHERE id = ? LIMIT 1',
      [id],
    );
    if (rows.isEmpty) {
      return null;
    }
    return _iptvChannel(rows.first);
  }

  List<String> loadIptvGroups() {
    final rows = _db.select('''
      SELECT group_name, MIN(sort_order) AS first_order
      FROM iptv_channels
      GROUP BY group_name
      ORDER BY first_order ASC, group_name ASC
    ''');
    return rows
        .map((row) => row['group_name'] as String?)
        .whereType<String>()
        .toList();
  }

  void upsertIptvSubscription(
    IptvSubscription subscription,
    List<IptvChannel> channels,
  ) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        '''
        INSERT INTO iptv_subscriptions (
          id, name, url, content_hash, enabled, last_checked_at, last_updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
          name = excluded.name,
          url = excluded.url,
          content_hash = excluded.content_hash,
          enabled = excluded.enabled,
          last_checked_at = excluded.last_checked_at,
          last_updated_at = excluded.last_updated_at
      ''',
        [
          subscription.id,
          subscription.name,
          subscription.url,
          subscription.contentHash,
          subscription.enabled ? 1 : 0,
          _millis(subscription.lastCheckedAt),
          _millis(subscription.lastUpdatedAt),
        ],
      );
      if (channels.isNotEmpty) {
        _db.execute('DELETE FROM iptv_channels WHERE subscription_id = ?', [
          subscription.id,
        ]);
        final statement = _db.prepare('''
          INSERT INTO iptv_channels (
            id, subscription_id, name, url, group_name, logo, tvg_id, tvg_name, sort_order
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''');
        try {
          for (final channel in channels) {
            statement.execute([
              channel.id,
              channel.subscriptionId,
              channel.name,
              channel.url,
              channel.group,
              channel.logo,
              channel.tvgId,
              channel.tvgName,
              channel.sortOrder,
            ]);
          }
        } finally {
          statement.close();
        }
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void deleteIptvSubscription(String id) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM iptv_channels WHERE subscription_id = ?', [id]);
      _db.execute('DELETE FROM iptv_subscriptions WHERE id = ?', [id]);
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void clearCache() {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM source_categories');
      _db.execute('DELETE FROM iptv_channels');
      _db.execute(
        "UPDATE source_subscriptions SET content_hash = '', last_checked_at = NULL",
      );
      _db.execute(
        "UPDATE iptv_subscriptions SET content_hash = '', last_checked_at = NULL",
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  SourceSubscription _subscription(Map<String, Object?> row) {
    return SourceSubscription(
      id: row['id'] as String,
      name: row['name'] as String,
      url: row['url'] as String,
      contentHash: row['content_hash'] as String,
      enabled: (row['enabled'] as int) == 1,
      lastCheckedAt: _date(row['last_checked_at']),
      lastUpdatedAt: _date(row['last_updated_at']),
    );
  }

  IptvSubscription _iptvSubscription(Map<String, Object?> row) {
    return IptvSubscription(
      id: row['id'] as String,
      name: row['name'] as String,
      url: row['url'] as String,
      contentHash: row['content_hash'] as String,
      enabled: (row['enabled'] as int) == 1,
      lastCheckedAt: _date(row['last_checked_at']),
      lastUpdatedAt: _date(row['last_updated_at']),
    );
  }

  IptvChannel _iptvChannel(Map<String, Object?> row) {
    return IptvChannel(
      id: row['id'] as String,
      subscriptionId: row['subscription_id'] as String,
      name: row['name'] as String,
      url: row['url'] as String,
      group: row['group_name'] as String?,
      logo: row['logo'] as String?,
      tvgId: row['tvg_id'] as String?,
      tvgName: row['tvg_name'] as String?,
      sortOrder: row['sort_order'] as int,
    );
  }

  SourceCategory _category(Map<String, Object?> row) {
    return SourceCategory(
      id: row['category_id'] as String,
      sourceId: row['source_id'] as String,
      sourceName: row['source_name'] as String,
      name: row['name'] as String,
    );
  }

  MediaItem _favorite(Map<String, Object?> row) {
    return MediaItem(
      id: row['media_id'] as String,
      sourceId: row['source_id'] as String,
      sourceName: row['source_name'] as String,
      title: row['title'] as String,
      poster: row['poster'] as String?,
    );
  }

  WatchRecord _watchRecord(Map<String, Object?> row) {
    return WatchRecord(
      sourceId: row['source_id'] as String,
      mediaId: row['media_id'] as String,
      sourceName: row['source_name'] as String,
      title: row['title'] as String,
      poster: row['poster'] as String?,
      lineIndex: row['line_index'] as int,
      episodeIndex: row['episode_index'] as int,
      positionMs: row['position_ms'] as int,
      durationMs: row['duration_ms'] as int,
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int),
    );
  }

  DateTime? _date(Object? value) {
    if (value is! int) {
      return null;
    }
    return DateTime.fromMillisecondsSinceEpoch(value);
  }

  int? _millis(DateTime? value) => value?.millisecondsSinceEpoch;

  void _addColumnIfMissing(String table, String column, String definition) {
    final rows = _db.select('PRAGMA table_info($table)');
    final exists = rows.any((row) => row['name'] == column);
    if (!exists) {
      _db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
    }
  }

  void close() => _db.close();
}
