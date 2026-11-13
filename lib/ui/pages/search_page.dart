import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/track.dart';
import '../../services/engines/ytmusic_client.dart';
import '../../services/music_service.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import '../widgets/actions.dart';
import '../glass/liquid_glass.dart';
import '../widgets/large_title.dart';
import '../widgets/track_row.dart';
import 'video_player_page.dart';
import 'videos_page.dart' show VideoTile;

/// Search: suggestions while typing, results on submit, split into a music tab
/// (songs to play) and a video tab (music videos, stages, fancams to watch).
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;
  int _requestId = 0; // discards responses that arrive out of order
  int _suggestId = 0;

  static const _recentKey = 'drizonRecentSearches';
  List<String> _recent = const [];
  bool _videoMode = false;
  Future<List<YtmItem>>? _videos; // fetched lazily, only if the video tab is opened
  List<Track> _results = const [];
  List<String> _suggestions = const [];
  bool _typing = false; // showing suggestions instead of results
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _recent = p.getStringList(_recentKey) ?? const []);
    });
  }

  Future<void> _remember(String q) async {
    final next = [q, ..._recent.where((e) => e != q)].take(12).toList();
    setState(() => _recent = next);
    (await SharedPreferences.getInstance()).setStringList(_recentKey, next);
  }

  Future<void> _clearRecent() async {
    setState(() => _recent = const []);
    (await SharedPreferences.getInstance()).remove(_recentKey);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    setState(() => _typing = text.trim().isNotEmpty);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => _suggest(text));
  }

  Future<void> _suggest(String text) async {
    final id = ++_suggestId;
    if (text.trim().isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    try {
      final s = await context.read<YtmClient>().suggestions(text);
      if (mounted && id == _suggestId) setState(() => _suggestions = s);
    } catch (_) {
      // suggestions are best-effort
    }
  }

  Future<void> _search(String text) async {
    _debounce?.cancel();
    _suggestId++; // drop pending suggestions
    _focus.unfocus();
    final q = text.trim();
    if (_controller.text != text) _controller.text = text;
    final id = ++_requestId;
    setState(() {
      _typing = false;
      _query = q;
      _results = const [];
      _videos = null;
      _error = null;
      _loading = q.isNotEmpty;
    });
    if (q.isEmpty) return;
    _remember(q);
    if (_videoMode) _loadVideos();
    try {
      final tracks = await context.read<MusicService>().search(q);
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = tracks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _error = '검색에 실패했어요. 잠시 후 다시 시도해 주세요.';
        _loading = false;
      });
    }
  }

  void _loadVideos() {
    if (_query.isEmpty || _videos != null) return;
    _videos = context.read<YtmClient>().searchVideos(_query);
  }

  void _setMode(bool video) {
    setState(() {
      _videoMode = video;
      if (video) _loadVideos();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Align(alignment: Alignment.centerLeft, child: LargeTitle('검색')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: LiquidGlass(
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            shadow: false,
            child: CupertinoSearchTextField(
              controller: _controller,
              focusNode: _focus,
              placeholder: '아티스트, 노래, 영상',
              backgroundColor: Colors.transparent,
              padding: const EdgeInsetsDirectional.fromSTEB(8, 12, 8, 12),
              onChanged: _onChanged,
              onSubmitted: _search,
              onSuffixTap: () {
                _controller.clear();
                _search('');
              },
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoSlidingSegmentedControl<bool>(
              groupValue: _videoMode,
              children: const {
                false: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('음악')),
                true: Padding(padding: EdgeInsets.symmetric(vertical: 6), child: Text('비디오')),
              },
              onValueChanged: (v) => _setMode(v ?? false),
            ),
          ),
        ),
        Expanded(child: _typing ? _suggestionList() : (_videoMode ? _videoBody() : _body())),
      ],
    );
  }

  Widget _suggestionList() {
    final pal = context.pal;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: ShellInsets.of(context)),
      itemCount: _suggestions.length,
      itemBuilder: (context, i) => ListTile(
        leading: Icon(CupertinoIcons.search, color: pal.secondaryLabel, size: 20),
        title: Text(_suggestions[i], style: Type.row(pal)),
        onTap: () => _search(_suggestions[i]),
      ),
    );
  }

  Widget _body() {
    final pal = context.pal;
    if (_loading) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_error != null) {
      return _Message(icon: CupertinoIcons.exclamationmark_circle, text: _error!);
    }
    if (_query.isEmpty) {
      if (_recent.isEmpty) {
        return const _Message(icon: CupertinoIcons.search, text: '좋아하는 음악을 검색해 보세요');
      }
      return ListView(
        padding: EdgeInsets.only(bottom: ShellInsets.of(context)),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(child: Text('최근 검색', style: Type.title(pal).copyWith(fontSize: 20))),
                CupertinoButton(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: _clearRecent,
                  child: const Text('지우기', style: TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ),
          for (final q in _recent)
            ListTile(
              leading: Icon(CupertinoIcons.clock, color: pal.secondaryLabel, size: 20),
              title: Text(q, style: Type.row(pal)),
              onTap: () => _search(q),
            ),
        ],
      );
    }
    if (_results.isEmpty) {
      return const _Message(icon: CupertinoIcons.music_note, text: '결과가 없어요');
    }

    final player = context.read<PlayerService>();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.only(bottom: ShellInsets.of(context)),
      itemCount: _results.length,
      itemBuilder: (context, i) => FadeSlideIn(
        index: i,
        child: TrackRow(
          track: _results[i],
          onTap: () => player.playTrack(_results[i], queue: _results, index: i),
          onMore: () => showTrackActions(context, _results[i]),
        ),
      ),
    );
  }

  Widget _videoBody() {
    if (_query.isEmpty) {
      return const _Message(icon: CupertinoIcons.play_rectangle, text: '뮤직비디오, 무대, 직캠을 검색해 보세요');
    }
    final future = _videos;
    if (future == null) return const SizedBox.shrink();
    return FutureBuilder<List<YtmItem>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CupertinoActivityIndicator(radius: 14));
        }
        if (snap.hasError) {
          return const _Message(
              icon: CupertinoIcons.exclamationmark_circle, text: '검색에 실패했어요. 잠시 후 다시 시도해 주세요.');
        }
        final items = snap.data ?? const [];
        if (items.isEmpty) return const _Message(icon: CupertinoIcons.play_rectangle, text: '결과가 없어요');
        return ListView.builder(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + ShellInsets.of(context)),
          itemCount: items.length,
          itemBuilder: (context, i) => FadeSlideIn(
            index: i,
            child: VideoTile(
              item: items[i],
              onTap: () => Navigator.of(context, rootNavigator: true)
                  .push(VideoPlayerPage.route(items[i])),
            ),
          ),
        );
      },
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: pal.secondaryLabel),
          const SizedBox(height: 12),
          Text(text, style: Type.sub(pal)),
        ],
      ),
    );
  }
}
