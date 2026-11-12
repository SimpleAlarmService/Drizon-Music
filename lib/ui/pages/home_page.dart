import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../services/library_service.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import '../widgets/actions.dart';
import '../widgets/artwork.dart';
import '../widgets/large_title.dart';
import 'settings_page.dart';

/// "지금 듣기": resume card plus shelves of recent and liked songs.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final library = context.watch<LibraryService>();
    final history = library.history;
    final liked = library.liked;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        LargeTitle(
          '지금 듣기',
          trailing: IconButton(
            icon: Icon(CupertinoIcons.person_crop_circle,
                size: 30, color: kAccent),
            onPressed: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(builder: (_) => const SettingsPage())),
          ),
        ),
        if (history.isEmpty && liked.isEmpty)
          _EmptyState(onSearch: onSearch)
        else ...[
          if (history.isNotEmpty) _Featured(track: history.first, queue: history),
          if (history.length > 1)
            _Shelf(title: '최근 재생', tracks: history),
          if (liked.isNotEmpty) _Shelf(title: '좋아요 표시한 곡', tracks: liked),
        ],
        SizedBox(height: 8, child: Divider(color: pal.separator.withValues(alpha: 0))),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onSearch});
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 0),
      child: Column(
        children: [
          Icon(CupertinoIcons.music_note_2, size: 64, color: pal.secondaryLabel),
          const SizedBox(height: 16),
          Text('아직 들은 음악이 없어요', style: Type.title(pal)),
          const SizedBox(height: 8),
          Text('검색에서 곡을 찾아 재생해 보세요.',
              textAlign: TextAlign.center, style: Type.sub(pal)),
          const SizedBox(height: 24),
          CupertinoButton.filled(
            onPressed: onSearch,
            child: const Text('검색하러 가기'),
          ),
        ],
      ),
    );
  }
}

/// Big "continue listening" card for the most recent track.
class _Featured extends StatelessWidget {
  const _Featured({required this.track, required this.queue});
  final Track track;
  final List<Track> queue;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: GestureDetector(
        onTap: () => context.read<PlayerService>().playTrack(track, queue: queue, index: 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('이어 듣기',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: pal.secondaryLabel)),
            const SizedBox(height: 8),
            Stack(
              alignment: Alignment.bottomLeft,
              children: [
                Artwork(track: track, radius: 12, hiRes: true),
                Positioned(
                  left: 12,
                  bottom: 12,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: const Icon(CupertinoIcons.play_fill,
                        color: Colors.black, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Type.row(pal).copyWith(fontSize: 18)),
            Text(track.artist, maxLines: 1, style: Type.sub(pal)),
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.tracks});
  final String title;
  final List<Track> tracks;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
          child: Text(title, style: Type.title(pal)),
        ),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: tracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, i) {
              final t = tracks[i];
              return GestureDetector(
                onTap: () => context
                    .read<PlayerService>()
                    .playTrack(t, queue: tracks, index: i),
                onLongPress: () => showTrackActions(context, t),
                child: SizedBox(
                  width: 150,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Artwork(track: t, size: 150, radius: 10),
                      const SizedBox(height: 8),
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.row(pal).copyWith(fontSize: 14)),
                      Text(t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Type.caption(pal)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }
}
