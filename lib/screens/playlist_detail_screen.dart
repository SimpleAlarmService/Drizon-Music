import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import '../services/storage_service.dart';
import '../services/player_service.dart';
import '../widgets/track_tile.dart';
import '../theme.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onChanged;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.onChanged,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late Playlist _playlist;
  late List<Track> _tracks;

  @override
  void initState() {
    super.initState();
    _playlist = widget.playlist;
    _tracks = [];
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  void _refresh() {
    final storage = context.read<StorageService>();
    final updated = storage.getPlaylists().firstWhere(
          (p) => p.id == _playlist.id,
          orElse: () => _playlist,
        );
    setState(() {
      _playlist = updated;
      _tracks = storage.getPlaylistTracks(_playlist.id);
    });
    widget.onChanged?.call();
  }

  Future<void> _removeTrack(Track track) async {
    final storage = context.read<StorageService>();
    await storage.removeTrackFromPlaylist(_playlist.id, track.videoId);
    _refresh();
  }

  Future<void> _showRenameDialog() async {
    final storage = context.read<StorageService>();
    final controller = TextEditingController(text: _playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContainerHigh,
        title: Text('이름 변경', style: headline(18)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: body(15),
          decoration: InputDecoration(
            hintText: '새 이름 입력',
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
            child: Text('저장', style: body(14, color: kPrimary)),
          ),
        ],
      ),
    );
    if (name != null && name.isNotEmpty) {
      await storage.renamePlaylist(_playlist.id, name);
      _refresh();
    }
  }

  Future<void> _confirmDelete() async {
    final storage = context.read<StorageService>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContainerHigh,
        title: Text('플레이리스트 삭제', style: headline(18)),
        content: Text(
          '"${_playlist.name}"을(를) 삭제할까요? 되돌릴 수 없습니다.',
          style: body(14, color: kOnSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('취소', style: body(14, color: kOnSurfaceVariant)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('삭제', style: body(14, color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await storage.deletePlaylist(_playlist.id);
      widget.onChanged?.call();
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final thumbUrl = _tracks.isNotEmpty ? _tracks.first.thumbnail : null;

    return Scaffold(
      backgroundColor: kSurface,
      body: CustomScrollView(
        slivers: [
          // ── Sliver app bar ───────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: kSurface,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: kOnSurface),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: kOnSurface),
                color: kSurfaceContainerHigh,
                onSelected: (value) {
                  if (value == 'rename') _showRenameDialog();
                  if (value == 'delete') _confirmDelete();
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined,
                            color: kOnSurfaceVariant, size: 18),
                        const SizedBox(width: 12),
                        Text('이름 변경', style: body(14)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        const Icon(Icons.delete_outline,
                            color: Colors.redAccent, size: 18),
                        const SizedBox(width: 12),
                        Text('삭제',
                            style: body(14, color: Colors.redAccent)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumbUrl != null)
                    CachedNetworkImage(
                      imageUrl: thumbUrl,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: kSurfaceContainer),
                      errorWidget: (_, __, ___) =>
                          Container(color: kSurfaceContainer),
                      color: Colors.black.withValues(alpha: 0.45),
                      colorBlendMode: BlendMode.darken,
                    )
                  else
                    Container(
                      color: kSurfaceContainerLow,
                      child: const Center(
                        child: Icon(Icons.queue_music,
                            color: kOutline, size: 80),
                      ),
                    ),
                  // Gradient overlay at bottom
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(20, 60, 20, 20),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, kSurface],
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_playlist.name, style: headline(28)),
                          const SizedBox(height: 4),
                          Text(
                            '${_tracks.length} 곡',
                            style: body(13, color: kOnSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Play / Shuffle buttons ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _tracks.isNotEmpty
                          ? () => player.playTrack(
                                _tracks.first,
                                queue: _tracks,
                                index: 0,
                              )
                          : null,
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient:
                              _tracks.isNotEmpty ? primaryGradient : null,
                          color: _tracks.isEmpty
                              ? kSurfaceContainerHigh
                              : null,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.play_arrow,
                              color: _tracks.isNotEmpty
                                  ? kOnPrimary
                                  : kOnSurfaceVariant,
                              size: 24,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '전체 재생',
                              style: body(
                                15,
                                weight: FontWeight.w700,
                                color: _tracks.isNotEmpty
                                    ? kOnPrimary
                                    : kOnSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _tracks.isNotEmpty
                        ? () {
                            final shuffled = List<Track>.from(_tracks)
                              ..shuffle();
                            player.playTrack(
                              shuffled.first,
                              queue: shuffled,
                              index: 0,
                            );
                          }
                        : null,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: kSurfaceContainerHigh,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.shuffle,
                        color: _tracks.isNotEmpty
                            ? kOnSurface
                            : kOutlineVariant,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Track list ───────────────────────────────────────────────────────
          if (_tracks.isEmpty)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.only(top: 60),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.music_off_outlined,
                          color: kOutline, size: 56),
                      SizedBox(height: 16),
                      Text(
                        '플레이리스트가 비어 있습니다',
                        style: TextStyle(
                            color: kOnSurfaceVariant, fontSize: 15),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '곡에서 ••• 를 눌러 추가하세요',
                        style: TextStyle(
                            color: kOutline, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) {
                  final track = _tracks[i];
                  return Dismissible(
                    key: ValueKey(track.videoId),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 24),
                      color: Colors.red.shade900,
                      child: const Icon(Icons.delete_outline,
                          color: Colors.white, size: 26),
                    ),
                    onDismissed: (_) => _removeTrack(track),
                    child: TrackTile(
                      track: track,
                      queue: _tracks,
                      queueIndex: i,
                    ),
                  );
                },
                childCount: _tracks.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}
