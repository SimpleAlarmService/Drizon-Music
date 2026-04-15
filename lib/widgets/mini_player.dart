import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../screens/player_screen.dart';
import '../theme.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final track = player.currentTrack;
    if (track == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (_, __, ___) => const PlayerScreen(),
          transitionsBuilder: (_, anim, __, child) => SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
                .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
            child: child,
          ),
          transitionDuration: const Duration(milliseconds: 400),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        decoration: BoxDecoration(
          color: kSurfaceVariant.withValues(alpha: 0.8),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: track.thumbnail,
                        width: 46,
                        height: 46,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          width: 46, height: 46, color: kSurfaceContainerHigh,
                          child: const Icon(Icons.music_note, color: kOutline, size: 18),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          width: 46, height: 46, color: kSurfaceContainerHigh,
                          child: const Icon(Icons.music_note, color: kOutline, size: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Title / Artist
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: body(13, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: label(9, color: kOnSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    // Like button
                    GestureDetector(
                      onTap: () => player.toggleLike(track),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          player.isLiked(track.videoId)
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: player.isLiked(track.videoId) ? kPrimary : kOnSurface,
                          size: 22,
                        ),
                      ),
                    ),
                    // Play/Pause button
                    GestureDetector(
                      onTap: player.togglePlay,
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          gradient: primaryGradient,
                          shape: BoxShape.circle,
                        ),
                        child: player.isLoading
                            ? const Center(
                                child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kOnPrimary),
                                ),
                              )
                            : Icon(
                                player.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: kOnPrimary,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              // Progress bar
              Container(
                height: 2,
                width: double.infinity,
                color: kSurfaceContainerHighest,
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: player.progress.clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: primaryGradient,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
