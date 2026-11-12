import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import 'artwork.dart';

/// Floating mini player shown above the tab bar while something is queued.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final track =
        context.select<PlayerService, Track?>((p) => p.currentTrack);
    if (track == null) return const SizedBox.shrink();

    final pal = context.pal;
    final player = context.read<PlayerService>();
    final isPlaying = context.select<PlayerService, bool>((p) => p.isPlaying);
    final isLoading = context.select<PlayerService, bool>((p) => p.isLoading);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Material(
            color: pal.surfaceHigh.withValues(alpha: 0.88),
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 58,
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Artwork(track: track, size: 42, radius: 6),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.row(pal).copyWith(fontSize: 15),
                      ),
                    ),
                    SizedBox(
                      width: 44,
                      child: isLoading
                          ? const CupertinoActivityIndicator()
                          : IconButton(
                              padding: EdgeInsets.zero,
                              icon: Icon(
                                isPlaying
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill,
                                color: pal.label,
                                size: 24,
                              ),
                              onPressed: player.togglePlay,
                            ),
                    ),
                    IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(CupertinoIcons.forward_fill,
                          color: pal.label, size: 24),
                      onPressed: player.next,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
