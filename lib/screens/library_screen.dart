import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/playlist.dart';
import '../services/storage_service.dart';
import '../services/player_service.dart';
import '../widgets/track_tile.dart';
import '../screens/playlist_detail_screen.dart';
import '../screens/settings_screen.dart';
import '../theme.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with AutomaticKeepAliveClientMixin {
  int _filterIndex = 0;

  static const _filters = ['플레이리스트', '좋아요 표시한 곡', '최근 재생 기록'];

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final storage = context.read<StorageService>();

    return Scaffold(
      backgroundColor: kSurface,
      body: CustomScrollView(
        slivers: [
          // ── Header ──────────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: kSurface,
            floating: true,
            snap: true,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: kSurfaceContainer),
                  child: const Icon(Icons.music_note, color: kPrimary, size: 18),
                ),
                const SizedBox(width: 12),
                Text('Drizon', style: headline(20)),
              ],
            ),
            actions: [
              if (_filterIndex == 0)
                IconButton(
                  icon: const Icon(Icons.add, color: kPrimary),
                  tooltip: '새 플레이리스트',
                  onPressed: () => _showCreatePlaylistDialog(context, storage),
                ),
              IconButton(
                icon: const Icon(Icons.settings_outlined, color: kPrimary),
                tooltip: '설정',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
              ),
            ],
          ),

          // ── Title + filter tabs ────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('보관함', style: headline(48, weight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('내 컬렉션 및 재생 기록',
                      style: body(14, color: kOnSurfaceVariant)),
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < _filters.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () => setState(() => _filterIndex = i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 9),
                                decoration: BoxDecoration(
                                  gradient: _filterIndex == i
                                      ? primaryGradient
                                      : null,
                                  color: _filterIndex != i
                                      ? kSurfaceContainerHigh
                                      : null,
                                  borderRadius: BorderRadius.circular(40),
                                ),
                                child: Text(
                                  _filters[i],
                                  style: body(13,
                                      weight: FontWeight.w700,
                                      color: _filterIndex == i
                                          ? kOnPrimary
                                          : kOnSurfaceVariant),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────────────
          if (_filterIndex == 0) ...[
            _PlaylistsTab(
              storage: storage,
              onNeedRefresh: () => setState(() {}),
            ),
          ] else if (_filterIndex == 1) ...[
            _LikedTab(storage: storage),
          ] else ...[
            _HistoryTab(storage: storage),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Future<void> _showCreatePlaylistDialog(
      BuildContext context, StorageService storage) async {
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
      await storage.createPlaylist(name);
      if (mounted) setState(() {});
    }
  }

  @override
  bool get wantKeepAlive => true;
}

// ── Playlists Tab ─────────────────────────────────────────────────────────────

class _PlaylistsTab extends StatefulWidget {
  final StorageService storage;
  final VoidCallback onNeedRefresh;

  const _PlaylistsTab({required this.storage, required this.onNeedRefresh});

  @override
  State<_PlaylistsTab> createState() => _PlaylistsTabState();
}

class _PlaylistsTabState extends State<_PlaylistsTab> {
  void _refresh() => setState(() {});

  Future<void> _openPlaylist(BuildContext context, Playlist playlist) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playlist: playlist,
          onChanged: _refresh,
        ),
      ),
    );
    _refresh();
    widget.onNeedRefresh();
  }

  Future<void> _showPlaylistOptions(
      BuildContext context, Playlist playlist) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kSurfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
                children: [
                  Text(playlist.name, style: headline(16)),
                ],
              ),
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: const Icon(Icons.edit_outlined,
                  color: kOnSurfaceVariant, size: 22),
              title: Text('이름 변경', style: body(15, weight: FontWeight.w600)),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
              leading: const Icon(Icons.delete_outline,
                  color: Colors.redAccent, size: 22),
              title: Text('삭제',
                  style: body(15,
                      weight: FontWeight.w600, color: Colors.redAccent)),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (!mounted) return;
    if (action == 'rename') {
      await _renamePlaylist(context, playlist);
    } else if (action == 'delete') {
      await _deletePlaylist(context, playlist);
    }
  }

  Future<void> _renamePlaylist(
      BuildContext context, Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
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
      await widget.storage.renamePlaylist(playlist.id, name);
      _refresh();
    }
  }

  Future<void> _deletePlaylist(
      BuildContext context, Playlist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kSurfaceContainerHigh,
        title: Text('플레이리스트 삭제', style: headline(18)),
        content: Text(
          '"${playlist.name}"을(를) 삭제할까요?',
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
      await widget.storage.deletePlaylist(playlist.id);
      _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final storage = widget.storage;
    final liked = storage.getLikedTracks();
    final playlists = storage.getPlaylists();
    final player = context.watch<PlayerService>();

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildListDelegate([
          // ── Featured: Liked Songs card ────────────────────────────────────
          GestureDetector(
            onTap: liked.isNotEmpty
                ? () => player.playTrack(liked.first,
                    queue: liked, index: 0)
                : null,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: kSurfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (liked.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: liked.first.thumbnail,
                      fit: BoxFit.cover,
                      placeholder: (_, __) =>
                          Container(color: kSurfaceContainer),
                      errorWidget: (_, __, ___) =>
                          Container(color: kSurfaceContainer),
                      color: Colors.black.withValues(alpha: 0.4),
                      colorBlendMode: BlendMode.darken,
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [kSecondaryContainer, kSurfaceContainer],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, kSurface],
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: kPrimary,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text('즐겨찾기',
                                      style: label(9, color: kOnPrimary)),
                                ),
                                const SizedBox(height: 6),
                                Text('좋아요 표시한 곡', style: headline(22)),
                                const SizedBox(height: 2),
                                Text(
                                  '${liked.length} 곡',
                                  style: body(12, color: kOnSurfaceVariant),
                                ),
                              ],
                            ),
                          ),
                          if (liked.isNotEmpty)
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                gradient: primaryGradient,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow,
                                  color: kOnPrimary, size: 22),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── User playlists ────────────────────────────────────────────────
          if (playlists.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Column(
                  children: [
                    const Icon(Icons.playlist_add,
                        color: kOutline, size: 48),
                    const SizedBox(height: 12),
                    Text('아직 플레이리스트가 없습니다',
                        style: body(14, color: kOnSurfaceVariant)),
                    const SizedBox(height: 4),
                    Text('+ 버튼을 눌러 만들어보세요',
                        style: body(12, color: kOutline)),
                  ],
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('내 플레이리스트',
                  style: body(13,
                      weight: FontWeight.w700,
                      color: kOnSurfaceVariant)),
            ),
            for (final playlist in playlists) ...[
              _PlaylistRow(
                playlist: playlist,
                storage: storage,
                onTap: () => _openPlaylist(context, playlist),
                onMoreTap: () => _showPlaylistOptions(context, playlist),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ]),
      ),
    );
  }
}

// ── Single playlist row ───────────────────────────────────────────────────────

class _PlaylistRow extends StatelessWidget {
  final Playlist playlist;
  final StorageService storage;
  final VoidCallback onTap;
  final VoidCallback onMoreTap;

  const _PlaylistRow({
    required this.playlist,
    required this.storage,
    required this.onTap,
    required this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final firstTrack = playlist.trackIds.isNotEmpty
        ? storage.getPlaylistTracks(playlist.id).firstOrNull
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: firstTrack != null
                  ? CachedNetworkImage(
                      imageUrl: firstTrack.thumbnail,
                      width: 60,
                      height: 60,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                          width: 60, height: 60, color: kSurfaceContainerHigh),
                      errorWidget: (_, __, ___) => Container(
                        width: 60,
                        height: 60,
                        color: kSurfaceContainerHigh,
                        child: const Icon(Icons.music_note,
                            color: kOutline, size: 24),
                      ),
                    )
                  : Container(
                      width: 60,
                      height: 60,
                      color: kSurfaceContainerHigh,
                      child: const Icon(Icons.queue_music,
                          color: kOutline, size: 26),
                    ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.name,
                    style: body(16, weight: FontWeight.w700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '플레이리스트 • ${playlist.trackIds.length} 곡',
                    style: label(10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: onMoreTap,
              behavior: HitTestBehavior.opaque,
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Icon(Icons.more_vert,
                    color: kOnSurfaceVariant, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Liked Songs Tab ───────────────────────────────────────────────────────────

class _LikedTab extends StatelessWidget {
  final StorageService storage;
  const _LikedTab({required this.storage});

  @override
  Widget build(BuildContext context) {
    final tracks = storage.getLikedTracks();
    if (tracks.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.favorite_border, color: kOutline, size: 56),
                SizedBox(height: 16),
                Text('아직 좋아요를 표시한 곡이 없습니다',
                    style: TextStyle(color: kOnSurfaceVariant, fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) => TrackTile(track: tracks[i], queue: tracks, queueIndex: i),
        childCount: tracks.length,
      ),
    );
  }
}

// ── History Tab ───────────────────────────────────────────────────────────────

class _HistoryTab extends StatelessWidget {
  final StorageService storage;
  const _HistoryTab({required this.storage});

  @override
  Widget build(BuildContext context) {
    final history = storage.getHistory();
    if (history.isEmpty) {
      return const SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.only(top: 80),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.history, color: kOutline, size: 56),
                SizedBox(height: 16),
                Text('재생 기록이 없습니다',
                    style: TextStyle(color: kOnSurfaceVariant, fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (_, i) =>
            TrackTile(track: history[i], queue: history, queueIndex: i),
        childCount: history.length,
      ),
    );
  }
}
