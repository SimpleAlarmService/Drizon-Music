import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/cupertino.dart' hide RepeatMode;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:provider/provider.dart';
import '../../models/track.dart';
import '../../services/download_service.dart';
import '../../services/library_service.dart';
import '../../services/metadata_service.dart';
import '../../services/player_service.dart';
import '../widgets/actions.dart';
import '../widgets/artwork.dart';
import '../widgets/lyrics_view.dart';

/// Full-screen player: blurred artwork backdrop, big cover that shrinks while
/// paused, scrubber, transport controls and the queue sheet.
class NowPlayingPage extends StatefulWidget {
  const NowPlayingPage({super.key});

  static Route<void> route() => CupertinoPageRoute<void>(
      fullscreenDialog: true, builder: (_) => const NowPlayingPage());

  @override
  State<NowPlayingPage> createState() => _NowPlayingPageState();
}

class _NowPlayingPageState extends State<NowPlayingPage> {
  bool _lyrics = false;

  @override
  Widget build(BuildContext context) {
    final track = context.select<PlayerService, Track?>((p) => p.currentTrack);
    if (track == null) return const Scaffold(backgroundColor: Colors.black);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _Backdrop(track: track),
          SafeArea(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragEnd: (d) {
                if ((d.primaryVelocity ?? 0) > 600) Navigator.of(context).pop();
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    _Grabber(onTap: () => Navigator.of(context).pop()),
                    if (_lyrics) ...[
                      const SizedBox(height: 12),
                      _TitleRow(track: track, compact: true),
                      Expanded(child: LyricsView(track: track)),
                    ] else ...[
                      const SizedBox(height: 20),
                      Expanded(child: _BigArtwork(track: track)),
                      const SizedBox(height: 28),
                      _TitleRow(track: track),
                    ],
                    const SizedBox(height: 18),
                    const _Scrubber(),
                    const SizedBox(height: 14),
                    const _Controls(),
                    const SizedBox(height: 18),
                    _BottomBar(
                      lyrics: _lyrics,
                      onToggleLyrics: () => setState(() => _lyrics = !_lyrics),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Backdrop extends StatelessWidget {
  const _Backdrop({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final image = context.select<MetadataService, String?>((m) => m.artFor(track)) ??
        track.thumbnail;
    final local = context.select<DownloadService, String?>((d) => d.localCover(track.videoId));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Stack(
        key: ValueKey(local ?? image),
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF111111)),
          if (local != null || image.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 50, sigmaY: 50),
              child: Transform.scale(
                scale: 1.8,
                child: local != null
                    ? Image.file(File(local), fit: BoxFit.cover)
                    : CachedNetworkImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
              ),
            ),
          ColoredBox(color: Colors.black.withValues(alpha: 0.42)),
        ],
      ),
    );
  }
}

class _Grabber extends StatelessWidget {
  const _Grabber({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 40),
          child: Container(
            width: 40,
            height: 5,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      );
}

class _BigArtwork extends StatelessWidget {
  const _BigArtwork({required this.track});
  final Track track;

  @override
  Widget build(BuildContext context) {
    final playing = context.select<PlayerService, bool>((p) => p.isPlaying);
    return Center(
      child: AspectRatio(
        aspectRatio: 1,
        child: AnimatedScale(
          scale: playing ? 1.0 : 0.84,
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutCubic,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: playing ? 0.5 : 0.25),
                  blurRadius: playing ? 40 : 16,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Artwork(track: track, radius: 14, hiRes: true),
          ),
        ),
      ),
    );
  }
}

class _TitleRow extends StatelessWidget {
  const _TitleRow({required this.track, this.compact = false});
  final Track track;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final liked = context
        .select<LibraryService, bool>((l) => l.isLiked(track.videoId));
    return Row(
      children: [
        if (compact) ...[
          Artwork(track: track, size: 52, radius: 6),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 17 : 22,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.65),
                      fontSize: compact ? 15 : 19)),
            ],
          ),
        ),
        IconButton(
          icon: Icon(liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              color: liked ? const Color(0xFFFA2D48) : Colors.white, size: 26),
          onPressed: () => context.read<LibraryService>().toggleLike(track),
        ),
        IconButton(
          icon: const Icon(CupertinoIcons.ellipsis_circle,
              color: Colors.white, size: 26),
          onPressed: () => showTrackActions(context, track),
        ),
      ],
    );
  }
}

class _Scrubber extends StatefulWidget {
  const _Scrubber();

  @override
  State<_Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends State<_Scrubber> {
  double? _drag; // fraction while the finger is down

  static String _fmt(Duration d) {
    final s = d.inSeconds.clamp(0, 359999);
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final position = context.select<PlayerService, Duration>((p) => p.position);
    final duration = context.select<PlayerService, Duration>((p) => p.duration);
    final total = duration.inMilliseconds;
    final fraction = total == 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    final value = _drag ?? fraction;
    final shownPos = Duration(milliseconds: (value * total).round());
    final remaining = duration - shownPos;
    final label = TextStyle(
        color: Colors.white.withValues(alpha: 0.6),
        fontSize: 12,
        fontFeatures: const [FontFeature.tabularFigures()]);

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: _drag == null ? 4 : 8,
            activeTrackColor: Colors.white.withValues(alpha: 0.9),
            inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
            thumbShape: SliderComponentShape.noThumb,
            overlayShape: SliderComponentShape.noOverlay,
            trackShape: const RoundedRectSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            onChanged: total == 0 ? null : (v) => setState(() => _drag = v),
            onChangeEnd: (v) {
              context.read<PlayerService>().seek(v);
              setState(() => _drag = null);
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(shownPos), style: label),
              Text(total == 0 ? '' : '-${_fmt(remaining)}', style: label),
            ],
          ),
        ),
      ],
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    final playing = context.select<PlayerService, bool>((p) => p.isPlaying);
    final loading = context.select<PlayerService, bool>((p) => p.isLoading);
    final shuffle = context.select<PlayerService, bool>((p) => p.shuffleEnabled);
    final repeat = context.select<PlayerService, RepeatMode>((p) => p.repeatMode);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _Toggle(
            icon: CupertinoIcons.shuffle,
            active: shuffle,
            onTap: player.toggleShuffle),
        IconButton(
          iconSize: 38,
          color: Colors.white,
          icon: const Icon(CupertinoIcons.backward_fill),
          onPressed: player.prev,
        ),
        SizedBox(
          width: 76,
          height: 76,
          child: loading
              ? const CupertinoActivityIndicator(radius: 16, color: Colors.white)
              : IconButton(
                  iconSize: 58,
                  color: Colors.white,
                  icon: Icon(playing
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill),
                  onPressed: player.togglePlay,
                ),
        ),
        IconButton(
          iconSize: 38,
          color: Colors.white,
          icon: const Icon(CupertinoIcons.forward_fill),
          onPressed: player.next,
        ),
        _Toggle(
            icon: repeat == RepeatMode.one
                ? CupertinoIcons.repeat_1
                : CupertinoIcons.repeat,
            active: repeat != RepeatMode.none,
            onTap: player.cycleRepeat),
      ],
    );
  }
}

/// Round toggle that fills white when active (Apple Music style).
class _Toggle extends StatelessWidget {
  const _Toggle({required this.icon, required this.active, required this.onTap});
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: active ? Colors.white.withValues(alpha: 0.9) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon,
            size: 22,
            color: active ? Colors.black : Colors.white.withValues(alpha: 0.7)),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.lyrics, required this.onToggleLyrics});
  final bool lyrics;
  final VoidCallback onToggleLyrics;

  @override
  Widget build(BuildContext context) {
    final error = context.select<PlayerService, String?>((p) => p.errorMessage);
    return Column(
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(error,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12)),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: '가사',
              icon: Icon(
                  lyrics ? CupertinoIcons.quote_bubble_fill : CupertinoIcons.quote_bubble,
                  color: lyrics ? Colors.white : Colors.white.withValues(alpha: 0.8),
                  size: 26),
              onPressed: onToggleLyrics,
            ),
            IconButton(
              icon: Icon(CupertinoIcons.list_bullet,
                  color: Colors.white.withValues(alpha: 0.8), size: 26),
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) => const _QueueSheet(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final queue = player.queue;
    final current = player.currentIndex;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Material(
            color: const Color(0xE61C1C1E),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(3)),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Text('재생 대기열',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: ReorderableListView.builder(
                    scrollController: scroll,
                    itemCount: queue.length,
                    onReorder: player.reorderQueue,
                    buildDefaultDragHandles: true,
                    itemBuilder: (context, i) {
                      final t = queue[i];
                      final isCurrent = i == current;
                      final row = ListTile(
                        key: ValueKey('${t.videoId}#$i'),
                        leading: Artwork(track: t, size: 44, radius: 6),
                        title: Text(t.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: isCurrent
                                    ? const Color(0xFFFA2D48)
                                    : Colors.white)),
                        subtitle: Text(t.artist,
                            maxLines: 1,
                            style: const TextStyle(color: Colors.white54)),
                        onTap: () =>
                            player.playTrack(t, queue: queue, index: i),
                      );
                      if (isCurrent) return row;
                      return Dismissible(
                        key: ValueKey('dismiss-${t.videoId}#$i'),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: const Color(0xFFFA2D48),
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 20),
                          child: const Icon(CupertinoIcons.delete,
                              color: Colors.white),
                        ),
                        onDismissed: (_) => player.removeFromQueue(i),
                        child: row,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
