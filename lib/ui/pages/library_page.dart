import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/library_service.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import '../widgets/actions.dart';
import '../widgets/artwork.dart';
import '../widgets/cover_flow.dart';
import '../widgets/large_title.dart';
import '../widgets/track_row.dart';

/// 보관함: a Cover Flow of liked songs, history and playlists, with the
/// selected collection's songs listed underneath.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _flow = GlobalKey<CoverFlowState>();
  int _index = 0;

  void _play(Collection c, {bool shuffle = false}) {
    if (c.tracks.isEmpty) return;
    final player = context.read<PlayerService>();
    if (player.shuffleEnabled != shuffle) player.toggleShuffle();
    final start = shuffle ? math.Random().nextInt(c.tracks.length) : 0;
    player.playTrack(c.tracks[start], queue: c.tracks, index: start);
  }

  Future<void> _createPlaylist(int currentCount) async {
    final library = context.read<LibraryService>();
    final name = await promptText(context,
        title: '새 플레이리스트', placeholder: '플레이리스트 이름', confirm: '만들기');
    if (name == null) return;
    await library.createPlaylist(name);
    // Fly to the new cover once it has been laid out.
    WidgetsBinding.instance.addPostFrameCallback(
        (_) => _flow.currentState?.animateTo(currentCount));
  }

  void _playlistMenu(Collection c) {
    final library = context.read<LibraryService>();
    final playlist = c.playlist!;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(playlist.name),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              final name = await promptText(context,
                  title: '이름 변경', initial: playlist.name);
              if (name != null) library.renamePlaylist(playlist.id, name);
            },
            child: const Text('이름 변경'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              library.deletePlaylist(playlist.id);
            },
            child: const Text('플레이리스트 삭제'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final collections = context.watch<LibraryService>().collections;
    final index = _index.clamp(0, collections.length - 1);
    final selected = collections[index];
    final coverSize = math.min(MediaQuery.sizeOf(context).width * 0.56, 260.0);
    final player = context.read<PlayerService>();

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        LargeTitle(
          '보관함',
          trailing: IconButton(
            icon: const Icon(CupertinoIcons.add, color: kAccent, size: 28),
            onPressed: () => _createPlaylist(collections.length),
          ),
        ),
        const SizedBox(height: 12),
        CoverFlow(
          key: _flow,
          size: coverSize,
          itemCount: collections.length,
          initialIndex: index,
          itemBuilder: (_, i) => CollectionArtwork(collection: collections[i]),
          onIndexChanged: (i) => setState(() => _index = i),
          onTapCenter: (i) => _play(collections[i]),
        ),
        const SizedBox(height: 4),
        Text(
          selected.title,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Type.title(pal),
        ),
        const SizedBox(height: 4),
        Text('곡 ${selected.tracks.length}개',
            textAlign: TextAlign.center, style: Type.sub(pal)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: _PillButton(
                  icon: CupertinoIcons.play_fill,
                  label: '재생',
                  onTap: () => _play(selected),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PillButton(
                  icon: CupertinoIcons.shuffle,
                  label: '셔플',
                  onTap: () => _play(selected, shuffle: true),
                ),
              ),
              if (selected.kind == CollectionKind.playlist) ...[
                const SizedBox(width: 12),
                _PillButton(
                  icon: CupertinoIcons.ellipsis,
                  onTap: () => _playlistMenu(selected),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (selected.tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 40, 32, 0),
            child: Text(
              selected.kind == CollectionKind.playlist
                  ? '비어 있어요. 곡의 ⋯ 메뉴에서 이 플레이리스트에 추가해 보세요.'
                  : selected.kind == CollectionKind.liked
                      ? '곡의 ⋯ 메뉴에서 좋아요를 누르면 여기에 모여요.'
                      : '재생한 곡이 여기에 기록돼요.',
              textAlign: TextAlign.center,
              style: Type.sub(pal),
            ),
          )
        else
          for (var i = 0; i < selected.tracks.length; i++)
            TrackRow(
              key: ValueKey('${selected.id}:${selected.tracks[i].videoId}'),
              track: selected.tracks[i],
              onTap: () {
                if (player.shuffleEnabled) player.toggleShuffle();
                player.playTrack(selected.tracks[i],
                    queue: selected.tracks, index: i);
              },
              onMore: () => showTrackActions(context, selected.tracks[i],
                  fromPlaylist: selected.playlist),
            ),
      ],
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.icon, required this.onTap, this.label});
  final IconData icon;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Material(
      color: pal.surfaceHigh,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: label == null ? const EdgeInsets.symmetric(horizontal: 18) : null,
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: kAccent, size: 20),
              if (label != null) ...[
                const SizedBox(width: 8),
                Text(label!,
                    style: const TextStyle(
                        color: kAccent, fontSize: 17, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
