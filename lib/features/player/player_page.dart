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

/// 全屏/宽屏选集侧栏背景（约 80% 不透明度）。
const _episodeOverlayPanelColor = Color(0xCC141414);

double _episodeOverlayPanelWidth(
  double screenWidth, {
  required bool inFullscreen,
}) {
  if (inFullscreen) {
    return (screenWidth * 0.36).clamp(288.0, 368.0);
  }
  return _episodeOverlayPanelWidthWide.clamp(320.0, screenWidth * 0.38);
}

const _episodeOverlayPanelWidthWide = 400.0;

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
              onPressed: (actionContext) =>
                  _showEpisodes(actionContext, detail),
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

  Future<void> _showEpisodes(
    BuildContext actionContext,
    MediaDetail detail,
  ) async {
    final inFullscreen = isFullscreen(actionContext);
    final overlay =
        inFullscreen ||
        MediaQuery.sizeOf(actionContext).width >= playerWideBreakpoint;

    void onPick(int lineIndex, int episodeIndex) {
      unawaited(_selectEpisode(lineIndex, episodeIndex));
    }

    if (overlay) {
      await showGeneralDialog<void>(
        context: actionContext,
        useRootNavigator: inFullscreen,
        barrierDismissible: true,
        barrierLabel: '关闭选集',
        barrierColor: Colors.black.withValues(alpha: 0.35),
        pageBuilder: (dialogContext, _, _) {
          final panelWidth = _episodeOverlayPanelWidth(
            MediaQuery.sizeOf(dialogContext).width,
            inFullscreen: inFullscreen,
          );
          return Align(
            alignment: Alignment.centerRight,
            child: Material(
              color: _episodeOverlayPanelColor,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: _EpisodePicker(
                  detail: detail,
                  lineIndex: _lineIndex,
                  episodeIndex: _episodeIndex,
                  overlay: true,
                  onSelected: onPick,
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    final colorScheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: actionContext,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: colorScheme.surface,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(actionContext).height * 0.68,
      ),
      builder: (sheetContext) => _EpisodePicker(
        detail: detail,
        lineIndex: _lineIndex,
        episodeIndex: _episodeIndex,
        overlay: false,
        onSelected: onPick,
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

class _EpisodePicker extends StatefulWidget {
  const _EpisodePicker({
    required this.detail,
    required this.lineIndex,
    required this.episodeIndex,
    required this.overlay,
    required this.onSelected,
  });

  final MediaDetail detail;
  final int lineIndex;
  final int episodeIndex;
  final bool overlay;
  final void Function(int lineIndex, int episodeIndex) onSelected;

  @override
  State<_EpisodePicker> createState() => _EpisodePickerState();
}

class _EpisodePickerState extends State<_EpisodePicker> {
  late int _activeLineIndex;

  @override
  void initState() {
    super.initState();
    _activeLineIndex = widget.lineIndex;
  }

  void _pickEpisode(int lineIndex, int episodeIndex) {
    Navigator.pop(context);
    widget.onSelected(lineIndex, episodeIndex);
  }

  @override
  Widget build(BuildContext context) {
    final list = _EpisodeList(
      detail: widget.detail,
      lineIndex: widget.lineIndex,
      episodeIndex: widget.episodeIndex,
      overlay: widget.overlay,
      onlyLineIndex: widget.overlay && widget.detail.playLines.length > 1
          ? _activeLineIndex
          : null,
      onSelected: _pickEpisode,
    );

    if (!widget.overlay) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [list],
        ),
      );
    }

    return SafeArea(
      left: false,
      right: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 12, 0),
            child: Row(
              children: [
                const Text(
                  '选集',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, color: Colors.white70),
                  tooltip: '关闭',
                ),
              ],
            ),
          ),
          if (widget.detail.playLines.length > 1)
            _EpisodeLineTabs(
              lines: widget.detail.playLines,
              lineIndex: _activeLineIndex,
              onChanged: (index) => setState(() => _activeLineIndex = index),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [list],
            ),
          ),
        ],
      ),
    );
  }
}

class _EpisodeLineTabs extends StatelessWidget {
  const _EpisodeLineTabs({
    required this.lines,
    required this.lineIndex,
    required this.onChanged,
  });

  final List<PlayLine> lines;
  final int lineIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: lines.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == lineIndex;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => onChanged(index),
              borderRadius: BorderRadius.circular(8),
              child: Ink(
                decoration: BoxDecoration(
                  color: selected
                      ? primary.withValues(alpha: 0.12)
                      : Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? primary.withValues(alpha: 0.85)
                        : Colors.white.withValues(alpha: 0.18),
                    width: selected ? 1.5 : 1,
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  lines[index].name,
                  style: TextStyle(
                    color: selected ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EpisodeList extends StatelessWidget {
  const _EpisodeList({
    required this.detail,
    required this.lineIndex,
    required this.episodeIndex,
    required this.onSelected,
    this.overlay = false,
    this.onlyLineIndex,
  });

  final MediaDetail detail;
  final int lineIndex;
  final int episodeIndex;
  final void Function(int lineIndex, int episodeIndex) onSelected;
  final bool overlay;
  final int? onlyLineIndex;

  @override
  Widget build(BuildContext context) {
    if (onlyLineIndex != null) {
      return _EpisodeGrid(
        lineIndex: onlyLineIndex!,
        line: detail.playLines[onlyLineIndex!],
        selectedLineIndex: lineIndex,
        episodeIndex: episodeIndex,
        overlay: overlay,
        onSelected: onSelected,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!overlay)
          Text(
            '线路与分集',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        if (!overlay) const SizedBox(height: 14),
        for (
          var currentLineIndex = 0;
          currentLineIndex < detail.playLines.length;
          currentLineIndex++
        ) ...[
          if (!overlay) ...[
            Text(
              detail.playLines[currentLineIndex].name,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 10),
          ],
          _EpisodeGrid(
            lineIndex: currentLineIndex,
            line: detail.playLines[currentLineIndex],
            selectedLineIndex: lineIndex,
            episodeIndex: episodeIndex,
            overlay: overlay,
            onSelected: onSelected,
          ),
          if (!overlay) const SizedBox(height: 20),
        ],
      ],
    );
  }
}

class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({
    required this.lineIndex,
    required this.line,
    required this.selectedLineIndex,
    required this.episodeIndex,
    required this.overlay,
    required this.onSelected,
  });

  final int lineIndex;
  final PlayLine line;
  final int selectedLineIndex;
  final int episodeIndex;
  final bool overlay;
  final void Function(int lineIndex, int episodeIndex) onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;
        const minTileWidth = 108.0;
        const tileHeight = 38.0;
        final width = constraints.maxWidth;
        final columns = (width / minTileWidth).floor().clamp(3, 6);
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        final episodes = line.episodes;
        if (episodes.isEmpty) {
          return const SizedBox.shrink();
        }
        final rowCount = (episodes.length + columns - 1) ~/ columns;

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var row = 0; row < rowCount; row++) ...[
              if (row > 0) const SizedBox(height: spacing),
              Row(
                children: [
                  for (var col = 0; col < columns; col++) ...[
                    if (col > 0) SizedBox(width: spacing),
                    SizedBox(
                      width: tileWidth,
                      height: tileHeight,
                      child: _episodeTileAt(
                        row: row,
                        col: col,
                        columns: columns,
                        tileWidth: tileWidth,
                        episodes: episodes,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _episodeTileAt({
    required int row,
    required int col,
    required int columns,
    required double tileWidth,
    required List<Episode> episodes,
  }) {
    final index = row * columns + col;
    if (index >= episodes.length) {
      return const SizedBox.shrink();
    }
    return _EpisodeTile(
      width: tileWidth,
      title: episodes[index].title,
      selected: lineIndex == selectedLineIndex && index == episodeIndex,
      overlay: overlay,
      onSelected: () => onSelected(lineIndex, index),
    );
  }
}

class _EpisodeTile extends StatelessWidget {
  const _EpisodeTile({
    required this.title,
    required this.width,
    required this.selected,
    required this.overlay,
    required this.onSelected,
  });

  final String title;
  final double width;
  final bool selected;
  final bool overlay;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color textColor;
    final BoxBorder? border;

    if (overlay) {
      background = selected
          ? scheme.primary.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04);
      textColor = selected ? Colors.white : Colors.white70;
      border = Border.all(
        color: selected
            ? scheme.primary.withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.18),
        width: selected ? 1.5 : 1,
      );
    } else {
      background = selected
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest;
      textColor = selected
          ? scheme.onPrimaryContainer
          : scheme.onSurfaceVariant;
      border = null;
    }

    return SizedBox(
      width: width,
      height: 38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onSelected,
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(8),
              border: border,
            ),
            child: Center(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
