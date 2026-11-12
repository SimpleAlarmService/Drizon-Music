import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../services/engines/ytmusic_client.dart';
import '../../services/music_service.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import '../widgets/actions.dart';
import '../widgets/large_title.dart';
import '../widgets/track_row.dart';

/// Search: YouTube Music suggestions while typing, results on submit,
/// grouped into songs (with album art) and videos.
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

  List<Track> _results = const [];
  List<String> _suggestions = const [];
  bool _typing = false; // showing suggestions instead of results
  bool _loading = false;
  String? _error;
  String _query = '';

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
      _error = null;
      _loading = q.isNotEmpty;
    });
    if (q.isEmpty) return;
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Align(alignment: Alignment.centerLeft, child: LargeTitle('검색')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: CupertinoSearchTextField(
            controller: _controller,
            focusNode: _focus,
            placeholder: '아티스트, 노래, 앨범',
            onChanged: _onChanged,
            onSubmitted: _search,
            onSuffixTap: () {
              _controller.clear();
              _search('');
            },
          ),
        ),
        Expanded(child: _typing ? _suggestionList() : _body()),
      ],
    );
  }

  Widget _suggestionList() {
    final pal = context.pal;
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
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
      return const _Message(icon: CupertinoIcons.search, text: '좋아하는 음악을 검색해 보세요');
    }
    if (_results.isEmpty) {
      return const _Message(icon: CupertinoIcons.music_note, text: '결과가 없어요');
    }

    // Songs come first from the engine; they're the ones with album art.
    final songs = _results.where((t) => t.albumArt != null).toList();
    final videos = _results.where((t) => t.albumArt == null).toList();
    final player = context.read<PlayerService>();

    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(title, style: Type.title(pal).copyWith(fontSize: 20)),
        );
    Widget row(Track t, List<Track> queue, int i) => TrackRow(
          track: t,
          onTap: () => player.playTrack(t, queue: queue, index: i),
          onMore: () => showTrackActions(context, t),
        );

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        if (songs.isNotEmpty) ...[
          section('노래'),
          for (var i = 0; i < songs.length; i++) row(songs[i], songs, i),
        ],
        if (videos.isNotEmpty) ...[
          if (songs.isNotEmpty) section('뮤직비디오 · 동영상'),
          for (var i = 0; i < videos.length; i++) row(videos[i], videos, i),
        ],
        const SizedBox(height: 16),
      ],
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
