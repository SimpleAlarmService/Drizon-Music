import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lyrics.dart';
import 'matching.dart';

/// A track in the Bugs catalogue.
class BugsTrack {
  final String id;
  final String title;
  final String artist;
  final String album;
  final String? imageUrl; // 500px album cover

  const BugsTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() =>
      {'id': id, 'title': title, 'artist': artist, 'album': album, 'imageUrl': imageUrl};

  factory BugsTrack.fromMap(Map<dynamic, dynamic> m) => BugsTrack(
        id: m['id'] as String,
        title: m['title'] as String? ?? '',
        artist: m['artist'] as String? ?? '',
        album: m['album'] as String? ?? '',
        imageUrl: m['imageUrl'] as String?,
      );
}

/// Unofficial client for Bugs (music.bugs.co.kr): track search and lyrics.
class BugsClient {
  BugsClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _host = 'https://music.bugs.co.kr';
  static const _headers = {
    'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36',
    'Referer': 'https://music.bugs.co.kr/',
  };

  Future<List<BugsTrack>> search(String query) async {
    final uri = Uri.parse('$_host/search/track').replace(queryParameters: {'q': query});
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) throw Exception('Bugs search failed: HTTP ${res.statusCode}');
    return parseSearch(utf8.decode(res.bodyBytes));
  }

  /// Synced lyrics if Bugs has them, otherwise plain lyrics, otherwise null.
  Future<Lyrics?> lyrics(String trackId) async {
    final synced = await _lyricsRaw('T', trackId);
    if (synced != null && synced.isNotEmpty) {
      final lines = Lyrics.parseBugsSynced(synced);
      if (lines.isNotEmpty) return Lyrics(synced: lines);
    }
    final plain = await _lyricsRaw('N', trackId);
    if (plain != null && plain.trim().isNotEmpty) {
      return Lyrics(plain: plain.replaceAll('\r\n', '\n').trim());
    }
    return null;
  }

  Future<String?> _lyricsRaw(String kind, String trackId) async {
    final res = await _http
        .get(Uri.parse('$_host/player/lyrics/$kind/$trackId'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    return body is Map ? body['lyrics'] as String? : null;
  }

  /// Best Bugs track for [query], trying each search term until one scores well.
  /// Returns the match (or null) plus every candidate seen, for manual picking.
  Future<(BugsTrack?, List<BugsTrack>)> match(SongQuery query) async {
    final seen = <String, BugsTrack>{};
    final terms = query.searchTerms;
    for (var i = 0; i < terms.length; i++) {
      final results = await search(terms[i]);
      for (final r in results) {
        seen.putIfAbsent(r.id, () => r);
      }
      final best = pickBest(query, results, artistInTerm: query.termHasArtist(i));
      if (best != null) return (best, seen.values.toList());
    }
    return (null, seen.values.toList());
  }

  static BugsTrack? pickBest(SongQuery query, List<BugsTrack> candidates,
      {bool artistInTerm = false}) {
    BugsTrack? best;
    var bestScore = 0.0;
    for (final (rank, c) in candidates.indexed) {
      final s = query.score(
        candidateTitle: c.title,
        candidateArtist: c.artist,
        candidateAlbum: c.album,
        rankInArtistSearch: artistInTerm ? rank : null,
      );
      if (s > bestScore) {
        bestScore = s;
        best = c;
      }
    }
    return bestScore >= matchThreshold ? best : null;
  }

  // ── HTML parsing ─────────────────────────────────────────────────────────

  static final _row = RegExp(r'<tr[^>]*rowType="track"[^>]*>(.*?)</tr>', dotAll: true);

  static List<BugsTrack> parseSearch(String html) {
    final out = <BugsTrack>[];
    for (final m in _row.allMatches(html)) {
      final row = m.group(0)!;
      final id = RegExp(r'trackId="(\d+)"').firstMatch(row)?.group(1);
      if (id == null) continue;

      final titleBlock = RegExp(r'<p class="title"[^>]*>(.*?)</p>', dotAll: true)
          .firstMatch(row)
          ?.group(1);
      final title = titleBlock == null
          ? null
          : RegExp(r'<a[^>]*title="([^"]*)"', dotAll: true).firstMatch(titleBlock)?.group(1);
      if (title == null) continue;

      final artistBlock =
          RegExp(r'<p class="artist">(.*?)</p>', dotAll: true).firstMatch(row)?.group(1) ?? '';
      final artistNames = RegExp(r'<a[^>]*>([^<]+)</a>')
          .allMatches(artistBlock)
          .map((a) => a.group(1)!.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final artist = artistNames.isNotEmpty
          ? artistNames.join(', ')
          : artistBlock.replaceAll(RegExp(r'<[^>]+>'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

      final album = RegExp(r'class="album" title="([^"]*)"').firstMatch(row)?.group(1) ?? '';
      final img = RegExp(r'<img src="(https://image\.bugsm\.co\.kr/album/images/)\d+(/[^"]+)"')
          .firstMatch(row);

      out.add(BugsTrack(
        id: id,
        title: _unescape(title),
        artist: _unescape(artist),
        album: _unescape(album),
        imageUrl: img == null ? null : '${img.group(1)}500${img.group(2)}',
      ));
    }
    return out;
  }

  static String _unescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&#x27;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&');
}
