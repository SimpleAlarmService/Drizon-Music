import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/track.dart';
import '../../services/player_service.dart';
import '../../theme.dart';
import '../glass/liquid_glass.dart';
import 'artwork.dart';

/// Glass capsule above the tab bar. Slides in when something is queued; its
/// artwork flies into the Now Playing screen (Hero).
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key, required this.onTap});
  final VoidCallback onTap;

  static const height = 62.0;

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlayerService, Track?>((p) => p.currentTrack);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 380),
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.6), end: Offset.zero).animate(a),
          child: child,
        ),
      ),
      child: track == null ? const SizedBox(width: double.infinity) : _Bar(track: track, onTap: onTap),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.track, required this.onTap});
  final Track track;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final player = context.read<PlayerService>();
    final isPlaying = context.select<PlayerService, bool>((p) => p.isPlaying);
    final isLoading = context.select<PlayerService, bool>((p) => p.isLoading);
    final progress = context.select<PlayerService, double>((p) => p.progress);

    return GlassPressable(
      depth: 0.03,
      onTap: onTap,
      builder: (context, press, child) =>
          LiquidGlass.capsule(highlight: 1 + press * 0.5, child: child),
      child: SizedBox(
        height: MiniPlayer.height,
        child: Stack(children: [
          Row(children: [
            const SizedBox(width: 9),
            Hero(
              tag: 'artwork-${track.videoId}',
              child: Artwork(track: track, size: 44, radius: 10),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.centerLeft,
                  children: [...previous, ?current],
                ),
                transitionBuilder: (c, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                    child: c,
                  ),
                ),
                child: Column(
                  key: ValueKey(track.videoId),
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.row(pal).copyWith(fontSize: 15)),
                    Text(track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Type.caption(pal)),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: 44,
              child: isLoading
                  ? const CupertinoActivityIndicator()
                  : GlassPressable(
                      depth: 0.15,
                      onTap: player.togglePlay,
                      child: SizedBox(
                        height: 44,
                        child: Center(child: PlayPauseIcon(playing: isPlaying, color: pal.label, size: 26)),
                      ),
                    ),
            ),
            GlassPressable(
              depth: 0.15,
              onTap: player.next,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(CupertinoIcons.forward_fill, color: pal.label, size: 24),
              ),
            ),
            const SizedBox(width: 6),
          ]),
          // Hairline progress along the bottom of the capsule.
          Positioned(
            left: 24,
            right: 24,
            bottom: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                color: kAccent,
                backgroundColor: pal.label.withValues(alpha: 0.08),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Play/pause glyph that morphs (scale + rotate + fade) between states.
class PlayPauseIcon extends StatelessWidget {
  const PlayPauseIcon({super.key, required this.playing, required this.color, this.size = 28});
  final bool playing;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: Curves.easeOutBack,
        transitionBuilder: (child, a) => RotationTransition(
          turns: Tween(begin: -0.12, end: 0.0).animate(a),
          child: ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: child)),
        ),
        child: Icon(
          playing ? CupertinoIcons.pause_fill : CupertinoIcons.play_fill,
          key: ValueKey(playing),
          color: color,
          size: size,
        ),
      );
}
