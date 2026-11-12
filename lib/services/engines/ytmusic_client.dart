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

  const YtmItem({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    required this.kind,
    this.album,
    this.albumArt,
    this.durationSec = 0,
  });

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

  /// Songs first (with album + square cover), then music videos, then other videos.
  Future<List<YtmItem>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
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
  static String? songsFilterParams(Map<String, dynamic> json) {
    const labels = {'노래', '곡', 'songs', 'song'};
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

    String? label, artist, album;
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
        // view / play counts
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
