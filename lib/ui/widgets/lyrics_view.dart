import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/engines/bugs_client.dart';
import '../../services/engines/lyrics.dart';
import '../../services/metadata_service.dart';
import '../../services/player_service.dart';

/// Apple Music–style lyrics: the current line is bright, the rest dimmed, and
/// the view follows playback. Tapping a line seeks there.
class LyricsView extends StatelessWidget {
  const LyricsView({super.key, required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final meta = context.watch<MetadataService>();
    return FutureBuilder<LyricsResult>(
      future: meta.lyricsFor(track),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CupertinoActivityIndicator(color: Colors.white));
        }
        final r = snap.data!;
        if (!r.found) {
          return _Empty(
            track: track,
            message: r.error ?? '가사를 찾지 못했어요',
          );
        }
        final footer = _Footer(track: track, result: r);
        return r.lyrics!.isSynced
            ? _SyncedLyrics(
                key: ValueKey('${track.videoId}:${r.provider}:${r.sourceTitle}'),
                lyrics: r.lyrics!,
                footer: footer)
            : _PlainLyrics(text: r.lyrics!.plain!, footer: footer);
      },
    );
  }
}

class _SyncedLyrics extends StatefulWidget {
  const _SyncedLyrics({super.key, required this.lyrics, required this.footer});
  final Lyrics lyrics;
  final Widget footer;

  @override
  State<_SyncedLyrics> createState() => _SyncedLyricsState();
}

class _SyncedLyricsState extends State<_SyncedLyrics> {
  late final List<GlobalKey> _keys =
      List.generate(widget.lyrics.synced.length, (_) => GlobalKey());
  int _current = -2;
  DateTime _userScrolledAt = DateTime.fromMillisecondsSinceEpoch(0);

  // Lines are highlighted slightly early so they light up as they're sung.
  static const _lead = Duration(milliseconds: 250);

  void _follow(int index) {
    if (index < 0 || index >= _keys.length) return;
    // Don't fight the user while they're reading ahead/behind.
    if (DateTime.now().difference(_userScrolledAt) < const Duration(seconds: 3)) return;
    final ctx = _keys[index].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(ctx,
        alignment: 0.3,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final position = context.select<PlayerService, Duration>((p) => p.position);
    final index = widget.lyrics.indexAt(position + _lead);
    if (index != _current) {
      _current = index;
      WidgetsBinding.instance.addPostFrameCallback((_) => _follow(index));
    }
    final player = context.read<PlayerService>();

    return NotificationListener<UserScrollNotification>(
      onNotification: (_) {
        _userScrolledAt = DateTime.now();
        return false;
      },
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
          stops: [0, 0.08, 0.85, 1],
        ).createShader(r),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(top: 40, bottom: 260),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < widget.lyrics.synced.length; i++)
                _Line(
                  key: _keys[i],
                  text: widget.lyrics.synced[i].text,
                  state: i == index
                      ? _LineState.current
                      : i < index
                          ? _LineState.past
                          : _LineState.upcoming,
                  onTap: () => player.seekToPosition(widget.lyrics.synced[i].time),
                ),
              const SizedBox(height: 24),
              widget.footer,
            ],
          ),
        ),
      ),
    );
  }
}

enum _LineState { past, current, upcoming }

class _Line extends StatelessWidget {
  const _Line({super.key, required this.text, required this.state, required this.onTap});
  final String text;
  final _LineState state;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final current = state == _LineState.current;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          style: TextStyle(
            fontSize: 27,
            height: 1.25,
            fontWeight: FontWeight.w800,
            color: Colors.white.withValues(
                alpha: current ? 1.0 : state == _LineState.past ? 0.28 : 0.38),
          ),
          // Blank LRC lines mark instrumental breaks.
          child: Text(text.isEmpty ? '•••' : text),
        ),
      ),
    );
  }
}

class _PlainLyrics extends StatelessWidget {
  const _PlainLyrics({required this.text, required this.footer});
  final String text;
  final Widget footer;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.only(top: 24, bottom: 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(text,
                style: TextStyle(
                    fontSize: 21,
                    height: 1.5,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 24),
            footer,
          ],
        ),
      );
}

class _Footer extends StatelessWidget {
  const _Footer({required this.track, required this.result});
  final Track track;
  final LyricsResult result;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('가사 제공: ${result.provider}'
            '${result.lyrics!.isSynced ? '' : ' (싱크 없음)'}', style: style),
        if (result.sourceTitle != null)
          Text('${result.sourceTitle} – ${result.sourceArtist}', style: style),
        CupertinoButton(
          padding: const EdgeInsets.symmetric(vertical: 8),
          onPressed: () => showLyricsMatchSheet(context, track),
          child: const Text('가사가 맞지 않나요?',
              style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.track, required this.message});
  final Track track;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.quote_bubble,
                size: 44, color: Colors.white.withValues(alpha: 0.5)),
            const SizedBox(height: 12),
            Text(message,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 16)),
            CupertinoButton(
              onPressed: () => showLyricsMatchSheet(context, track),
              child: const Text('벅스에서 직접 찾기',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}

/// Search Bugs and pick the song whose lyrics should be used for [track].
Future<void> showLyricsMatchSheet(BuildContext context, Track track) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1C1C1E),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<MetadataService>(),
      child: _MatchSheet(track: track),
    ),
  );
}

class _MatchSheet extends StatefulWidget {
  const _MatchSheet({required this.track});
  final Track track;

  @override
  State<_MatchSheet> createState() => _MatchSheetState();
}

class _MatchSheetState extends State<_MatchSheet> {
  late final TextEditingController _query;
  Future<List<BugsTrack>>? _results;

  @override
  void initState() {
    super.initState();
    final q = context.read<MetadataService>().queryFor(widget.track);
    _query = TextEditingController(text: q.searchTerms.first);
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() => setState(
      () => _results = context.read<MetadataService>().searchBugs(_query.text.trim()));

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        children: [
          const SizedBox(height: 14),
          const Text('가사 찾기 · 벅스',
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: CupertinoSearchTextField(
              controller: _query,
              style: const TextStyle(color: Colors.white),
              onSubmitted: (_) => _search(),
            ),
          ),
          Expanded(
            child: FutureBuilder<List<BugsTrack>>(
              future: _results,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CupertinoActivityIndicator(color: Colors.white));
                }
                final list = snap.data ?? const [];
                if (list.isEmpty) {
                  return const Center(
                      child: Text('결과가 없어요', style: TextStyle(color: Colors.white54)));
                }
                return ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final b = list[i];
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: b.imageUrl == null
                            ? const SizedBox(width: 44, height: 44)
                            : Image.network(b.imageUrl!, width: 44, height: 44, fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44)),
                      ),
                      title: Text(b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text('${b.artist} · ${b.album}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white54)),
                      onTap: () {
                        context.read<MetadataService>().setLyricsSource(widget.track, b);
                        Navigator.pop(context);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
