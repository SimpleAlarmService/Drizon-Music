import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../services/download_service.dart';
import '../../services/metadata_service.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import 'artwork.dart';

/// One song in a list: artwork, title/artist, duration and a "more" button.
/// The row that is currently playing is tinted with the accent colour.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.track,
    required this.onTap,
    this.onMore,
  });

  final Track track;
  final VoidCallback onTap;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final isCurrent = context.select<PlayerService, bool>(
        (p) => p.currentTrack?.videoId == track.videoId);
    final isPlaying =
        context.select<PlayerService, bool>((p) => isCurrent && p.isPlaying);
    final album = context.select<MetadataService, String?>((m) => m.albumFor(track));
    final dl = context.select<DownloadService, DownloadStatus>((d) => d.status(track.videoId));
    final dlProgress = context.select<DownloadService, double>((d) => d.progress(track.videoId));

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 16, top: 6, bottom: 6),
        child: Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Artwork(track: track, size: 48, radius: 6),
                if (isCurrent)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      isPlaying
                          ? CupertinoIcons.waveform
                          : CupertinoIcons.pause_fill,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.row(pal)
                        .copyWith(color: isCurrent ? kAccent : pal.label),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album == null || album.isEmpty ? track.artist : '${track.artist} · $album',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Type.sub(pal),
                  ),
                ],
              ),
            ),
            if (dl == DownloadStatus.done)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.arrow_down_circle_fill,
                    size: 15, color: pal.secondaryLabel),
              )
            else if (dl == DownloadStatus.downloading || dl == DownloadStatus.queued)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    value: dl == DownloadStatus.queued || dlProgress == 0 ? null : dlProgress,
                    strokeWidth: 2,
                    color: kAccent,
                    backgroundColor: pal.surfaceHigh,
                  ),
                ),
              )
            else if (dl == DownloadStatus.failed)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: Icon(CupertinoIcons.exclamationmark_circle, size: 15, color: kAccent),
              ),
            if (track.durationSec > 0)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(track.duration, style: Type.caption(pal)),
              ),
            SizedBox(
              width: 44,
              height: 44,
              child: onMore == null
                  ? null
                  : IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(CupertinoIcons.ellipsis,
                          size: 18, color: pal.secondaryLabel),
                      onPressed: onMore,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
