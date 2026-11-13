import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/track.dart';
import 'matching.dart';

enum YtmKind { song, musicVideo, video }

/// One playable search result.
class YtmItem {
  final String videoId;
  final String title;
  final String artist;
  final String? album;
  final int durationSec;
  final String thumbnail; // as returned (video frame or album art)
  final String? albumArt; // square cover, songs only
  final YtmKind kind;
  final String? views; // "조회수 80만회", videos only

  const YtmItem({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.kind,
    this.album,
    this.albumArt,
    this.durationSec = 0,
    this.views,
  });

  /// 16:9 YouTube thumbnail for video lists ('mqdefault', 'hqdefault', 'maxresdefault').
  String videoThumb([String size = 'hqdefault']) => 'https://i.ytimg.com/vi/$videoId/$size.jpg';

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnail': thumbnail,
        'kind': kind.name,
        'durationSec': durationSec,
        if (views != null) 'views': views,
      };

  factory YtmItem.fromMap(Map<dynamic, dynamic> m) => YtmItem(
        videoId: m['videoId'] as String,
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        thumbnail: m['thumbnail'] as String? ?? '',
        kind: YtmKind.values.firstWhere((k) => k.name == m['kind'], orElse: () => YtmKind.video),
        durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
        views: m['views'] as String?,
      );

  Track toTrack() => Track(
        videoId: videoId,
        title: title,
        artist: artist,
        // Keep a YouTube frame as the generic thumbnail; songs also get albumArt.
        thumbnail: 'https://i.ytimg.com/vi/$videoId/mqdefault.jpg',
        duration: Track.secToString(durationSec),
        durationSec: durationSec,
        album: album,
        albumArt: albumArt,
      );
}

class YtmException implements Exception {
  final String message;
  YtmException(this.message);
  @override
  String toString() => 'YtmException: $message';
}

/// Unofficial YouTube Music engine: talks to the same InnerTube API the
/// music.youtube.com web app uses (client WEB_REMIX). No API key or login.
class YtmClient {
  YtmClient({http.Client? client, this.hl = 'ko', this.gl = 'KR'})
      : _http = client ?? http.Client();

  final http.Client _http;
  final String hl;
  final String gl;

  static const _origin = 'https://music.youtube.com';
  // Used when the web page can't be scraped; YouTube rejects very old versions
  // silently (empty results), so the live value is preferred.
  static const fallbackClientVersion = '1.20261110.04.00';
  static const _userAgent =
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';

  String? _clientVersion;
  String? _visitorData;
  Future<void>? _bootstrapping;

  // ── Public API ───────────────────────────────────────────────────────────

  /// Songs (with album + square cover).
  ///
  /// Anonymous sessions no longer get a "Songs" filter or any song rows, so,
  /// like the iPod Composer app, this goes through albums: search albums, open
  /// the best ones and rank their tracks against the query. Falls back to the
  /// direct search if that finds nothing.
  Future<List<YtmItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    try {
      final viaAlbums = await _searchViaAlbums(q);
      if (viaAlbums.isNotEmpty) return viaAlbums;
    } catch (_) {
      // fall back to the direct search below
    }
    return _searchDirect(q);
  }

  Future<List<YtmItem>> _searchDirect(String q) async {
    final first = await _call('search', {'query': q});
    final items = parseSearch(first);

    // The "Songs" filter chip carries the params for a songs-only page. Read it
    // from the response instead of hard-coding it; it changes over time and is
    // absent in regions without the music catalogue.
    final songsParams = songsFilterParams(first);
    if (songsParams != null) {
      try {
        items.insertAll(
            0, parseSearch(await _call('search', {'query': q, 'params': songsParams})));
      } catch (_) {
        // The unfiltered results are still useful.
      }
    }
    return rank(items);
  }


  // ── Album route (works without a login) ──────────────────────────────────

  static const _albumsFilter = 'EgWKAQIYAWoQEBAQBRAKEAkQFRAEEA4QEQ==';

  static final _junk = RegExp(
      r'karaoke|カラオケ|歌っちゃ王|노래방|piano|피아노|lullaby|자장가|music box|오르골|instrumental|inst\.|cover|커버|mr\b|kpopstream|8d audio|nightcore|sped up|slowed',
      caseSensitive: false);

  static String _nrm(String s) =>
      s.toLowerCase().replaceAll(RegExp('[\\s()\\[\\]\\-_.,\'"!?·’:&/]'), '');

  static String? _pageType(Map run) => run['navigationEndpoint']?['browseEndpoint']
      ?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']?['pageType']
      as String?;

  static String? _browseId(Map run) =>
      run['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;

  static List<Map> _shelfItems(Map<String, dynamic> json) {
    final tabs = (json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?) ?? const [];
    final sections = (tabs.isEmpty
            ? null
            : tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?) ??
        const [];
    final out = <Map>[];
    for (final sec in sections) {
      final shelf = sec['musicShelfRenderer'] ?? sec['itemSectionRenderer'];
      for (final w in (shelf?['contents'] as List?) ?? const []) {
        final r = w['musicResponsiveListItemRenderer'];
        if (r is Map) out.add(r);
      }
    }
    return out;
  }

  static List<Map> _flexRuns(Map item, int i) {
    final cols = (item['flexColumns'] as List?) ?? const [];
    if (i >= cols.length) return const [];
    return _runs(cols[i]['musicResponsiveListItemFlexColumnRenderer']?['text']);
  }

  Future<List<_YtmAlbum>> _albums(String q) async {
    final json = await _call('search', {'query': q, 'params': _albumsFilter});
    final out = <_YtmAlbum>[];
    for (final it in _shelfItems(json)) {
      final id = it['navigationEndpoint']?['browseEndpoint']?['browseId'] as String?;
      if (id == null || !id.startsWith('MPRE')) continue;
      final sub = _flexRuns(it, 1);
      final artists = sub.where((r) =>
          _pageType(r) == 'MUSIC_PAGE_TYPE_ARTIST' || (_browseId(r)?.startsWith('UC') ?? false));
      out.add(_YtmAlbum(
        browseId: id,
        title: _flexRuns(it, 0).map((r) => r['text'] ?? '').join(),
        artist: artists.isNotEmpty
            ? artists.map((r) => r['text']).join(', ')
            : (sub.length > 2 ? '${sub[2]['text']}' : ''),
        artistIds: [
          for (final r in artists)
            if (_browseId(r) != null) _browseId(r)!
        ],
      ));
    }
    return out;
  }

  static double _parseCount(String txt) {
    final m = RegExp(r'([\d.,]+)\s*(억|만|천|[KMB])?', caseSensitive: false).firstMatch(txt);
    if (m == null) return 0;
    final n = double.tryParse(m.group(1)!.replaceAll(',', '')) ?? 0;
    final mul = switch ((m.group(2) ?? '').toLowerCase()) {
      '억' => 1e8,
      '만' => 1e4,
      '천' => 1e3,
      'k' => 1e3,
      'm' => 1e6,
      'b' => 1e9,
      _ => 1.0,
    };
    return n * mul;
  }

  /// The artist the query most likely refers to (top card, else first artist row).
  Future<_YtmArtist?> _topArtist(String q) async {
    final json = await _call('search', {'query': q});
    List<String> aliases(String name) {
      final m = RegExp(r'^(.*?)\s*[(（](.*?)[)）]').firstMatch(name);
      return [name, if (m?.group(1) != null) m!.group(1)!, if (m?.group(2) != null) m!.group(2)!]
          .map(_nrm)
          .where((e) => e.isNotEmpty)
          .toList();
    }

    final tabs = (json['contents']?['tabbedSearchResultsRenderer']?['tabs'] as List?) ?? const [];
    final sections = (tabs.isEmpty
            ? null
            : tabs[0]?['tabRenderer']?['content']?['sectionListRenderer']?['contents'] as List?) ??
        const [];
    for (final sec in sections) {
      final card = sec['musicCardShelfRenderer'];
      if (card is! Map) continue;
      final runs = _runs(card['title']);
      if (runs.isNotEmpty && _pageType(runs.first) == 'MUSIC_PAGE_TYPE_ARTIST') {
        final sub = _text(card['subtitle']);
        return _YtmArtist(runs.first['text'] as String, _browseId(runs.first) ?? '',
            _parseCount(sub.split('•').last), aliases(runs.first['text'] as String));
      }
      break;
    }
    for (final it in _shelfItems(json)) {
      final id = it['navigationEndpoint']?['browseEndpoint']?['browseId'] as String? ?? '';
      if (!id.startsWith('UC')) continue;
      final sub = _flexRuns(it, 1).map((r) => r['text'] ?? '').join();
      if (!RegExp(r'아티스트|artist', caseSensitive: false).hasMatch(sub)) continue;
      final name = _flexRuns(it, 0).map((r) => r['text'] ?? '').join();
      return _YtmArtist(name, id, _parseCount(sub.split('•').last), aliases(name));
    }
    return null;
  }

  Future<_YtmAlbumTracks?> _album(_YtmAlbum a) async {
    final json = await _call('browse', {'browseId': a.browseId});
    final two = json['contents']?['twoColumnBrowseResultsRenderer'];
    final header = (two?['tabs']?[0]?['tabRenderer']?['content']?['sectionListRenderer']
        ?['contents']?[0]?['musicResponsiveHeaderRenderer']) as Map?;
    Map? shelf;
    for (final c in (two?['secondaryContents']?['sectionListRenderer']?['contents'] as List?) ??
        const []) {
      if (c is Map && c['musicShelfRenderer'] is Map) {
        shelf = c['musicShelfRenderer'] as Map;
        break;
      }
    }
    if (shelf == null) return null;
    final thumbs =
        header?['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?;
    final thumb = (thumbs != null && thumbs.isNotEmpty) ? thumbs.last['url'] as String? : null;
    final albumTitle = _text(header?['title']).isNotEmpty ? _text(header?['title']) : a.title;
    final albumArtist = _runs(header?['straplineTextOne'])
        .map((r) => '${r['text'] ?? ''}')
        .where((t) => t.trim().isNotEmpty && t.trim() != '•' && t.trim() != '&' && t.trim() != ',')
        .join(', ');
    final tracks = <YtmItem>[];
    for (final w in (shelf['contents'] as List?) ?? const []) {
      final r = w['musicResponsiveListItemRenderer'];
      if (r is! Map) continue;
      final videoId = r['playlistItemData']?['videoId'] as String?;
      if (videoId == null) continue;
      final artistText = _flexRuns(r, 1)
          .map((x) => '${x['text'] ?? ''}')
          .where((t) => t.trim().isNotEmpty && t.trim() != '•')
          .join();
      final fixedList = (r['fixedColumns'] as List?) ?? const [];
      final fixedRuns = fixedList.isEmpty
          ? const <Map>[]
          : _runs(fixedList.first['musicResponsiveListItemFixedColumnRenderer']?['text']);
      final dur = _parseDuration(fixedRuns.map((x) => '${x['text'] ?? ''}').join());
      tracks.add(YtmItem(
        videoId: videoId,
        title: _flexRuns(r, 0).map((x) => x['text'] ?? '').join(),
        artist: artistText.isNotEmpty ? artistText : albumArtist,
        album: albumTitle,
        durationSec: dur,
        thumbnail: thumb ?? '',
        albumArt: thumb == null ? null : squareArt(thumb),
        kind: YtmKind.song,
      ));
    }
    return _YtmAlbumTracks(a, albumArtist.isNotEmpty ? albumArtist : a.artist, tracks);
  }

  static double _scoreAlbum(_YtmAlbum a, List<String> tokens) {
    final hay = _nrm('${a.title} ${a.artist}');
    var s = tokens.where(hay.contains).length.toDouble();
    if (_junk.hasMatch('${a.title} ${a.artist}')) s -= 2;
    return s;
  }

  /// Returns the relevance score and whether the track relates to the query.
  static (double, bool) _scoreTrack(
      YtmItem t, String albumArtist, List<String> tokens, String qn) {
    final title = _nrm(t.title);
    final rest = _nrm('${t.artist} ${t.album ?? ''} $albumArtist');
    final total = tokens.fold<int>(0, (n, k) => n + k.length);
    var inTitle = 0, inRest = 0;
    for (final k in tokens) {
      if (title.contains(k)) {
        inTitle += k.length;
      } else if (rest.contains(k)) {
        inRest += k.length;
      }
    }
    final denom = total == 0 ? 1 : total;
    var score = inTitle / denom * 2 + inRest / denom;
    final variants = <String>{
      t.title,
      for (final m in RegExp(r'[(（\[]([^)）\]]+)[)）\]]').allMatches(t.title)) m.group(1)!,
      t.title.replaceFirst(RegExp(r'[(（\[].*$'), ''),
    }.map(_nrm).where((v) => v.length >= 2);
    final titleInQuery = variants.any(qn.contains);
    if (titleInQuery) score += 3;
    final related = inTitle + inRest > 0 || titleInQuery;
    if (title == qn) score += 1;
    if (_junk.hasMatch('${t.album ?? ''} $albumArtist ${t.artist}')) score -= 2.5;
    if (RegExp(r'\(inst\.?\)|instrumental|\bmr\b|sped up|remix', caseSensitive: false)
            .hasMatch(t.title) &&
        !RegExp(r'inst|mr|remix|sped', caseSensitive: false).hasMatch(qn)) {
      score -= 1;
    }
    return (score, related);
  }

  Future<List<YtmItem>> _searchViaAlbums(String q) async {
    final results = await Future.wait<Object?>([
      _albums(q).catchError((_) => <_YtmAlbum>[]),
      _topArtist(q).catchError((_) => null),
    ]);
    final albums0 = results[0] as List<_YtmAlbum>;
    final artist = results[1] as _YtmArtist?;
    if (albums0.isEmpty) return const [];

    final tokens = q.split(RegExp(r'\s+')).map(_nrm).where((e) => e.isNotEmpty).toList();
    final qn = _nrm(q);
    final main = (artist != null && artist.listeners >= 1e5) ? artist : null;
    bool isMain(String? name, List<String> ids) {
      if (main == null) return false;
      if (ids.isNotEmpty) return ids.contains(main.browseId);
      final first = (name ?? '').split(RegExp(r',| 및 | & ')).first;
      return main.aliases.contains(_nrm(first));
    }

    var albums = albums0;
    if (main != null) {
      final restQ = tokens
          .where((k) => !main.aliases.any((a) => a.contains(k) || k.contains(a)))
          .join(' ');
      final extra = await _albums('${main.name} ${restQ.isEmpty ? q : restQ}')
          .catchError((_) => <_YtmAlbum>[]);
      final seen = albums.map((a) => a.browseId).toSet();
      albums = [...albums, ...extra.where((a) => !seen.contains(a.browseId))];
    }

    String firstArtist(String s) => _nrm(s.split(RegExp(r',| 및 | & ')).first);
    final authority = <String, int>{};
    for (final a in albums) {
      if (_junk.hasMatch('${a.title} ${a.artist}')) continue;
      authority.update(firstArtist(a.artist), (v) => v + 1, ifAbsent: () => 1);
    }

    final pick = <_YtmAlbum>[];
    void add(_YtmAlbum a) {
      if (!pick.contains(a)) pick.add(a);
    }

    List<_YtmAlbum> bestByScore(Iterable<_YtmAlbum> list, int n, {bool positiveOnly = false}) {
      final scored = [
        for (final a in list) (a, _scoreAlbum(a, tokens), albums.indexOf(a)),
      ].where((x) => !positiveOnly || x.$2 > 0).toList()
        ..sort((x, y) => y.$2 != x.$2 ? y.$2.compareTo(x.$2) : x.$3.compareTo(y.$3));
      return [for (final x in scored.take(n)) x.$1];
    }

    bestByScore(albums.where((a) => isMain(a.artist, a.artistIds)), 5).forEach(add);
    albums0.take(4).forEach(add);
    bestByScore(albums.where((a) => !pick.contains(a)), 2, positiveOnly: true).forEach(add);

    final rankOf = {for (var i = 0; i < albums0.length; i++) albums0[i].browseId: i};
    final opened = await Future.wait(
        pick.map((a) => _album(a).then<_YtmAlbumTracks?>((v) => v).catchError((_) => null)));

    final scored = <(YtmItem, double)>[];
    final seen = <String>{};
    for (final al in opened.whereType<_YtmAlbumTracks>()) {
      final rank = rankOf[al.album.browseId] ?? 10;
      final auth = (authority[firstArtist(al.album.artist)] ?? 0).clamp(0, 3);
      final albumIsMain = isMain(al.album.artist, al.album.artistIds);
      for (final t in al.tracks) {
        if (!seen.add(t.videoId)) continue;
        final (base, related) = _scoreTrack(t, al.albumArtist, tokens, qn);
        final score = base +
            auth * 0.4 +
            (4 - rank).clamp(0, 4) * 0.15 +
            (related && albumIsMain ? 3 : 0);
        scored.add((t, score));
      }
    }
    // Stable: equal scores keep album order.
    final indexed = scored.asMap().entries.toList()
      ..sort((a, b) {
        final c = b.value.$2.compareTo(a.value.$2);
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in indexed.take(40)) e.value.$1];
  }

  /// More songs to play after [seed]. YouTube Music's own radio mix is empty
  /// for anonymous sessions (only the seed comes back), so this uses the album
  /// route with the seed's artist: other songs by the same artist.
  Future<List<YtmItem>> related(YtmItem seed) async {
    final first = seed.artist.split(RegExp(r',| & ')).first.trim();
    if (first.isEmpty) return const [];
    final songs = await search(first);
    return songs.where((i) => i.videoId != seed.videoId).toList();
  }

  /// Videos only (music videos, stages, fancams…), using the "Videos" filter chip.
  Future<List<YtmItem>> searchVideos(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final first = await _call('search', {'query': q});
    final params = videosFilterParams(first);
    final items = params == null
        ? parseSearch(first)
        : parseSearch(await _call('search', {'query': q, 'params': params}));
    final seen = <String>{};
    return items.where((i) => i.kind != YtmKind.song && seen.add(i.videoId)).toList();
  }

  Future<List<String>> suggestions(String input) async {
    if (input.trim().isEmpty) return const [];
    return parseSuggestions(
        await _call('music/get_search_suggestions', {'input': input}));
  }

  // ── Transport ────────────────────────────────────────────────────────────

  Future<void> _bootstrap() => _bootstrapping ??= () async {
        try {
          final res = await _http.get(Uri.parse('$_origin/'), headers: {
            'User-Agent': _userAgent,
            'Accept-Language': hl,
          }).timeout(const Duration(seconds: 15));
          _clientVersion = RegExp(r'"INNERTUBE_CLIENT_VERSION":"([^"]+)"')
              .firstMatch(res.body)
              ?.group(1);
          _visitorData =
              RegExp(r'"VISITOR_DATA":"([^"]+)"').firstMatch(res.body)?.group(1);
        } catch (_) {
          // fall through to the fallback version
        }
        if (_clientVersion == null) _bootstrapping = null; // retry next time
      }();

  Future<Map<String, dynamic>> _call(String endpoint, Map<String, dynamic> body) async {
    await _bootstrap();
    final payload = jsonEncode({
      'context': {
        'client': {
          'clientName': 'WEB_REMIX',
          'clientVersion': _clientVersion ?? fallbackClientVersion,
          'hl': hl,
          'gl': gl,
        },
      },
      ...body,
    });
    final headers = {
      'Content-Type': 'application/json',
      'User-Agent': _userAgent,
      'Origin': _origin,
      'Referer': '$_origin/',
      if (_visitorData != null) 'X-Goog-Visitor-Id': _visitorData!,
    };
    final uri = Uri.parse('$_origin/youtubei/v1/$endpoint?prettyPrint=false');

    // Bursts of requests are sometimes answered with 403/429; back off and retry.
    for (var attempt = 0;; attempt++) {
      final res = await _http
          .post(uri, headers: headers, body: payload)
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      }
      final retryable = res.statusCode == 403 || res.statusCode == 429 || res.statusCode >= 500;
      if (!retryable || attempt >= 2) {
        throw YtmException('$endpoint failed: HTTP ${res.statusCode}');
      }
      await Future.delayed(Duration(milliseconds: 700 * (attempt + 1)));
    }
  }

  // ── Parsing (static, unit-tested against captured responses) ─────────────

  static List<YtmItem> parseSearch(Map<String, dynamic> json) {
    final out = <YtmItem>[];
    void walk(Object? node) {
      if (node is Map) {
        final list = node['musicResponsiveListItemRenderer'];
        if (list is Map) {
          final item = _parseListItem(list);
          if (item != null) out.add(item);
          return;
        }
        final card = node['musicCardShelfRenderer'];
        if (card is Map) {
          final item = _parseCard(card);
          if (item != null) out.add(item);
          // Cards can also nest list items in `contents`.
          walk(card['contents']);
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(json['contents']);
    return out;
  }

  /// Params of the "Songs" filter chip, if the response offers one.
  static String? songsFilterParams(Map<String, dynamic> json) =>
      _filterParams(json, const {'노래', '곡', 'songs', 'song'});

  /// Params of the "Videos" filter chip.
  static String? videosFilterParams(Map<String, dynamic> json) =>
      _filterParams(json, const {'동영상', 'videos', 'video'});

  static String? _filterParams(Map<String, dynamic> json, Set<String> labels) {
    String? found;
    void walk(Object? node) {
      if (found != null) return;
      if (node is Map) {
        final chip = node['chipCloudChipRenderer'];
        if (chip is Map) {
          final label = _text(chip['text']).trim().toLowerCase();
          final params = chip['navigationEndpoint']?['searchEndpoint']?['params'];
          if (labels.contains(label) && params is String) {
            found = Uri.decodeComponent(params);
          }
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(json['contents']);
    return found;
  }

  static List<String> parseSuggestions(Map<String, dynamic> json) {
    final out = <String>[];
    void walk(Object? node) {
      if (node is Map) {
        final s = node['searchSuggestionRenderer'];
        if (s is Map) {
          final q = s['navigationEndpoint']?['searchEndpoint']?['query'];
          out.add(q is String ? q : _text(s['suggestion']));
          return;
        }
        node.values.forEach(walk);
      } else if (node is List) {
        node.forEach(walk);
      }
    }

    walk(json['contents']);
    return out.where((s) => s.isNotEmpty).toList();
  }

  /// Songs → music videos → other videos; first occurrence of a video wins.
  static List<YtmItem> rank(List<YtmItem> items) {
    final seen = <String>{};
    final unique = items.where((i) => seen.add(i.videoId)).toList();
    int order(YtmKind k) => switch (k) {
          YtmKind.song => 0,
          YtmKind.musicVideo => 1,
          YtmKind.video => 2,
        };
    // List.sort isn't stable; sort by (kind, original position).
    final indexed = unique.asMap().entries.toList()
      ..sort((a, b) {
        final c = order(a.value.kind).compareTo(order(b.value.kind));
        return c != 0 ? c : a.key.compareTo(b.key);
      });
    return [for (final e in indexed) e.value];
  }

  static YtmItem? _parseListItem(Map r) {
    final columns = (r['flexColumns'] as List?) ?? const [];
    if (columns.isEmpty) return null;
    final titleRuns = _runs(columns[0]['musicResponsiveListItemFlexColumnRenderer']?['text']);
    if (titleRuns.isEmpty) return null;
    // Podcast episodes link their title to a show page instead of a player.
    if (titleRuns.first['navigationEndpoint']?['browseEndpoint'] != null) return null;

    final watch = (titleRuns.first['navigationEndpoint']?['watchEndpoint'] as Map?) ??
        (r['overlay']?['musicItemThumbnailOverlayRenderer']?['content']
            ?['musicPlayButtonRenderer']?['playNavigationEndpoint']?['watchEndpoint'] as Map?);
    final videoId = (r['playlistItemData']?['videoId'] as String?) ?? (watch?['videoId'] as String?);
    if (videoId == null) return null; // artists, albums, profiles, playlists

    final meta = <Map>[];
    for (var i = 1; i < columns.length; i++) {
      final runs = _runs(columns[i]['musicResponsiveListItemFlexColumnRenderer']?['text']);
      if (runs.isEmpty) continue;
      if (meta.isNotEmpty) meta.add({'text': ' • '});
      meta.addAll(runs);
    }
    for (final fixed in (r['fixedColumns'] as List?) ?? const []) {
      final runs = _runs(fixed['musicResponsiveListItemFixedColumnRenderer']?['text']);
      if (runs.isNotEmpty) meta..add({'text': ' • '})..addAll(runs);
    }

    return _build(
      videoId: videoId,
      title: titleRuns.map((e) => e['text'] ?? '').join(),
      videoType: watch?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']
          ?['musicVideoType'] as String?,
      metaRuns: meta,
      thumbnails: r['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?,
    );
  }

  static YtmItem? _parseCard(Map card) {
    final runs = _runs(card['title']);
    if (runs.isEmpty) return null;
    final watch = runs.first['navigationEndpoint']?['watchEndpoint'] as Map?;
    final videoId = watch?['videoId'] as String?;
    if (videoId == null) return null; // top result is an artist/album
    return _build(
      videoId: videoId,
      title: runs.map((e) => e['text'] ?? '').join(),
      videoType: watch?['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']
          ?['musicVideoType'] as String?,
      metaRuns: _runs(card['subtitle']),
      thumbnails: card['thumbnail']?['musicThumbnailRenderer']?['thumbnail']?['thumbnails'] as List?,
    );
  }

  static const _podcastLabels = {'에피소드', '팟캐스트', 'episode', 'podcast'};

  static const _typeLabels = {
    '노래', '곡', '동영상', '뮤직비디오', 'song', 'video', 'music video', 'single', 'ep',
  };

  static YtmItem? _build({
    required String videoId,
    required String title,
    required String? videoType,
    required List<Map> metaRuns,
    required List? thumbnails,
  }) {
    // Split "노래 • 아이유 • Palette • 3:42" into segments and classify each by
    // what its runs link to, not by position (the layout differs per page).
    final segments = <List<Map>>[[]];
    for (final run in metaRuns) {
      if ((run['text'] as String?)?.trim() == '•') {
        segments.add([]);
      } else {
        segments.last.add(run);
      }
    }

    String? label, artist, album, views;
    var duration = 0;
    for (final seg in segments.where((s) => s.isNotEmpty)) {
      final text = seg.map((r) => r['text'] ?? '').join().trim();
      final pageTypes = seg
          .map((r) => r['navigationEndpoint']?['browseEndpoint']
              ?['browseEndpointContextSupportedConfigs']?['browseEndpointContextMusicConfig']
              ?['pageType'])
          .whereType<String>()
          .toSet();
      if (pageTypes.any((p) => p.contains('PODCAST')) ||
          _podcastLabels.contains(text.toLowerCase())) {
        return null; // podcast episode
      }
      if (pageTypes.contains('MUSIC_PAGE_TYPE_ALBUM')) {
        album = text;
      } else if (pageTypes.contains('MUSIC_PAGE_TYPE_ARTIST') ||
          pageTypes.contains('MUSIC_PAGE_TYPE_USER_CHANNEL')) {
        artist ??= text;
      } else if (RegExp(r'^\d{1,2}(:\d{2}){1,2}$').hasMatch(text)) {
        duration = _parseDuration(text);
      } else if (label == null && artist == null && _typeLabels.contains(text.toLowerCase())) {
        label = text;
      } else if (RegExp(r'(조회수|재생|views?|plays?|회$|좋아요)', caseSensitive: false).hasMatch(text)) {
        views ??= text;
      } else {
        artist ??= text; // artist without a link (e.g. "Various Artists")
      }
    }

    final kind = switch (videoType) {
      'MUSIC_VIDEO_TYPE_ATV' => YtmKind.song,
      'MUSIC_VIDEO_TYPE_OMV' => YtmKind.musicVideo,
      null when (label == '노래' || label == '곡' || label?.toLowerCase() == 'song') => YtmKind.song,
      _ => YtmKind.video,
    };

    final thumb = (thumbnails != null && thumbnails.isNotEmpty)
        ? (thumbnails.last['url'] as String? ?? '')
        : '';
    return YtmItem(
      videoId: videoId,
      title: title,
      artist: artist ?? '',
      album: album,
      durationSec: duration,
      thumbnail: thumb,
      albumArt: kind == YtmKind.song ? squareArt(thumb) : null,
      kind: kind,
      views: kind == YtmKind.song ? null : views,
    );
  }

  /// Requests a large square rendition of a googleusercontent album cover.
  static String? squareArt(String url) {
    if (url.isEmpty || !(url.contains('googleusercontent.com') || url.contains('ggpht.com'))) {
      return null;
    }
    if (RegExp(r'=w\d+-h\d+').hasMatch(url)) {
      return url.replaceFirst(RegExp(r'=w\d+-h\d+'), '=w544-h544');
    }
    if (RegExp(r'=s\d+').hasMatch(url)) return url.replaceFirst(RegExp(r'=s\d+'), '=s544');
    return '$url=w544-h544-l90-rj';
  }

  static int _parseDuration(String s) =>
      s.split(':').fold(0, (acc, p) => acc * 60 + (int.tryParse(p) ?? 0));

  static List<Map> _runs(Object? text) =>
      ((text is Map ? text['runs'] : null) as List?)?.whereType<Map>().toList() ?? const [];

  static String _text(Object? text) => _runs(text).map((r) => r['text'] ?? '').join();

  /// For album-art matching: best song in [items] for [query], if good enough.
  static YtmItem? bestSong(SongQuery query, List<YtmItem> items, {bool artistInTerm = false}) {
    YtmItem? best;
    var bestScore = 0.0;
    final songs = items.where((i) => i.kind == YtmKind.song && i.albumArt != null);
    for (final (rank, i) in songs.indexed) {
      final s = query.score(
        candidateTitle: i.title,
        candidateArtist: i.artist,
        candidateAlbum: i.album,
        candidateDurationSec: i.durationSec,
        rankInArtistSearch: artistInTerm ? rank : null,
      );
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
    return bestScore >= matchThreshold ? best : null;
  }
}

class _YtmAlbum {
  const _YtmAlbum(
      {required this.browseId, required this.title, required this.artist, required this.artistIds});
  final String browseId, title, artist;
  final List<String> artistIds;
}

class _YtmArtist {
  const _YtmArtist(this.name, this.browseId, this.listeners, this.aliases);
  final String name, browseId;
  final double listeners;
  final List<String> aliases;
}

class _YtmAlbumTracks {
  const _YtmAlbumTracks(this.album, this.albumArtist, this.tracks);
  final _YtmAlbum album;
  final String albumArtist;
  final List<YtmItem> tracks;
}
