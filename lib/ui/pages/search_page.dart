import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../services/music_service.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import '../widgets/actions.dart';
import '../widgets/large_title.dart';
import '../widgets/track_row.dart';

class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0; // discards responses that arrive out of order

  List<Track> _results = const [];
  bool _loading = false;
  String? _error;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () => _search(text));
  }

  Future<void> _search(String text) async {
    _debounce?.cancel();
    final q = text.trim();
    if (q == _query && _error == null) return;
    final id = ++_requestId;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
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
    final pal = context.pal;
    return Column(
      children: [
        const Align(alignment: Alignment.centerLeft, child: LargeTitle('검색')),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: CupertinoSearchTextField(
            controller: _controller,
            placeholder: '아티스트, 곡',
            onChanged: _onChanged,
            onSubmitted: _search,
            onSuffixTap: () {
              _controller.clear();
              _search('');
            },
          ),
        ),
        Expanded(child: _body(pal)),
      ],
    );
  }

  Widget _body(Palette pal) {
    if (_loading) return const Center(child: CupertinoActivityIndicator(radius: 14));
    if (_error != null) {
      return _Message(icon: CupertinoIcons.exclamationmark_circle, text: _error!);
    }
    if (_query.isEmpty) {
      return const _Message(
          icon: CupertinoIcons.search, text: '좋아하는 음악을 검색해 보세요');
    }
    if (_results.isEmpty) {
      return const _Message(icon: CupertinoIcons.music_note, text: '결과가 없어요');
    }
    final player = context.read<PlayerService>();
    return ListView.builder(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final t = _results[i];
        return TrackRow(
          track: t,
          onTap: () => player.playTrack(t, queue: _results, index: i),
          onMore: () => showTrackActions(context, t),
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
