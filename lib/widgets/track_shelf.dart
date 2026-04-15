import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../theme.dart';

class TrackShelf extends StatelessWidget {
  final String title;
  final List<Track> tracks;

  const TrackShelf({super.key, required this.title, required this.tracks});

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: headline(26),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 8),
              Text('See All',
                  style: body(13, weight: FontWeight.w700, color: kPrimary)),
            ],
          ),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: tracks.length,
            itemBuilder: (ctx, i) =>
                _TrackCard(track: tracks[i], queue: tracks, index: i),
          ),
        ),
      ],
    );
  }
}

class _TrackCard extends StatelessWidget {
  final Track track;
  final List<Track> queue;
  final int index;

  const _TrackCard({required this.track, required this.queue, required this.index});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final isCurrent = player.currentTrack?.videoId == track.videoId;

    return GestureDetector(
      onTap: () => player.playTrack(track, queue: queue, index: index),
      child: Container(
        width: 148,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(
                    imageUrl: track.thumbnail,
                    width: 148,
                    height: 148,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                      width: 148, height: 148,
                      color: kSurfaceContainer,
                      child: const Icon(Icons.music_note, color: kOutline, size: 32),
                    ),
                    errorWidget: (_, __, ___) => Container(
                      width: 148, height: 148,
                      color: kSurfaceContainer,
                      child: const Icon(Icons.music_note, color: kOutline, size: 32),
                    ),
                  ),
                ),
                // Hover-style play overlay
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      color: isCurrent ? Colors.black54 : Colors.transparent,
                      child: isCurrent
                          ? Center(
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: primaryGradient,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.graphic_eq,
                                    color: kOnPrimary, size: 22),
                              ),
                            )
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(13, weight: FontWeight.w700,
                  color: isCurrent ? kPrimary : kOnSurface),
            ),
            const SizedBox(height: 2),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body(11, color: kOnSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Skeleton loading ──────────────────────────────────────────────────────────

class TrackShelfSkeleton extends StatelessWidget {
  const TrackShelfSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
          child: Container(width: 160, height: 22,
              decoration: _sk.copyWith(borderRadius: BorderRadius.circular(6))),
        ),
        SizedBox(
          height: 200,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            scrollDirection: Axis.horizontal,
            itemCount: 4,
            itemBuilder: (_, __) => Container(
              width: 148,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 148, height: 148,
                    decoration: _sk.copyWith(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  const SizedBox(height: 8),
                  Container(width: 120, height: 13,
                      decoration: _sk.copyWith(borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 4),
                  Container(width: 80, height: 11,
                      decoration: _sk.copyWith(borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static BoxDecoration get _sk =>
      const BoxDecoration(color: kSurfaceContainerHigh);
}
