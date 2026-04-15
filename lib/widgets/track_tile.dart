import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../widgets/playlist_sheet.dart';
import '../theme.dart';

class TrackTile extends StatelessWidget {
  final Track track;
  final List<Track>? queue;
  final int? queueIndex;
  final int? number;
  final VoidCallback? onTap;

  const TrackTile({
    super.key,
    required this.track,
    this.queue,
    this.queueIndex,
    this.number,
    this.onTap,
  });

  void _showOptions(BuildContext context) {
    final player = context.read<PlayerService>();
    final storage = context.read<StorageService>();
    final isLiked = player.isLiked(track.videoId);

    showModalBottomSheet(
      context: context,
      backgroundColor: kSurfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: kOutlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Track info header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: CachedNetworkImage(
                      imageUrl: track.thumbnail,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          width: 48, height: 48, color: kSurfaceContainerHigh),
                      errorWidget: (_, __, ___) => Container(
                        width: 48,
                        height: 48,
                        color: kSurfaceContainerHigh,
                        child: const Icon(Icons.music_note,
                            color: kOutline, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: body(14, weight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: label(10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: kSurfaceContainerHighest, height: 1),
            // Options
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: const Icon(Icons.queue_music_outlined,
                  color: kOnSurfaceVariant, size: 22),
              title: Text('대기열에 추가',
                  style: body(15, weight: FontWeight.w600)),
              onTap: () {
                player.addToQueue(track);
                Navigator.pop(sheetCtx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('대기열에 추가되었습니다', style: body(13)),
                    backgroundColor: kSurfaceContainerHigh,
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: const Icon(Icons.playlist_add_outlined,
                  color: kOnSurfaceVariant, size: 22),
              title: Text('플레이리스트에 저장',
                  style: body(15, weight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(sheetCtx);
                showAddToPlaylistSheet(context, track, storage);
              },
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? kPrimary : kOnSurfaceVariant,
                size: 22,
              ),
              title: Text(
                isLiked ? '좋아요 취소' : '좋아요',
                style: body(15, weight: FontWeight.w600),
              ),
              onTap: () {
                player.toggleLike(track);
                Navigator.pop(sheetCtx);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final isCurrent = player.currentTrack?.videoId == track.videoId;

    return GestureDetector(
      onTap: onTap ??
          () {
            final q = queue ?? [track];
            final idx = queueIndex ??
                q.indexWhere((t) => t.videoId == track.videoId);
            player.playTrack(track, queue: q, index: idx < 0 ? 0 : idx);
          },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isCurrent ? kSurfaceContainerHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            // Number or thumbnail
            if (number != null)
              SizedBox(
                width: 32,
                child: Text(
                  number.toString().padLeft(2, '0'),
                  style: headline(18,
                      weight: FontWeight.w800,
                      color: isCurrent ? kPrimary : kOutlineVariant),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: track.thumbnail,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        width: 54,
                        height: 54,
                        color: kSurfaceContainerHigh,
                        child: const Icon(Icons.music_note,
                            color: kOutline, size: 20),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        width: 54,
                        height: 54,
                        color: kSurfaceContainerHigh,
                        child: const Icon(Icons.music_note,
                            color: kOutline, size: 20),
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        width: 54,
                        height: 54,
                        color: Colors.black54,
                        child: const Icon(Icons.graphic_eq,
                            color: kPrimary, size: 20),
                      ),
                  ],
                ),
              ),
            // Thumbnail after number
            if (number != null) ...[
              const SizedBox(width: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: CachedNetworkImage(
                  imageUrl: track.thumbnail,
                  width: 54,
                  height: 54,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => Container(
                      width: 54, height: 54, color: kSurfaceContainerHigh),
                  errorWidget: (_, __, ___) => Container(
                      width: 54, height: 54, color: kSurfaceContainerHigh),
                ),
              ),
            ],
            const SizedBox(width: 16),
            // Title / Artist
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(15,
                        weight: FontWeight.w700,
                        color: isCurrent ? kPrimary : kOnSurface),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    track.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: body(12, color: kOnSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Duration
            Text(
              track.duration,
              style: body(12, color: kOnSurfaceVariant),
            ),
            const SizedBox(width: 4),
            // More options button
            GestureDetector(
              onTap: () => _showOptions(context),
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.more_vert,
                    color: kOnSurfaceVariant, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
