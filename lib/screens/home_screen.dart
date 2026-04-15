import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../services/player_service.dart';
import '../widgets/track_shelf.dart';
import '../widgets/track_tile.dart';
import '../screens/player_screen.dart';
import '../theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with AutomaticKeepAliveClientMixin {
  List<({String title, List<Track> tracks})> _shelves = [];
  List<Track> _trending = [];
  Track? _heroTrack;
  bool _loading = true;
  String? _error;

  static const _queries = [
    (title: '당신을 위한 추천', query: 'hot music 2025'),
    (title: '인기 K-Pop',           query: 'kpop 2025'),
    (title: '인기 팝송',             query: 'pop hits 2025'),
    (title: '힙합 & R&B',        query: 'hip hop rnb 2025'),
    (title: '휴식에 좋은 곡',          query: 'lofi chill music'),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final service = context.read<MusicService>();
      final results = await Future.wait([
        ...(_queries.map((q) => service.search(q.query))),
        service.search('trending music 2025'),
      ]);

      if (!mounted) return;
      final trendingResults = results.last;
      setState(() {
        _shelves = [
          for (var i = 0; i < _queries.length; i++)
            if (results[i].isNotEmpty)
              (title: _queries[i].title, tracks: results[i]),
        ];
        _trending = trendingResults.take(5).toList();
        _heroTrack = results[0].isNotEmpty ? results[0].first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: kSurface,
      body: RefreshIndicator(
        color: kPrimary,
        backgroundColor: kSurfaceContainer,
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            // ── Sticky Header ──────────────────────────────────────────────────
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
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: kSurfaceContainer,
                      gradient: primaryGradient,
                    ),
                    child: const Icon(Icons.music_note,
                        color: kOnPrimary, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Text('Drizon', style: headline(20)),
                ],
              ),
              actions: const [],
            ),

            if (_loading)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, __) => const TrackShelfSkeleton(),
                  childCount: 2,
                ),
              )
            else if (_error != null)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wifi_off, color: kOutline, size: 48),
                      const SizedBox(height: 16),
                      Text('데이터를 불러오지 못했습니다', style: headline(18)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _load,
                        child: Text('다시 시도',
                            style: body(14, color: kPrimary,
                                weight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // ── Hero Section ───────────────────────────────────────────────
              if (_heroTrack != null)
                SliverToBoxAdapter(child: _HeroSection(track: _heroTrack!)),

              // ── Recommended carousel ───────────────────────────────────────
              for (final shelf in _shelves)
                SliverToBoxAdapter(
                  child: TrackShelf(title: shelf.title, tracks: shelf.tracks),
                ),

              // ── Trending list ──────────────────────────────────────────────
              if (_trending.isNotEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                    child: Text('인기 급상승 음악', style: headline(26)),
                  ),
                ),
              if (_trending.isNotEmpty)
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => TrackTile(
                      track: _trending[i],
                      queue: _trending,
                      queueIndex: i,
                      number: i + 1,
                    ),
                    childCount: _trending.length,
                  ),
                ),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// ── Hero section with gradient overlay ────────────────────────────────────────

class _HeroSection extends StatelessWidget {
  final Track track;
  const _HeroSection({required this.track});

  @override
  Widget build(BuildContext context) {
    final player = context.read<PlayerService>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: GestureDetector(
        onTap: () {
          player.playTrack(track);
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (_, __, ___) => const PlayerScreen(),
              transitionsBuilder: (_, anim, __, child) => SlideTransition(
                position: Tween<Offset>(
                        begin: const Offset(0, 1), end: Offset.zero)
                    .animate(CurvedAnimation(
                        parent: anim, curve: Curves.easeOutCubic)),
                child: child,
              ),
              transitionDuration: const Duration(milliseconds: 400),
            ),
          );
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: 420,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Album art
                CachedNetworkImage(
                  imageUrl: track.thumbnail,
                  fit: BoxFit.cover,
                  placeholder: (_, __) =>
                      Container(color: kSurfaceContainer),
                  errorWidget: (_, __, ___) =>
                      Container(color: kSurfaceContainer),
                ),
                // Gradient overlay
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Colors.transparent, kSurface],
                      stops: [0.3, 1.0],
                    ),
                  ),
                ),
                // Content
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: kPrimaryContainer,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '주목해야 할 아티스트',
                            style: label(10, color: kOnPrimaryContainer),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          track.title,
                          style: headline(36),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          track.artist,
                          style: body(14, color: kOnSurfaceVariant),
                        ),
                        const SizedBox(height: 20),
                        GestureDetector(
                          onTap: () {
                            player.playTrack(track);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            decoration: BoxDecoration(
                              gradient: primaryGradient,
                              borderRadius: BorderRadius.circular(40),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.play_arrow,
                                    color: kOnPrimary, size: 22),
                                const SizedBox(width: 8),
                                Text('지금 듣기',
                                    style: body(14,
                                        weight: FontWeight.w700,
                                        color: kOnPrimary)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
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
