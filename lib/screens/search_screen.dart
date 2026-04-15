import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../services/music_service.dart';
import '../widgets/track_tile.dart';
import '../theme.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with AutomaticKeepAliveClientMixin {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  Timer? _debounce;

  List<Track> _results = [];
  List<String> _recents = [];
  bool _loading = false;
  bool _hasSearched = false;
  String? _error;

  static const _trendingKeywords = [
    'Midnight City', '재즈 퓨전', 'K-Pop 2025',
    '비 내리는 밤', '로파이 힙합', '신스웨이브',
  ];

  @override
  void initState() {
    super.initState();
    _loadRecents();
    _ctrl.addListener(_onTextChanged);
  }

  Future<void> _loadRecents() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _recents = prefs.getStringList('oye_recent_searches') ?? [];
      });
    }
  }

  Future<void> _saveRecent(String q) async {
    final list = [q, ..._recents.where((r) => r != q)].take(8).toList();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('oye_recent_searches', list);
    if (mounted) setState(() => _recents = list);
  }

  void _onTextChanged() {
    _debounce?.cancel();
    final q = _ctrl.text.trim();
    if (q.isEmpty) {
      setState(() { _results = []; _hasSearched = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) return;
    setState(() { _loading = true; _hasSearched = true; _error = null; });
    try {
      final service = context.read<MusicService>();
      final results = await service.search(query);
      if (!mounted) return;
      setState(() { _results = results; _loading = false; });
      await _saveRecent(query);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  void _clear() {
    _ctrl.clear();
    setState(() { _results = []; _hasSearched = false; });
    _focus.requestFocus();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
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
            centerTitle: true,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                shape: BoxShape.circle, color: kSurfaceContainer),
              child: const Icon(Icons.music_note, color: kPrimary, size: 18),
            ),
            title: Text('Drizon', style: headline(20)),
            actions: const [],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Search bar ─────────────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: kSurfaceContainerLow,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: TextField(
                      controller: _ctrl,
                      focusNode: _focus,
                      style: body(17),
                      cursorColor: kPrimary,
                      decoration: InputDecoration(
                        hintText: '노래, 앨범, 또는 팟캐스트',
                        hintStyle: body(17, color: kOnSurfaceVariant),
                        border: InputBorder.none,
                        prefixIcon: const Icon(Icons.search, color: kOnSurfaceVariant),
                        suffixIcon: _ctrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, color: kOnSurfaceVariant, size: 18),
                                onPressed: _clear,
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 18),
                      ),
                      onSubmitted: _search,
                      textInputAction: TextInputAction.search,
                    ),
                  ),
                  const SizedBox(height: 24),

                  if (!_hasSearched) ...[
                    // ── Before search: recent + trending ──────────────────────
                    _SearchIdle(
                      recents: _recents,
                      trending: _trendingKeywords,
                      onTapQuery: (q) {
                        _ctrl.text = q;
                        _search(q);
                      },
                    ),
                  ] else if (_loading) ...[
                    const SizedBox(
                      height: 200,
                      child: Center(
                        child: CircularProgressIndicator(color: kPrimary),
                      ),
                    ),
                  ] else if (_error != null) ...[
                    SizedBox(
                      height: 200,
                      child: Center(
                        child: Text('검색에 실패했습니다',
                            style: body(15, color: kOnSurfaceVariant)),
                      ),
                    ),
                  ] else if (_results.isEmpty) ...[
                    SizedBox(
                      height: 200,
                      child: Center(
                        child: Text('"${_ctrl.text}" 검색 결과가 없습니다',
                            style: body(15, color: kOnSurfaceVariant)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          if (_hasSearched && !_loading && _results.isNotEmpty)
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => TrackTile(
                  track: _results[i],
                  queue: _results,
                  queueIndex: i,
                ),
                childCount: _results.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}

// ── Idle state: recents + trending ────────────────────────────────────────────

class _SearchIdle extends StatelessWidget {
  final List<String> recents;
  final List<String> trending;
  final ValueChanged<String> onTapQuery;

  const _SearchIdle({
    required this.recents,
    required this.trending,
    required this.onTapQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Row: recents + trending keywords
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Recent searches
            if (recents.isNotEmpty)
              Expanded(
                flex: 4,
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: kSurfaceContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('최근 검색어',
                          style: body(14,
                              weight: FontWeight.w700,
                              color: kOnSurfaceVariant)),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: recents
                            .take(5)
                            .map((r) => GestureDetector(
                                  onTap: () => onTapQuery(r),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: kSurfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(r, style: body(13)),
                                  ),
                                ))
                            .toList(),
                      ),
                    ],
                  ),
                ),
              ),
            if (recents.isNotEmpty) const SizedBox(width: 12),
            // Trending keywords
            Expanded(
              flex: recents.isEmpty ? 10 : 6,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: kSurfaceContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('인기 검색어',
                        style: body(14,
                            weight: FontWeight.w700,
                            color: kOnSurfaceVariant)),
                    const SizedBox(height: 12),
                    Column(
                      children: [
                        for (int i = 0; i < trending.length; i += 2)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Row(
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => onTapQuery(trending[i]),
                                    child: Row(
                                      children: [
                                        Text(
                                          '0${i + 1}',
                                          style: body(14,
                                              weight: FontWeight.w800,
                                              color: kPrimary),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(trending[i],
                                              style: body(13,
                                                  weight: FontWeight.w600),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (i + 1 < trending.length)
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () => onTapQuery(trending[i + 1]),
                                      child: Row(
                                        children: [
                                          Text(
                                            '0${i + 2}',
                                            style: body(14,
                                                weight: FontWeight.w800,
                                                color: kPrimary),
                                          ),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Text(trending[i + 1],
                                                style: body(13,
                                                    weight: FontWeight.w600),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
