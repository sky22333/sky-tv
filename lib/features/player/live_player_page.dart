import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../../core/models/iptv_models.dart';
import '../../data/repositories/app_providers.dart';
import '../../ui/theme/app_system_ui.dart';
import '../../ui/widgets/app_search_field.dart';
import '../../ui/widgets/state_views.dart';
import '../live/live_channel_tile.dart';
import '../live/live_group_selector.dart';
import 'player_scaffold.dart';
import 'player_surface.dart';

class LivePlayerPage extends ConsumerStatefulWidget {
  const LivePlayerPage({super.key, required this.channelId});

  final String channelId;

  @override
  ConsumerState<LivePlayerPage> createState() => _LivePlayerPageState();
}

class _LivePlayerPageState extends ConsumerState<LivePlayerPage> {
  static const _searchDebounce = Duration(milliseconds: 300);

  late final Player _player;
  late final VideoController _videoController;
  late final ValueNotifier<String> _subtitleNotifier;
  IptvLibrary? _library;
  IptvChannel? _channel;
  Map<String, String> _requestHeaders = const {};
  String? _group;
  String _keyword = '';
  String? _loadError;
  bool _loading = true;
  bool _closing = false;
  bool _allowPop = false;
  bool _playerDisposed = false;
  int _openToken = 0;
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _videoController = VideoController(_player);
    _subtitleNotifier = ValueNotifier('直播');
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _subtitleNotifier.dispose();
    if (!_playerDisposed) {
      unawaited(_player.dispose());
      _playerDisposed = true;
    }
    unawaited(AppSystemUi.restore());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final repo = await ref.read(iptvRepositoryProvider.future);
      final library = repo.library();
      final channel = _findChannel(library.channels, widget.channelId);
      if (channel == null) {
        throw Exception('直播频道不存在');
      }
      _requestHeaders = await ref.read(requestHeadersProvider.future);
      if (!mounted) {
        return;
      }
      setState(() {
        _library = library;
        _group = channel.group;
      });
      await _playChannel(channel);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _playChannel(IptvChannel channel) async {
    final token = ++_openToken;
    setState(() {
      _channel = channel;
      _loading = true;
      _loadError = null;
    });
    _subtitleNotifier.value = channel.group ?? '直播';
    try {
      await _player.open(
        Media(
          channel.url,
          httpHeaders: _requestHeaders.isEmpty ? null : _requestHeaders,
        ),
        play: true,
      );
      if (!mounted || token != _openToken) {
        return;
      }
      setState(() => _loading = false);
    } catch (error) {
      if (!mounted || token != _openToken) {
        return;
      }
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  void _onSearchChanged(String value, {ValueChanged<String>? onApplied}) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) {
        return;
      }
      final normalized = value.trim();
      setState(() => _keyword = normalized);
      onApplied?.call(normalized);
    });
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    final channel = _channel;
    final title = channel?.name ?? '直播';
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(_closePage());
        }
      },
      child: PortraitPlayerScaffold(
        wideAppBar: AppBar(title: Text(title)),
        bodyBuilder: (context, constraints, wide) {
          final player = PlayerVideoBlock(
            controller: _videoController,
            title: title,
            subtitle: _subtitleNotifier,
            loading: _loading,
            loadError: _loadError,
            onBack: wide ? null : () => unawaited(_closePage()),
            selectorAction: library == null
                ? null
                : PlayerSurfaceAction(
                    icon: Icons.live_tv_rounded,
                    tooltip: '频道',
                    onPressed: _showChannels,
                  ),
            onNext: _nextChannel == null
                ? null
                : () => unawaited(_playChannel(_nextChannel!)),
            onEnterFullscreen: enterPlayerFullscreen,
            onExitFullscreen: AppSystemUi.restore,
            maxPlayerHeight: wide ? constraints.maxHeight * 0.72 : null,
          );
          final browser = library == null
              ? const LoadingState(message: '正在读取直播频道...')
              : _LiveChannelBrowser(
                  library: library,
                  selectedId: channel?.id,
                  group: _group,
                  keyword: _keyword,
                  onGroupChanged: (value) => setState(() => _group = value),
                  onSearchChanged: _onSearchChanged,
                  onSelected: (item) => unawaited(_playChannel(item)),
                );
          if (wide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: ListView(children: [player])),
                const VerticalDivider(width: 1),
                SizedBox(width: 400, child: browser),
              ],
            );
          }
          return PortraitPlayerLayout(player: player, content: browser);
        },
      ),
    );
  }

  Future<void> _closePage() async {
    if (_closing) {
      return;
    }
    _closing = true;
    _searchTimer?.cancel();
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

  IptvChannel? get _nextChannel {
    final channel = _channel;
    final library = _library;
    if (channel == null || library == null) {
      return null;
    }
    final channels = _filterChannels(library.channels, _group, _keyword);
    final index = channels.indexWhere((item) => item.id == channel.id);
    if (index < 0 || index + 1 >= channels.length) {
      return null;
    }
    return channels[index + 1];
  }

  Future<void> _showChannels(BuildContext context) async {
    final library = _library;
    if (library == null) {
      return;
    }
    var group = _group;
    var keyword = _keyword;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '关闭频道列表',
      barrierColor: Colors.black45,
      pageBuilder: (context, _, _) => StatefulBuilder(
        builder: (context, setDialogState) => Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.black,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width.clamp(320.0, 420.0),
              height: double.infinity,
              child: _LiveChannelBrowser(
                library: library,
                selectedId: _channel?.id,
                group: group,
                keyword: keyword,
                dark: true,
                onGroupChanged: (value) {
                  setDialogState(() => group = value);
                  setState(() => _group = value);
                },
                onSearchChanged: (value) {
                  _onSearchChanged(
                    value,
                    onApplied: (normalized) {
                      setDialogState(() => keyword = normalized);
                    },
                  );
                },
                onSelected: (item) {
                  Navigator.pop(context);
                  unawaited(_playChannel(item));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChannelBrowser extends StatelessWidget {
  const _LiveChannelBrowser({
    required this.library,
    required this.selectedId,
    required this.group,
    required this.keyword,
    required this.onGroupChanged,
    required this.onSearchChanged,
    required this.onSelected,
    this.dark = false,
  });

  final IptvLibrary library;
  final String? selectedId;
  final String? group;
  final String keyword;
  final ValueChanged<String?> onGroupChanged;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<IptvChannel> onSelected;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final channels = _filterChannels(library.channels, group, keyword);
    final child = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: AppSearchField(
            hintText: '搜索频道',
            dark: dark,
            onChanged: onSearchChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LiveGroupSelector(
            groups: library.groups,
            group: group,
            dark: dark,
            onChanged: onGroupChanged,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: channels.isEmpty
              ? EmptyState(
                  icon: Icons.search_off_rounded,
                  title: '没有匹配频道',
                  message: '换个分组或关键词再试。',
                  compact: true,
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                  itemBuilder: (context, index) {
                    final channel = channels[index];
                    return LiveChannelTile(
                      channel: channel,
                      selected: channel.id == selectedId,
                      dark: dark,
                      onTap: () => onSelected(channel),
                    );
                  },
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemCount: channels.length,
                ),
        ),
      ],
    );
    return SafeArea(
      top: dark,
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

IptvChannel? _findChannel(List<IptvChannel> channels, String id) {
  for (final channel in channels) {
    if (channel.id == id) {
      return channel;
    }
  }
  return null;
}

List<IptvChannel> _filterChannels(
  List<IptvChannel> channels,
  String? group,
  String keyword,
) {
  if (group == null && keyword.isEmpty) {
    return channels;
  }
  return channels.where((channel) {
    final matchesGroup = group == null || channel.group == group;
    final matchesKeyword = keyword.isEmpty || channel.name.contains(keyword);
    return matchesGroup && matchesKeyword;
  }).toList();
}
