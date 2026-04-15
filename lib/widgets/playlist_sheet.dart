import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/track.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';
import '../theme.dart';

/// Shows a bottom sheet to add [track] to one of the user's playlists.
/// Pass the root [BuildContext] (not the sheet's inner context) for ScaffoldMessenger.
Future<void> showAddToPlaylistSheet(
  BuildContext context,
  Track track,
  StorageService storage,
) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: kSurfaceContainer,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    isScrollControlled: true,
    builder: (_) => _AddToPlaylistSheet(
      track: track,
      storage: storage,
      rootContext: context,
    ),
  );
}

class _AddToPlaylistSheet extends StatefulWidget {
  final Track track;
  final StorageService storage;
  final BuildContext rootContext;

  const _AddToPlaylistSheet({
    required this.track,
    required this.storage,
    required this.rootContext,
  });

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  late List<Playlist> _playlists;

  @override
  void initState() {
    super.initState();
    _playlists = widget.storage.getPlaylists();
  }

  void _refresh() {
    setState(() => _playlists = widget.storage.getPlaylists());
  }

  bool _isInPlaylist(Playlist p) =>
      p.trackIds.contains(widget.track.videoId);

  void _showSnack(String message) {
    ScaffoldMessenger.of(widget.rootContext).showSnackBar(
      SnackBar(
        content: Text(message, style: body(13)),
        backgroundColor: kSurfaceContainerHigh,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showCreateDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContainerHigh,
        title: Text('새 플레이리스트', style: headline(18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: body(15),
          decoration: InputDecoration(
            hintText: '플레이리스트 이름',
            hintStyle: body(15, color: kOnSurfaceVariant),
            enabledBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kOutlineVariant),
            ),
            focusedBorder: const UnderlineInputBorder(
              borderSide: BorderSide(color: kPrimary),
            ),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소', style: body(14, color: kOnSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text('만들기', style: body(14, color: kPrimary)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      final playlist = await widget.storage.createPlaylist(name);
      await widget.storage.addTrackToPlaylist(playlist.id, widget.track);
      _refresh();
      _showSnack('"$name"에 추가되었습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: kOutlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text('플레이리스트에 저장', style: headline(18)),
          ),
          // New playlist row
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: kSurfaceContainerHigh,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.add, color: kPrimary, size: 24),
            ),
            title: Text('새 플레이리스트 만들기',
                style: body(15, weight: FontWeight.w700)),
            onTap: _showCreateDialog,
          ),
          if (_playlists.isNotEmpty)
            const Divider(color: kSurfaceContainerHighest, height: 1),
          // Existing playlists
          if (_playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Text('아직 만든 플레이리스트가 없습니다',
                  style: body(13, color: kOnSurfaceVariant)),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.4,
              ),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _playlists.length,
                itemBuilder: (_, i) {
                  final p = _playlists[i];
                  final inList = _isInPlaylist(p);
                  final thumbTrack = p.trackIds.isNotEmpty
                      ? widget.storage.getPlaylistTracks(p.id).firstOrNull
                      : null;
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 2),
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: thumbTrack != null
                          ? CachedNetworkImage(
                              imageUrl: thumbTrack.thumbnail,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                  width: 48,
                                  height: 48,
                                  color: kSurfaceContainerHigh),
                              errorWidget: (_, __, ___) => Container(
                                width: 48,
                                height: 48,
                                color: kSurfaceContainerHigh,
                                child: const Icon(Icons.music_note,
                                    color: kOutline, size: 20),
                              ),
                            )
                          : Container(
                              width: 48,
                              height: 48,
                              color: kSurfaceContainerHigh,
                              child: const Icon(Icons.queue_music,
                                  color: kOutline, size: 20),
                            ),
                    ),
                    title: Text(
                      p.name,
                      style: body(15,
                          weight: FontWeight.w700,
                          color: inList ? kPrimary : kOnSurface),
                    ),
                    subtitle: Text('${p.trackIds.length} 곡',
                        style: body(12, color: kOnSurfaceVariant)),
                    trailing: inList
                        ? const Icon(Icons.check_circle,
                            color: kPrimary, size: 22)
                        : const Icon(Icons.add_circle_outline,
                            color: kOnSurfaceVariant, size: 22),
                    onTap: inList
                        ? null
                        : () async {
                            await widget.storage
                                .addTrackToPlaylist(p.id, widget.track);
                            if (!mounted) return;
                            _refresh();
                            _showSnack('"${p.name}"에 추가되었습니다');
                            Navigator.pop(context);
                          },
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
