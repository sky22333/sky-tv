import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/upstream/maccms_api.dart';
import '../../core/models/media_models.dart';
import 'iptv_repository.dart';
import '../storage/app_database.dart';
import 'media_repository.dart';
import 'settings_repository.dart';
import 'source_repository.dart';

final databaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final customUserAgentProvider = FutureProvider((ref) async {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  return repo.customUserAgent();
});

final requestHeadersProvider = FutureProvider<Map<String, String>>((ref) async {
  final userAgent = await ref.watch(customUserAgentProvider.future);
  if (userAgent.isEmpty) {
    return const {};
  }
  return {'User-Agent': userAgent};
});

final macCmsApiProvider = FutureProvider<MacCmsApi>((ref) async {
  final headers = await ref.watch(requestHeadersProvider.future);
  final api = MacCmsApi(headers: headers);
  ref.onDispose(api.close);
  return api;
});

final sourceRepositoryProvider = FutureProvider<SourceRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final headers = await ref.watch(requestHeadersProvider.future);
  return SourceRepository(db, headers: headers);
});

final iptvRepositoryProvider = FutureProvider<IptvRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final headers = await ref.watch(requestHeadersProvider.future);
  return IptvRepository(db, headers: headers);
});

final mediaRepositoryProvider = FutureProvider<MediaRepository>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  final api = await ref.watch(macCmsApiProvider.future);
  return MediaRepository(db: db, api: api);
});

final settingsRepositoryProvider = FutureProvider<SettingsRepository>((
  ref,
) async {
  final preferences = await SharedPreferences.getInstance();
  return SettingsRepository(preferences);
});

final themeModeProvider = FutureProvider((ref) async {
  final repo = await ref.watch(settingsRepositoryProvider.future);
  return repo.themeMode();
});

final sourcesProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(sourceRepositoryProvider.future);
  return repo.sources();
});

final sourceCategoriesProvider = FutureProvider.autoDispose
    .family<List<SourceCategory>, String>((ref, sourceId) async {
      final sources = await ref.watch(sourcesProvider.future);
      final mediaRepo = await ref.watch(mediaRepositoryProvider.future);
      final source = mediaRepo.findSource(sources, sourceId);
      if (source == null || source.disabled) {
        return const [];
      }
      return mediaRepo.categories(source);
    });

final categoryPreviewRowsProvider = FutureProvider.autoDispose
    .family<List<CategoryPreviewRow>, String>((ref, sourceId) async {
      final sources = await ref.watch(sourcesProvider.future);
      final mediaRepo = await ref.watch(mediaRepositoryProvider.future);
      final source = mediaRepo.findSource(sources, sourceId);
      if (source == null || source.disabled) {
        return const [];
      }
      final categories = await ref.watch(
        sourceCategoriesProvider(sourceId).future,
      );
      if (categories.isEmpty) {
        return const [];
      }
      return mediaRepo.loadCategoryPreviewRows(source, categories);
    });

final iptvLibraryProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(iptvRepositoryProvider.future);
  return repo.library();
});

final homeDataProvider = FutureProvider.autoDispose((ref) async {
  final repo = await ref.watch(mediaRepositoryProvider.future);
  return HomeData(
    records: repo.watchRecords(),
    favorites: repo.favorites(),
    recentSearches: repo.recentSearches(),
  );
});

final homeRecommendProvider = FutureProvider.autoDispose<List<MediaItem>>((
  ref,
) async {
  final sources = await ref.watch(sourcesProvider.future);
  final mediaRepo = await ref.watch(mediaRepositoryProvider.future);
  if (mediaRepo.enabledSources(sources).isEmpty) {
    return const [];
  }
  return mediaRepo.homeRecommendations(sources);
});

class HomeData {
  const HomeData({
    required this.records,
    required this.favorites,
    required this.recentSearches,
  });

  final List<WatchRecord> records;
  final List<MediaItem> favorites;
  final List<String> recentSearches;
}
