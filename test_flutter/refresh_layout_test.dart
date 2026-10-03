import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:skytv/core/models/media_models.dart';
import 'package:skytv/core/models/video_source.dart';
import 'package:skytv/core/upstream/maccms_api.dart';
import 'package:skytv/data/repositories/media_repository.dart';
import 'package:skytv/data/repositories/app_providers.dart';
import 'package:skytv/data/repositories/source_repository.dart';
import 'package:skytv/data/storage/app_database.dart';
import 'package:skytv/features/settings/settings_page.dart';
import 'package:skytv/features/player/player_page.dart';
import 'package:skytv/ui/widgets/home_focus_carousel.dart';
import 'package:skytv/ui/widgets/poster_card.dart';

void main() {
  const source = VideoSource(
    sourceId: 'one',
    name: 'Test',
    apiUrl: 'https://example.test/api',
  );
  late _Database db;
  late MediaRepository repo;
  late http.Client client;
  late List<Uri> requests;
  var revision = 1;

  setUp(() {
    db = _Database();
    requests = [];
    revision = 1;
    client = MockClient((request) async {
      requests.add(request.url);
      return http.Response(
        jsonEncode({
          'class': [
            {'type_id': '1', 'type_name': 'Category $revision'},
          ],
          'list': [
            {
              'vod_id': '1',
              'vod_name': 'Title $revision',
              'vod_pic': 'https://example.test/poster.jpg',
            },
          ],
        }),
        200,
      );
    });
    repo = MediaRepository(
      db: db,
      api: MacCmsApi(client: client),
    );
  });
  tearDown(() => client.close());

  test(
    'home refresh fetches new data without discarding detail cache',
    () async {
      await repo.detail(source, '1');
      expect((await repo.homeFeed([source])).focus.single.title, 'Title 1');
      revision = 2;
      expect((await repo.homeFeed([source])).focus.single.title, 'Title 1');
      expect(requests.length, 2);

      repo.clearHomeFeedCache();
      expect((await repo.homeFeed([source])).focus.single.title, 'Title 2');
      expect((await repo.detail(source, '1'))!.title, 'Title 1');
      expect(requests.length, 3);
    },
  );

  test(
    'browse refresh clears disk categories and only that source preview',
    () async {
      const other = VideoSource(
        sourceId: 'two',
        name: 'Other',
        apiUrl: 'https://other.test/api',
      );
      await repo.categories(source);
      await repo.categoryPreview(source, '1');
      await repo.categoryPreview(other, '1');
      revision = 2;
      repo.clearBrowseCache(source.sourceId);

      expect((await repo.categories(source)).single.name, 'Category 2');
      expect((await repo.categoryPreview(source, '1')).single.title, 'Title 2');
      expect((await repo.categoryPreview(other, '1')).single.title, 'Title 1');
      expect(requests.length, 5);
    },
  );

  test(
    'failed home requests cannot be reported as a successful empty refresh',
    () async {
      final failingClient = MockClient(
        (_) async => http.Response('unavailable', 503),
      );
      addTearDown(failingClient.close);
      final failingRepo = MediaRepository(
        db: db,
        api: MacCmsApi(client: failingClient),
      );
      await expectLater(failingRepo.homeFeed([source]), throwsException);
    },
  );

  testWidgets(
    'null playback detail stops loading, supports retry and keeps back navigation',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (_) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      var attempts = 0;
      var hasDetail = false;
      final detailClient = MockClient((_) async {
        attempts++;
        return http.Response(
          jsonEncode({
            'list': hasDetail
                ? [
                    {'vod_id': '1', 'vod_name': 'No episodes'},
                  ]
                : [],
          }),
          200,
        );
      });
      addTearDown(detailClient.close);
      db.sources = [source];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaRepositoryProvider.overrideWith(
              (_) async => MediaRepository(
                db: db,
                api: MacCmsApi(client: detailClient),
              ),
            ),
            sourceRepositoryProvider.overrideWith(
              (_) async => SourceRepository(db, client: detailClient),
            ),
            requestHeadersProvider.overrideWith((_) async => {}),
          ],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const PlayerPage(
                        sourceId: 'one',
                        mediaId: '1',
                        lineIndex: 0,
                        episodeIndex: 0,
                        resume: false,
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.textContaining('当前源没有返回该影片详情'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(attempts, 2);
      hasDetail = true;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('没有播放地址'), findsOneWidget);
      expect(attempts, 3);
      await tester.pageBack();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Open'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'settings refresh waits for the request and reports its failure',
    (tester) async {
      final response = Completer<http.Response>();
      final pendingClient = MockClient((_) => response.future);
      addTearDown(pendingClient.close);
      final pendingRepo = MediaRepository(
        db: db,
        api: MacCmsApi(client: pendingClient),
      );
      db.sources = [source];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaRepositoryProvider.overrideWith((_) async => pendingRepo),
            sourceRepositoryProvider.overrideWith(
              (_) async => SourceRepository(db, client: pendingClient),
            ),
            themeModeProvider.overrideWith((_) async => ThemeMode.system),
            customUserAgentProvider.overrideWith((_) async => ''),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('刷新首页数据'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('首页数据已刷新'), findsNothing);
      response.complete(http.Response('unavailable', 503));
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('刷新失败'), findsOneWidget);
      expect(find.text('首页数据已刷新'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'carousel uses parent width, caps posters and survives resizing',
    (tester) async {
      final items = List.generate(
        5,
        (i) => MediaItem(
          id: '$i',
          sourceId: 'one',
          sourceName: 'Test',
          title: 'Title $i',
        ),
      );
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      Future<void> layout(double width) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: width,
                  child: HomeFocusCarousel(items: items, onTap: (_) {}),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final size = tester.getSize(find.byType(PosterCard).first);
        expect(size.width, lessThanOrEqualTo(220.01));
        expect(size.width / size.height, closeTo(2 / 3, 0.001));
      }

      await layout(320);
      expect(
        tester.getSize(find.byType(PosterCard).first).width,
        closeTo(111.6, 0.01),
      );
      await tester.drag(find.byType(PageView), const Offset(-130, 0));
      await tester.pumpAndSettle();
      final before = tester
          .widget<PageView>(find.byType(PageView))
          .controller!
          .page;
      await layout(1440);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        before,
      );
      await layout(390);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}

class _Database extends Fake implements AppDatabase {
  final _categories = <String, List<SourceCategory>>{};
  List<VideoSource> sources = [];

  @override
  List<VideoSource> loadSources() => sources;

  @override
  List<WatchRecord> loadWatchRecords() => [];
  @override
  List<MediaItem> loadFavorites() => [];
  @override
  List<SourceCategory> loadFreshCategories(String sourceId) =>
      _categories[sourceId] ?? [];
  @override
  void saveCategories(String sourceId, List<SourceCategory> categories) =>
      _categories[sourceId] = categories;
  @override
  void clearCategories(String sourceId) => _categories.remove(sourceId);
}
