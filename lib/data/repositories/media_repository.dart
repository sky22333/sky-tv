import 'dart:async';

import '../../core/models/media_models.dart';
import '../../core/models/video_source.dart';
import '../../core/upstream/maccms_api.dart';
import '../storage/app_database.dart';

sealed class SearchEvent {
  const SearchEvent();
}

class SourceSearchStarted extends SearchEvent {
  const SourceSearchStarted(this.source);
  final VideoSource source;
}

class SourceSearchCompleted extends SearchEvent {
  const SourceSearchCompleted(this.source, this.items);
  final VideoSource source;
  final List<MediaItem> items;
}

class SourceSearchFailed extends SearchEvent {
  const SourceSearchFailed(this.source, this.message);
  final VideoSource source;
  final String message;
}

class SearchCompleted extends SearchEvent {
  const SearchCompleted();
}

class MediaRepository {
  MediaRepository({required this.db, required this.api});

  static const searchBatchSize = 12;
  static const categoryPreviewLimit = 6;
  static const categoryPreviewRowCount = 4;
  static const homeRecommendHours = 72;
  static const homeRecommendLimit = 8;
  static const _maxConcurrentSearches = 4;
  static const _maxConcurrentCategoryPreviews = 3;
  static const _maxSearchCacheEntries = 300;
  static const _maxDetailCacheEntries = 400;
  static const _maxCategoryPreviewCacheEntries = 200;
  static const _maxHomeRecommendCacheEntries = 20;

  final AppDatabase db;
  final MacCmsApi api;
  final _searchCache = <String, _CacheEntry<List<MediaItem>>>{};
  final _detailCache = <String, _CacheEntry<MediaDetail>>{};
  final _categoryPreviewCache = <String, _CacheEntry<List<MediaItem>>>{};
  final _homeRecommendCache = <String, _CacheEntry<List<MediaItem>>>{};

  List<WatchRecord> watchRecords() => db.loadWatchRecords();

  WatchRecord? watchRecord(String sourceId, String mediaId) =>
      db.loadWatchRecord(sourceId, mediaId);

  List<MediaItem> favorites() => db.loadFavorites();

  List<String> recentSearches() => db.loadRecentSearches();

  bool isFavorite(String sourceId, String mediaId) =>
      db.isFavorite(sourceId, mediaId);

  void toggleFavorite(MediaItem item) => db.toggleFavorite(item);

  int enabledSourceCount(List<VideoSource> sources) {
    return sources.where((source) => !source.disabled).length;
  }

  Stream<SearchEvent> search(
    String keyword,
    List<VideoSource> sources, {
    int offset = 0,
    int limit = searchBatchSize,
    bool saveRecent = true,
  }) async* {
    final value = keyword.trim();
    if (value.isEmpty) {
      return;
    }
    if (saveRecent) {
      db.saveRecentSearch(value);
    }
    final active = sources.where((source) => !source.disabled).toList()
      ..sort(_compareSources);
    final searchable = active.skip(offset).take(limit).toList();
    if (searchable.isEmpty) {
      yield const SearchCompleted();
      return;
    }
    final queue = List<VideoSource>.from(searchable);
    var running = 0;
    var closed = false;
    late final StreamController<SearchEvent> controller;
    controller = StreamController<SearchEvent>(
      onCancel: () {
        closed = true;
      },
    );

    void emit(SearchEvent event) {
      if (!closed && !controller.isClosed) {
        controller.add(event);
      }
    }

    Future<void> pump() async {
      if (closed) {
        return;
      }
      while (running < _maxConcurrentSearches && queue.isNotEmpty) {
        final source = queue.removeAt(0);
        running++;
        emit(SourceSearchStarted(source));
        unawaited(
          _searchOne(source, value)
              .then((items) {
                emit(SourceSearchCompleted(source, items));
              })
              .catchError((Object error) {
                emit(SourceSearchFailed(source, error.toString()));
              })
              .whenComplete(() {
                running--;
                if (!closed && queue.isEmpty && running == 0) {
                  emit(const SearchCompleted());
                  closed = true;
                  unawaited(controller.close());
                } else {
                  unawaited(pump());
                }
              }),
        );
      }
    }

    unawaited(pump());
    yield* controller.stream;
  }

  Future<List<MediaItem>> _searchOne(VideoSource source, String keyword) async {
    final key = '${source.sourceId}|$keyword|1';
    final cached = _searchCache[key];
    if (cached != null && !cached.expired) {
      return cached.value;
    }
    final items = await api.search(source, keyword, 1);
    _writeCache(
      _searchCache,
      key,
      _CacheEntry(items, const Duration(minutes: 10)),
      _maxSearchCacheEntries,
    );
    return items;
  }

  Future<List<SourceCategory>> categories(VideoSource source) async {
    final cached = db.loadFreshCategories(source.sourceId);
    if (cached.isNotEmpty) {
      return cached;
    }
    final categories = await api.categories(source);
    db.saveCategories(source.sourceId, categories);
    return categories;
  }

  Future<List<MediaItem>> categoryVideos(
    VideoSource source,
    String categoryId, {
    int page = 1,
  }) {
    return api.categoryVideos(source, categoryId, page);
  }

  Future<List<MediaItem>> categoryPreview(
    VideoSource source,
    String categoryId, {
    int page = 1,
  }) async {
    final key = '${source.sourceId}|$categoryId|$page';
    final cached = _categoryPreviewCache[key];
    if (cached != null && !cached.expired) {
      return cached.value;
    }
    final items = await api.categoryVideos(source, categoryId, page);
    final preview = items.take(categoryPreviewLimit).toList();
    _writeCache(
      _categoryPreviewCache,
      key,
      _CacheEntry(preview, const Duration(minutes: 10)),
      _maxCategoryPreviewCacheEntries,
    );
    return preview;
  }

  Future<List<CategoryPreviewRow>> loadCategoryPreviewRows(
    VideoSource source,
    List<SourceCategory> categories,
  ) async {
    final targets = categories.take(categoryPreviewRowCount).toList();
    final rows = <CategoryPreviewRow>[];
    for (
      var index = 0;
      index < targets.length;
      index += _maxConcurrentCategoryPreviews
    ) {
      final batch = targets
          .skip(index)
          .take(_maxConcurrentCategoryPreviews)
          .toList();
      final batchRows = await Future.wait(
        batch.map((category) async {
          try {
            final items = await categoryPreview(source, category.id);
            return CategoryPreviewRow(category: category, items: items);
          } catch (_) {
            return CategoryPreviewRow(category: category, items: const []);
          }
        }),
      );
      rows.addAll(batchRows);
    }
    return rows;
  }

  Future<List<MediaItem>> homeRecommendations(List<VideoSource> sources) async {
    final candidates = _recommendSourceCandidates(sources);
    if (candidates.isEmpty) {
      return const [];
    }
    final exclude = _personalMediaKeys();
    for (final source in candidates.take(3)) {
      try {
        final items = await _loadRecentRecommend(source);
        final filtered = items
            .where((item) => !exclude.contains(_mediaKey(item)))
            .take(homeRecommendLimit)
            .toList();
        if (filtered.isNotEmpty) {
          return filtered;
        }
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  List<VideoSource> _recommendSourceCandidates(List<VideoSource> sources) {
    final enabled = enabledSources(sources);
    if (enabled.isEmpty) {
      return const [];
    }
    final records = watchRecords();
    if (records.isEmpty) {
      return enabled;
    }
    final recent = findSource(enabled, records.first.sourceId);
    if (recent == null) {
      return enabled;
    }
    return [
      recent,
      ...enabled.where((source) => source.sourceId != recent.sourceId),
    ];
  }

  Set<String> _personalMediaKeys() {
    final keys = <String>{};
    for (final record in watchRecords()) {
      keys.add('${record.sourceId}|${record.mediaId}');
    }
    for (final item in favorites()) {
      keys.add('${item.sourceId}|${item.id}');
    }
    return keys;
  }

  Future<List<MediaItem>> _loadRecentRecommend(VideoSource source) async {
    final key = '${source.sourceId}|$homeRecommendHours';
    final cached = _homeRecommendCache[key];
    if (cached != null && !cached.expired) {
      return cached.value;
    }
    final items = await api.recentVideos(source, hours: homeRecommendHours);
    _writeCache(
      _homeRecommendCache,
      key,
      _CacheEntry(items, const Duration(minutes: 10)),
      _maxHomeRecommendCacheEntries,
    );
    return items;
  }

  String _mediaKey(MediaItem item) => '${item.sourceId}|${item.id}';

  VideoSource? findSource(List<VideoSource> sources, String sourceId) {
    for (final source in sources) {
      if (source.sourceId == sourceId) {
        return source;
      }
    }
    return null;
  }

  List<VideoSource> orderedSources(List<VideoSource> sources) {
    return List<VideoSource>.from(sources)..sort(_compareSources);
  }

  List<VideoSource> enabledSources(List<VideoSource> sources) {
    return orderedSources(sources).where((source) => !source.disabled).toList();
  }

  Future<MediaDetail?> detail(VideoSource source, String mediaId) async {
    final key = '${source.sourceId}|$mediaId';
    final cached = _detailCache[key];
    if (cached != null && !cached.expired) {
      return cached.value;
    }
    final detail = await api.detail(source, mediaId);
    if (detail != null) {
      _writeCache(
        _detailCache,
        key,
        _CacheEntry(detail, const Duration(minutes: 30)),
        _maxDetailCacheEntries,
      );
    }
    return detail;
  }

  void saveWatchRecord(WatchRecord record) => db.saveWatchRecord(record);

  int _compareSources(VideoSource a, VideoSource b) {
    final aMeasured = a.avgLatencyMs > 0;
    final bMeasured = b.avgLatencyMs > 0;
    if (aMeasured != bMeasured) {
      return aMeasured ? -1 : 1;
    }
    if (aMeasured && bMeasured && a.avgLatencyMs != b.avgLatencyMs) {
      return a.avgLatencyMs.compareTo(b.avgLatencyMs);
    }
    return a.sortOrder.compareTo(b.sortOrder);
  }

  void _writeCache<T>(
    Map<String, _CacheEntry<T>> cache,
    String key,
    _CacheEntry<T> entry,
    int maxEntries,
  ) {
    cache.removeWhere((_, value) => value.expired);
    cache.remove(key);
    cache[key] = entry;
    while (cache.length > maxEntries) {
      cache.remove(cache.keys.first);
    }
  }
}

class _CacheEntry<T> {
  _CacheEntry(this.value, Duration ttl) : expiresAt = DateTime.now().add(ttl);

  final T value;
  final DateTime expiresAt;

  bool get expired => DateTime.now().isAfter(expiresAt);
}
