import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/media_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../data/repositories/media_repository.dart';
import '../../ui/theme/app_system_ui.dart';
import '../../ui/widgets/state_views.dart';
import 'player_scaffold.dart';
import 'player_surface.dart';

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    super.key,
    required this.sourceId,
    required this.mediaId,
    required this.lineIndex,
    required this.episodeIndex,
    required this.resume,
    this.initialDetail,
  });

  final String sourceId;
  final String mediaId;
  final int lineIndex;
  final int episodeIndex;
  final bool resume;
  final MediaDetail? initialDetail;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  late final Player _player;
  late final VideoController _videoController;
  MediaRepository? _mediaRepo;
  MediaDetail? _detail;
  Map<String, String> _requestHeaders = const {};
  String? _loadError;
  int _lineIndex = 0;
  int _episodeIndex = 0;
  bool _opening = false;
  bool _closing = false;
  bool _allowPop = false;
  bool _playerDisposed = false;
  int? _resumePositionMs;
  Duration _lastKnownPosition = Duration.zero;
  Duration _lastKnownDuration = Duration.zero;
  DateTime? _lastProgressSavedAt;
  late final ValueNotifier<String> _episodeTitleNotifier;
  StreamSubscription<bool>? _completedSubscription;
  StreamSubscription<bool>? _playingSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;

  @override
  void initState() {
    super.initState();
    _lineIndex = widget.lineIndex;
    _episodeIndex = widget.episodeIndex;
    _player = Player(
      configuration: const PlayerConfiguration(
        title: 'sky-tv',
        bufferSize: 64 * 1024 * 1024,
      ),
    );
    _videoController = VideoController(_player);
    _episodeTitleNotifier = ValueNotifier('');
    _completedSubscription = _player.stream.completed.listen((completed) {
      if (completed) {
        unawaited(_openNextEpisode());
      }
    });
    _playingSubscription = _player.stream.playing.listen((playing) {
      if (!playing && !_opening) {
        _saveRecord();
      }
    });
    _positionSubscription = _player.stream.position.listen((position) {
      _lastKnownPosition = position;
      _saveRecordThrottled();
    });
    _durationSubscription = _player.stream.duration.listen((duration) {
      _lastKnownDuration = duration;
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _completedSubscription?.cancel();
    _playingSubscription?.cancel();
    _positionSubscription?.cancel();
    _durationSubscription?.cancel();
    _episodeTitleNotifier.dispose();
    if (!_playerDisposed) {
      _saveRecord();
      unawaited(_player.dispose());
      _playerDisposed = true;
    }
    unawaited(AppSystemUi.restore());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final headersFuture = ref.read(requestHeadersProvider.future);
      final mediaRepo = await ref.read(mediaRepositoryProvider.future);
      if (!mounted) {
        return;
      }
      _mediaRepo = mediaRepo;
      if (widget.resume) {
        final record = mediaRepo.watchRecord(widget.sourceId, widget.mediaId);
        if (record != null &&
            record.lineIndex == _lineIndex &&
            record.episodeIndex == _episodeIndex &&
            record.positionMs > 0) {
          _resumePositionMs = record.positionMs;
        }
      }
      final initialDetail = widget.initialDetail;
      final detailFuture =
          initialDetail != null &&
              initialDetail.sourceId == widget.sourceId &&
              initialDetail.id == widget.mediaId
          ? Future<MediaDetail?>.value(initialDetail)
          : _loadDetail(mediaRepo);
      final detail = await detailFuture;
      _requestHeaders = await headersFuture;
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = detail;
        _loadError = null;
      });
      _syncEpisodeTitle();
      if (detail != null) {
        await _openCurrent();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _detail = null;
        _loadError = error.toString();
      });
    }
  }

  Future<MediaDetail?> _loadDetail(MediaRepository mediaRepo) async {
    final sourceRepo = await ref.read(sourceRepositoryProvider.future);
    final source = sourceRepo.findById(widget.sourceId);
    if (source == null) {
      throw Exception('影视源不存在');
    }
    return mediaRepo.detail(source, widget.mediaId);
  }

  Future<void> _openCurrent() async {
    if (_closing || _playerDisposed) {
      return;
    }
    final episode = _currentEpisode;
    if (episode == null) {
      return;
    }
    setState(() {
      _opening = true;
      _loadError = null;
    });
    try {
      final resumePositionMs = _resumePositionMs;
      _resumePositionMs = null;
      _resetProgressSnapshot();
      await _player.open(
        Media(
          episode.url,
          httpHeaders: _requestHeaders.isEmpty ? null : _requestHeaders,
          start: resumePositionMs == null
              ? null
              : Duration(milliseconds: resumePositionMs),
        ),
        play: true,
      );
      if (!mounted || _closing) {
        return;
      }
      setState(() => _opening = false);
    } catch (error) {
      if (!mounted || _closing) {
        return;
      }
      setState(() {
        _opening = false;
        _loadError = error.toString();
      });
    }
  }

  Episode? get _currentEpisode {
    final detail = _detail;
    if (detail == null || detail.playLines.isEmpty) {
      return null;
    }
    final lineIndex = _lineIndex.clamp(0, detail.playLines.length - 1);
    final line = detail.playLines[lineIndex];
    if (line.episodes.isEmpty) {
      return null;
    }
    return line.episodes[_episodeIndex.clamp(0, line.episodes.length - 1)];
  }

  @override
  Widget build(BuildContext context) {
    final detail = _detail;
    if (_loadError != null && detail == null) {
      return _wrapPopScope(
        Scaffold(
          appBar: AppBar(title: const Text('播放')),
          body: ErrorState(message: _loadError!, onRetry: _load),
        ),
      );
    }
    if (detail == null) {
      return _wrapPopScope(
        const Scaffold(
          appBar: _PlayerAppBar(),
          body: LoadingState(message: '正在加载播放地址...'),
        ),
      );
    }
    if (detail.playLines.isEmpty || _currentEpisode == null) {
      return _wrapPopScope(
        const Scaffold(
          appBar: _PlayerAppBar(),
          body: EmptyState(
            icon: Icons.link_off_rounded,
            title: '没有播放地址',
            message: '当前影片没有可播放分集。',
          ),
        ),
      );
    }

    return _wrapPopScope(
      PortraitPlayerScaffold(
        wideAppBar: const _PlayerAppBar(),
        bodyBuilder: (context, constraints, wide) {
          final player = PlayerVideoBlock(
            controller: _videoController,
            title: detail.title,
            subtitle: _episodeTitleNotifier,
            loading: _opening,
            loadError: _loadError,
            onBack: wide ? null : () => unawaited(_closePage()),
            selectorAction: PlayerSurfaceAction(
              icon: Icons.video_library_rounded,
              tooltip: '选集',
              onPressed: (context) => _showEpisodes(context, detail),
            ),
            onNext: _hasNextEpisode
                ? () => unawaited(_openNextEpisode())
                : null,
            onEnterFullscreen: _enterFullscreen,
            onExitFullscreen: _exitFullscreen,
            maxPlayerHeight: wide ? constraints.maxHeight * 0.72 : null,
          );
          final nowPlaying = _NowPlayingPanel(
            detail: detail,
            lineIndex: _lineIndex,
            episodeIndex: _episodeIndex,
            compact: !wide,
          );
          final episodes = _EpisodeSection(
            detail: detail,
            lineIndex: _lineIndex,
            episodeIndex: _episodeIndex,
            onSelected: (lineIndex, episodeIndex) =>
                unawaited(_selectEpisode(lineIndex, episodeIndex)),
          );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [player, nowPlaying],
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(
                  width: 400,
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [episodes],
                  ),
                ),
              ],
            );
          }
          return PortraitPlayerLayout(
            player: player,
            content: ListView(
              padding: EdgeInsets.zero,
              children: [nowPlaying, episodes],
            ),
          );
        },
      ),
    );
  }

  Widget _wrapPopScope(Widget child) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_closePage());
        }
      },
      child: child,
    );
  }

  Future<void> _selectEpisode(int lineIndex, int episodeIndex) async {
    if (_closing ||
        _opening ||
        (lineIndex == _lineIndex && episodeIndex == _episodeIndex)) {
      return;
    }
    _saveRecord();
    setState(() {
      _lineIndex = lineIndex;
      _episodeIndex = episodeIndex;
    });
    _syncEpisodeTitle();
    await _openCurrent();
  }

  Future<void> _openNextEpisode() async {
    final detail = _detail;
    if (!mounted ||
        _closing ||
        _opening ||
        detail == null ||
        detail.playLines.isEmpty) {
      return;
    }
    final line =
        detail.playLines[_lineIndex.clamp(0, detail.playLines.length - 1)];
    if (_episodeIndex + 1 >= line.episodes.length) {
      return;
    }
    await _selectEpisode(_lineIndex, _episodeIndex + 1);
  }

  bool get _hasNextEpisode {
    final detail = _detail;
    if (detail == null || detail.playLines.isEmpty) {
      return false;
    }
    final line =
        detail.playLines[_lineIndex.clamp(0, detail.playLines.length - 1)];
    return _episodeIndex + 1 < line.episodes.length;
  }

  Future<void> _closePage() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _saveRecord();
    await _completedSubscription?.cancel();
    try {
      await _player.pause();
      await _player.stop();
    } catch (_) {
      // Native playback may already be tearing down after a source failure.
    }
    if (!_playerDisposed) {
      await _player.dispose();
      _playerDisposed = true;
    }
    await AppSystemUi.restore();
    if (mounted) {
      setState(() => _allowPop = true);
      Navigator.pop(context);
    }
  }

  Future<void> _enterFullscreen() => enterPlayerFullscreen();

  Future<void> _exitFullscreen() => AppSystemUi.restore();

  Future<void> _showEpisodes(BuildContext context, MediaDetail detail) async {
    final wide = MediaQuery.sizeOf(context).width >= 700;
    if (wide) {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: '关闭选集',
        barrierColor: Colors.black45,
        pageBuilder: (context, _, _) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.black,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width.clamp(320.0, 420.0),
              height: double.infinity,
              child: _EpisodePicker(
                detail: detail,
                lineIndex: _lineIndex,
                episodeIndex: _episodeIndex,
                dark: true,
                onSelected: (lineIndex, episodeIndex) {
                  Navigator.pop(context);
                  unawaited(_selectEpisode(lineIndex, episodeIndex));
                },
              ),
            ),
          ),
        ),
      );
      return;
    }
    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: colorScheme.surface,
      barrierColor: Colors.black54,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.68,
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: _EpisodePicker(
          detail: detail,
          lineIndex: _lineIndex,
          episodeIndex: _episodeIndex,
          dark: false,
          onSelected: (lineIndex, episodeIndex) {
            Navigator.pop(context);
            unawaited(_selectEpisode(lineIndex, episodeIndex));
          },
        ),
      ),
    );
  }

  void _saveRecordThrottled() {
    if (_opening) {
      return;
    }
    final now = DateTime.now();
    final savedAt = _lastProgressSavedAt;
    if (savedAt != null &&
        now.difference(savedAt) < const Duration(seconds: 15)) {
      return;
    }
    if (_saveRecord(now: now)) {
      _lastProgressSavedAt = now;
    }
  }

  bool _saveRecord({DateTime? now}) {
    if (_opening) {
      return false;
    }
    final detail = _detail;
    final repo = _mediaRepo;
    final episode = _currentEpisode;
    if (detail == null || repo == null || episode == null) {
      return false;
    }
    final position = _lastKnownPosition > Duration.zero
        ? _lastKnownPosition
        : _player.state.position;
    final duration = _lastKnownDuration > Duration.zero
        ? _lastKnownDuration
        : _player.state.duration;
    if (position <= Duration.zero && duration <= Duration.zero) {
      return false;
    }
    repo.saveWatchRecord(
      WatchRecord(
        sourceId: detail.sourceId,
        mediaId: detail.id,
        sourceName: detail.sourceName,
        title: detail.title,
        poster: detail.poster,
        lineIndex: _lineIndex,
        episodeIndex: _episodeIndex,
        positionMs: position.inMilliseconds,
        durationMs: duration.inMilliseconds,
        updatedAt: now ?? DateTime.now(),
      ),
    );
    ref.invalidate(homeDataProvider);
    ref.invalidate(homeRecommendProvider);
    return true;
  }

  void _resetProgressSnapshot() {
    _lastKnownPosition = Duration.zero;
    _lastKnownDuration = Duration.zero;
    _lastProgressSavedAt = null;
  }

  void _syncEpisodeTitle() {
    _episodeTitleNotifier.value = _currentEpisode?.title ?? '';
  }
}

class _PlayerAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _PlayerAppBar();

  @override
  Widget build(BuildContext context) {
    return AppBar(title: const Text('播放'));
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

class _NowPlayingPanel extends StatelessWidget {
  const _NowPlayingPanel({
    required this.detail,
    required this.lineIndex,
    required this.episodeIndex,
    this.compact = false,
  });

  final MediaDetail detail;
  final int lineIndex;
  final int episodeIndex;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final line = detail.playLines[lineIndex];
    final episode = line.episodes[episodeIndex];
    final meta = [detail.sourceName, line.name, episode.title].join(' · ');

    return Padding(
      padding: EdgeInsets.fromLTRB(20, compact ? 12 : 20, 20, compact ? 4 : 8),
      child: compact
          ? Text(
              meta,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  meta,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
    );
  }
}

class _EpisodeSection extends StatelessWidget {
  const _EpisodeSection({
    required this.detail,
    required this.lineIndex,
    required this.episodeIndex,
    required this.onSelected,
  });

  final MediaDetail detail;
  final int lineIndex;
  final int episodeIndex;
  final void Function(int lineIndex, int episodeIndex) onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
      child: _EpisodeList(
        detail: detail,
        lineIndex: lineIndex,
        episodeIndex: episodeIndex,
        onSelected: onSelected,
      ),
    );
  }
}

class _EpisodePicker extends StatelessWidget {
  const _EpisodePicker({
    required this.detail,
    required this.lineIndex,
    required this.episodeIndex,
    required this.dark,
    required this.onSelected,
  });

  final MediaDetail detail;
  final int lineIndex;
  final int episodeIndex;
  final bool dark;
  final void Function(int lineIndex, int episodeIndex) onSelected;

  @override
  Widget build(BuildContext context) {
    final child = ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        _EpisodeList(
          detail: detail,
          lineIndex: lineIndex,
          episodeIndex: episodeIndex,
          onSelected: onSelected,
        ),
      ],
    );
    return SafeArea(
      child: dark
          ? Theme(
              data: Theme.of(context).copyWith(
                colorScheme: const ColorScheme.dark(
                  surface: Colors.black,
                  onSurface: Colors.white,
                  primary: Colors.white,
                  onPrimary: Colors.black,
                ),
              ),
              child: child,
            )
          : child,
    );
  }
}

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.detail,
    required this.lineIndex,
    required this.episodeIndex,
    required this.onSelected,
  });

  final MediaDetail detail;
  final int lineIndex;
  final int episodeIndex;
  final void Function(int lineIndex, int episodeIndex) onSelected;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '线路与分集',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),
        for (
          var currentLineIndex = 0;
          currentLineIndex < detail.playLines.length;
          currentLineIndex++
        ) ...[
          Text(
            detail.playLines[currentLineIndex].name,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              const minEpisodeChipWidth = 108.0;
              final columns = (constraints.maxWidth / minEpisodeChipWidth)
                  .floor()
                  .clamp(3, 6);
              final chipWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: 10,
                children: [
                  for (
                    var currentEpisodeIndex = 0;
                    currentEpisodeIndex <
                        detail.playLines[currentLineIndex].episodes.length;
                    currentEpisodeIndex++
                  )
                    _EpisodeChip(
                      width: chipWidth,
                      title: detail
                          .playLines[currentLineIndex]
                          .episodes[currentEpisodeIndex]
                          .title,
                      selected:
                          currentLineIndex == lineIndex &&
                          currentEpisodeIndex == episodeIndex,
                      onSelected: () =>
                          onSelected(currentLineIndex, currentEpisodeIndex),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _EpisodeChip extends StatelessWidget {
  const _EpisodeChip({
    required this.title,
    required this.width,
    required this.selected,
    required this.onSelected,
  });

  final String title;
  final double width;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: ChoiceChip(
        showCheckmark: false,
        selected: selected,
        label: SizedBox(
          width: double.infinity,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
        onSelected: (_) => onSelected(),
      ),
    );
  }
}
