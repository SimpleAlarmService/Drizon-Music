import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../../models/playlist.dart';
import '../../models/track.dart';
import '../../services/library_service.dart';
import '../../services/player_service.dart';

/// Asks for a line of text (playlist name). Returns null if cancelled/empty.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  String initial = '',
  String placeholder = '이름',
  String confirm = '확인',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showCupertinoDialog<String>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Text(title),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: CupertinoTextField(
          controller: controller,
          placeholder: placeholder,
          autofocus: true,
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
      ),
      actions: [
        CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
        CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(confirm)),
      ],
    ),
  );
  controller.dispose();
  final trimmed = result?.trim();
  return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
}

/// Bottom action sheet for a track: queue, like, add to playlist, remove.
Future<void> showTrackActions(
  BuildContext context,
  Track track, {
  Playlist? fromPlaylist,
}) {
  final player = context.read<PlayerService>();
  final library = context.read<LibraryService>();
  final liked = library.isLiked(track.videoId);

  return showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      message: Text(track.artist),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            player.addToQueue(track);
          },
          child: const Text('대기열에 추가'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            library.toggleLike(track);
          },
          child: Text(liked ? '좋아요 취소' : '좋아요'),
        ),
        CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            showPlaylistPicker(context, track);
          },
          child: const Text('플레이리스트에 추가…'),
        ),
        if (fromPlaylist != null)
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              library.removeFromPlaylist(fromPlaylist.id, track.videoId);
            },
            child: const Text('이 플레이리스트에서 삭제'),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('취소'),
      ),
    ),
  );
}

/// Choose a playlist (or create one) for [track].
Future<void> showPlaylistPicker(BuildContext context, Track track) {
  final library = context.read<LibraryService>();
  final playlists = library.playlists;

  return showCupertinoModalPopup<void>(
    context: context,
    builder: (ctx) => CupertinoActionSheet(
      title: const Text('플레이리스트에 추가'),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () async {
            Navigator.pop(ctx);
            final name = await promptText(context,
                title: '새 플레이리스트', placeholder: '플레이리스트 이름', confirm: '만들기');
            if (name == null) return;
            final p = await library.createPlaylist(name);
            await library.addToPlaylist(p.id, track);
          },
          child: const Text('새 플레이리스트…'),
        ),
        for (final p in playlists)
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              library.addToPlaylist(p.id, track);
            },
            child: Text(p.name),
          ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(ctx),
        child: const Text('취소'),
      ),
    ),
  );
}
