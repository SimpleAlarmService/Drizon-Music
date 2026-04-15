import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/player_service.dart';
import '../services/storage_service.dart';
import '../widgets/playlist_sheet.dart';
import '../theme.dart';

class PlayerScreen extends StatelessWidget {
  const PlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final track = player.currentTrack;

    if (track == null) {
      return Scaffold(
        backgroundColor: kSurface,
        body: Center(
          child: Text('재생 중인 곡이 없습니다', style: body(16, color: kOnSurfaceVariant)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: kSurface,
      body: Stack(
        children: [
          // ── Gradient blobs ─────────────────────────────────────────────────
          Positioned(
            top: -80,
            left: -60,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPrimary.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            bottom: 100,
            right: -80,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kPrimaryContainer.withValues(alpha: 0.06),
              ),
            ),
          ),

          // ── Main content ───────────────────────────────────────────────────
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down,
                            color: kOnSurface, size: 30),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Column(
                          children: [
                            Text('지금 재생 중', style: label(10, color: kOnSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text('Drizon', style: headline(14)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.queue_music_outlined,
                                color: kOnSurface, size: 26),
                            onPressed: () => _showQueueSheet(context, player),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_vert,
                                color: kOnSurface, size: 26),
                            onPressed: () => _showOptionsSheet(context, player),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Album art
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Glow ring
                          Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: kPrimary.withValues(alpha: 0.25),
                                  blurRadius: 60,
                                  spreadRadius: 10,
                                ),
                              ],
                            ),
                          ),
                          // Art
                          ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: CachedNetworkImage(
                              imageUrl: track.thumbnail,
                              fit: BoxFit.cover,
                              placeholder: (_, __) => Container(
                                color: kSurfaceContainer,
                                child: const Icon(Icons.music_note,
                                    color: kOutline, size: 60),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: kSurfaceContainer,
                                child: const Icon(Icons.music_note,
                                    color: kOutline, size: 60),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),

                // Title + artist + like
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: headline(24),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: body(14, color: kOnSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => player.toggleLike(track),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: player.isLiked(track.videoId)
                                ? kPrimary.withValues(alpha: 0.15)
                                : kSurfaceContainerHigh,
                          ),
                          child: Icon(
                            player.isLiked(track.videoId)
                                ? Icons.favorite
                                : Icons.favorite_border,
                            color: player.isLiked(track.videoId)
                                ? kPrimary
                                : kOnSurfaceVariant,
                            size: 22,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Progress bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _ProgressBar(player: player),
                ),

                const SizedBox(height: 24),

                // Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      // Shuffle
                      _ControlButton(
                        icon: Icons.shuffle,
                        isActive: player.shuffleEnabled,
                        onTap: player.toggleShuffle,
                      ),
                      // Prev
                      GestureDetector(
                        onTap: player.prev,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kSurfaceContainerHigh,
                          ),
                          child: const Icon(Icons.skip_previous,
                              color: kOnSurface, size: 28),
                        ),
                      ),
                      // Play / Pause
                      _PlayButton(player: player),
                      // Next
                      GestureDetector(
                        onTap: player.next,
                        child: Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: kSurfaceContainerHigh,
                          ),
                          child: const Icon(Icons.skip_next,
                              color: kOnSurface, size: 28),
                        ),
                      ),
                      // Repeat
                      _ControlButton(
                        icon: player.repeatMode == RepeatMode.one
                            ? Icons.repeat_one
                            : Icons.repeat,
                        isActive: player.repeatMode != RepeatMode.none,
                        onTap: player.cycleRepeat,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Footer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Device button
                      GestureDetector(
                        onTap: () {},
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.devices_outlined,
                              color: kOnSurfaceVariant,
                              size: 18,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'This device',
                              style: label(10, color: kOnSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      // Share button
                      GestureDetector(
                        onTap: () {},
                        child: const Icon(
                          Icons.share_outlined,
                          color: kOnSurfaceVariant,
                          size: 20,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQueueSheet(BuildContext context, PlayerService player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => _QueueSheet(
          player: player,
          scrollController: scrollCtrl,
        ),
      ),
    );
  }

  void _showOptionsSheet(BuildContext context, PlayerService player) {
    final track = player.currentTrack;
    if (track == null) return;
    final storage = context.read<StorageService>();
    showModalBottomSheet(
      context: context,
      backgroundColor: kSurfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _TrackOptionsSheet(
          track: track, player: player, storage: storage, rootContext: context),
    );
  }
}

// ── Progress Bar ──────────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  final PlayerService player;
  const _ProgressBar({required this.player});

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: kPrimary,
            inactiveTrackColor: kSurfaceContainerHigh,
            thumbColor: kPrimary,
            overlayColor: kPrimary.withValues(alpha: 0.15),
          ),
          child: Slider(
            value: player.progress,
            onChanged: player.seek,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_fmt(player.position),
                  style: label(11, color: kOnSurfaceVariant)),
              Text(_fmt(player.duration),
                  style: label(11, color: kOnSurfaceVariant)),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Play Button ───────────────────────────────────────────────────────────────

class _PlayButton extends StatelessWidget {
  final PlayerService player;
  const _PlayButton({required this.player});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: player.togglePlay,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          gradient: primaryGradient,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: kPrimary.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: player.isLoading
            ? const Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: kOnPrimary),
                ),
              )
            : Icon(
                player.isPlaying ? Icons.pause : Icons.play_arrow,
                color: kOnPrimary,
                size: 40,
              ),
      ),
    );
  }
}

// ── Small control button ──────────────────────────────────────────────────────

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          Icon(
            icon,
            color: isActive ? kPrimary : kOnSurfaceVariant,
            size: 24,
          ),
          if (isActive)
            Positioned(
              bottom: -6,
              child: Container(
                width: 5,
                height: 5,
                decoration: const BoxDecoration(
                  color: kPrimary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Queue Sheet ───────────────────────────────────────────────────────────────

class _QueueSheet extends StatelessWidget {
  final PlayerService player;
  final ScrollController scrollController;

  const _QueueSheet({required this.player, required this.scrollController});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 12),
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: kOutlineVariant,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('다음 곡', style: headline(20)),
              Text('${player.queue.length} 곡',
                  style: body(12, color: kOnSurfaceVariant)),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scrollController,
            itemCount: player.queue.length,
            itemBuilder: (_, i) {
              final t = player.queue[i];
              final isCurrent = i == player.currentIndex;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: t.thumbnail,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(color: kSurfaceContainerHigh),
                    errorWidget: (_, __, ___) =>
                        Container(color: kSurfaceContainerHigh),
                  ),
                ),
                title: Text(
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(14,
                      weight: FontWeight.w600,
                      color: isCurrent ? kPrimary : kOnSurface),
                ),
                subtitle: Text(
                  t.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: body(12, color: kOnSurfaceVariant),
                ),
                trailing: isCurrent
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('재생 중',
                            style: label(10, color: kPrimary)),
                      )
                    : null,
                onTap: () {
                  player.playTrack(t,
                      queue: player.queue.toList(), index: i);
                  Navigator.pop(context);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Track Options Bottom Sheet ────────────────────────────────────────────────

class _TrackOptionsSheet extends StatelessWidget {
  final Track track;
  final PlayerService player;
  final StorageService storage;
  final BuildContext rootContext;

  const _TrackOptionsSheet({
    required this.track,
    required this.player,
    required this.storage,
    required this.rootContext,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      (
        icon: Icons.queue_music_outlined,
        label: '대기열에 추가',
        onTap: () {
          player.addToQueue(track);
          Navigator.pop(context);
          ScaffoldMessenger.of(rootContext).showSnackBar(
            SnackBar(
              content: Text('대기열에 추가되었습니다', style: body(13)),
              backgroundColor: kSurfaceContainerHigh,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      ),
      (
        icon: Icons.playlist_add_outlined,
        label: '플레이리스트에 저장',
        onTap: () {
          Navigator.pop(context);
          showAddToPlaylistSheet(rootContext, track, storage);
        }
      ),
      (icon: Icons.share_outlined, label: '공유하기', onTap: () { Navigator.pop(context); }),
      (icon: Icons.person_outline, label: '아티스트 보기', onTap: () { Navigator.pop(context); }),
      (icon: Icons.flag_outlined,  label: '신고하기',    onTap: () { Navigator.pop(context); }),
    ];

    return SafeArea(
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
          const SizedBox(height: 20),
          // Track info header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: track.thumbnail,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    placeholder: (_, __) =>
                        Container(width: 52, height: 52, color: kSurfaceContainerHigh),
                    errorWidget: (_, __, ___) =>
                        Container(width: 52, height: 52, color: kSurfaceContainerHigh,
                            child: const Icon(Icons.music_note, color: kOutline)),
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
                        style: body(15, weight: FontWeight.w700),
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
                GestureDetector(
                  onTap: () => player.toggleLike(track),
                  child: Icon(
                    player.isLiked(track.videoId)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: player.isLiked(track.videoId)
                        ? kPrimary
                        : kOnSurfaceVariant,
                    size: 22,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(color: kSurfaceContainerHighest, height: 24),
          // Options list
          for (final opt in options)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: Icon(opt.icon, color: kOnSurfaceVariant, size: 22),
              title: Text(opt.label, style: body(15, weight: FontWeight.w600)),
              onTap: opt.onTap,
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
