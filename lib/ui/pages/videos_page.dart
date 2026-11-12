import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/download_service.dart';
import '../../services/engines/ytmusic_client.dart';
import '../../services/library_service.dart';
import '../../theme.dart';
import '../widgets/large_title.dart';
import '../widgets/video_widgets.dart';
import 'video_player_page.dart';

enum VideoCategory {
  all('전체', ''),
  mv('뮤직비디오', 'MV'),
  stage('음악방송', '무대 음악방송'),
  fancam('직캠', '직캠'),
  live('라이브', '라이브'),
  downloads('다운로드', '');

  const VideoCategory(this.label, this.suffix);
  final String label;
  final String suffix; // appended to the search so YouTube returns that kind

  String query(String base) => '$base $suffix'.trim();
}

/// 비디오: music videos, music-show stages, fancams and live clips — watch or
/// download. Without a search it shows the categories for the artists the
/// user listens to most.
class VideosPage extends StatefulWidget {
  const VideosPage({super.key});

  @override
  State<VideosPage> createState() => _VideosPageState();
}

class _VideosPageState extends State<VideosPage> {
  final _controller = TextEditingController();
  VideoCategory _category = VideoCategory.all;
  String _query = '';
  Future<List<YtmItem>>? _results;
  final _feed = <String, Future<List<YtmItem>>>{}; // "artist|category" → videos

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String text) {
    setState(() {
      _query = text.trim();
      _refresh();
    });
  }

  void _select(VideoCategory c) {
    setState(() {
      _category = c;
      _refresh();
    });
  }

  void _refresh() {
    _results = (_query.isEmpty || _category == VideoCategory.downloads)
        ? null
        : context.read<YtmClient>().searchVideos(_category.query(_query));
  }

  /// Most-played artists from history (one entry per artist).
  List<String> _topArtists(LibraryService library) {
    final counts = <String, int>{};
    for (final t in library.history) {
      final a = t.artist.replaceAll(RegExp(r'\s-\s*Topic$'), '').trim();
      if (a.isNotEmpty) counts[a] = (counts[a] ?? 0) + 1;
    }
    final artists = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return artists.take(3).toList();
  }

  void _open(YtmItem item) =>
      Navigator.of(context, rootNavigator: true).push(VideoPlayerPage.route(item));

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LargeTitle('비디오'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: CupertinoSearchTextField(
            controller: _controller,
            placeholder: '아티스트, 곡, 무대',
            onSubmitted: _submit,
            onSuffixTap: () {
              _controller.clear();
              _submit('');
            },
          ),
        ),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final c in VideoCategory.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _Chip(
                    label: c.label,
                    selected: c == _category,
                    onTap: () => _select(c),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_category == VideoCategory.downloads) return _downloads();
    if (_results != null) {
      return FutureBuilder<List<YtmItem>>(
        future: _results,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CupertinoActivityIndicator(radius: 14));
          }
          if (snap.hasError) return const _Message('검색에 실패했어요. 잠시 후 다시 시도해 주세요.');
          final items = snap.data ?? const [];
          if (items.isEmpty) return const _Message('결과가 없어요');
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: items.length,
            itemBuilder: (context, i) => _VideoTile(
              item: items[i],
              onTap: () => _open(items[i]),
            ),
          );
        },
      );
    }

    final artists = _topArtists(context.watch<LibraryService>());
    if (artists.isEmpty) {
      return const _Message('뮤직비디오, 음악방송 무대, 직캠을 검색해 보세요');
    }
    final ytm = context.read<YtmClient>();
    final category = _category == VideoCategory.all ? VideoCategory.mv : _category;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        for (final artist in artists)
          _Shelf(
            title: '$artist · ${category.label}',
            future: _feed.putIfAbsent(
                '$artist|${category.name}', () => ytm.searchVideos(category.query(artist))),
            onOpen: _open,
          ),
      ],
    );
  }

  Widget _downloads() {
    final videos = context.watch<DownloadService>().videos;
    if (videos.isEmpty) {
      return const _Message('영상의 다운로드 버튼으로 받으면 여기서 오프라인으로 볼 수 있어요');
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: videos.length,
      itemBuilder: (context, i) => _VideoTile(
        item: videos[i].item,
        trailing: qualityLabel(videos[i].height),
        onTap: () => _open(videos[i].item),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.item, required this.onTap, this.trailing});
  final YtmItem item;
  final VoidCallback onTap;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VideoThumb(item: item),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: VideoCaption(item: item)),
                if (trailing != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Text(trailing!, style: Type.caption(pal)),
                  ),
                SizedBox(
                  width: 36,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    icon: Icon(CupertinoIcons.ellipsis, size: 18, color: pal.secondaryLabel),
                    onPressed: () => showVideoDownloadSheet(context, item),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.future, required this.onOpen});
  final String title;
  final Future<List<YtmItem>> future;
  final ValueChanged<YtmItem> onOpen;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Text(title, style: Type.title(pal).copyWith(fontSize: 20)),
        ),
        SizedBox(
          height: 218,
          child: FutureBuilder<List<YtmItem>>(
            future: future,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CupertinoActivityIndicator());
              }
              final items = snap.data ?? const [];
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('영상을 찾지 못했어요', style: Type.sub(pal)),
                );
              }
              return ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, i) => GestureDetector(
                  onTap: () => onOpen(items[i]),
                  onLongPress: () => showVideoDownloadSheet(context, items[i]),
                  child: SizedBox(
                    width: 260,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        VideoThumb(item: items[i]),
                        const SizedBox(height: 8),
                        VideoCaption(item: items[i]),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? kAccent : pal.surfaceHigh,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Text(label,
            style: TextStyle(
                color: selected ? Colors.white : pal.label,
                fontSize: 14,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(CupertinoIcons.play_rectangle, size: 48, color: pal.secondaryLabel),
          const SizedBox(height: 12),
          Text(text, textAlign: TextAlign.center, style: Type.sub(pal)),
        ]),
      ),
    );
  }
}
