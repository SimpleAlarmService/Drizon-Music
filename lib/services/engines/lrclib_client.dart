import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lyrics.dart';
import 'matching.dart';

/// A lyrics record on LRCLIB (https://lrclib.net), an open lyrics database.
class LrclibRecord {
  final int id;
  final String title;
  final String artist;
  final String? album;
  final double duration;
  final bool instrumental;
  final String? synced;
  final String? plain;

  const LrclibRecord({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    this.album,
    this.instrumental = false,
    this.synced,
    this.plain,
  });

  factory LrclibRecord.fromJson(Map<String, dynamic> j) => LrclibRecord(
        id: (j['id'] as num).toInt(),
        title: j['trackName'] as String? ?? '',
        artist: j['artistName'] as String? ?? '',
        album: j['albumName'] as String?,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        instrumental: j['instrumental'] == true,
        synced: j['syncedLyrics'] as String?,
        plain: j['plainLyrics'] as String?,
      );

  Lyrics? toLyrics() {
    final lines = synced == null ? const <LyricLine>[] : Lyrics.parseLrc(synced!);
    if (lines.isNotEmpty) return Lyrics(synced: lines);
    if (plain != null && plain!.trim().isNotEmpty) return Lyrics(plain: plain!.trim());
    return null;
  }
}

/// LRCLIB fallback when Bugs has no (synced) lyrics.
class LrclibClient {
  LrclibClient({http.Client? client}) : _http = client ?? http.Client();
  final http.Client _http;

  static const _host = 'https://lrclib.net';
  // LRCLIB asks clients to identify themselves.
  static const _headers = {'User-Agent': 'Drizon/1.0 (personal music player)'};

  /// Allowed duration difference when the track length is known.
  static const durationTolerance = 5.0;

  Future<List<LrclibRecord>> search(String trackName, String artistName) async {
    final uri = Uri.parse('$_host/api/search')
        .replace(queryParameters: {'track_name': trackName, 'artist_name': artistName});
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];
    return parseSearch(utf8.decode(res.bodyBytes));
  }

  Future<LrclibRecord?> byId(int id) async {
    final res = await _http
        .get(Uri.parse('$_host/api/get/$id'), headers: _headers)
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    return LrclibRecord.fromJson(jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>);
  }

  static List<LrclibRecord> parseSearch(String body) {
    final list = jsonDecode(body);
    if (list is! List) return const [];
    return list.whereType<Map<String, dynamic>>().map(LrclibRecord.fromJson).toList();
  }

  /// Best record for [query]: synced lyrics win over plain, and when the length
  /// is known only records within [durationTolerance] seconds qualify.
  static LrclibRecord? pickBest(SongQuery query, List<LrclibRecord> records) {
    LrclibRecord? best;
    var bestScore = 0.0;
    for (final r in records) {
      if (r.instrumental) continue;
      if (query.durationSec > 0 && r.duration > 0 &&
          (r.duration - query.durationSec).abs() > durationTolerance) {
        continue;
      }
      var s = query.score(
        candidateTitle: r.title,
        candidateArtist: r.artist,
        candidateAlbum: r.album,
      );
      if (r.synced != null && r.synced!.trim().isNotEmpty) s += 0.05;
      if (s > bestScore) {
        bestScore = s;
        best = r;
      }
    }
    return bestScore >= matchThreshold ? best : null;
  }

  Future<LrclibRecord?> match(SongQuery query) async {
    final best = pickBest(query, await search(query.title, query.primaryArtist));
    if (best != null) return best;
    // Artist names differ across catalogues (아이유 / IU); retry by title only and
    // let the scorer judge the artist.
    return pickBest(query, await searchByQuery(query.title));
  }

  Future<List<LrclibRecord>> searchByQuery(String q) async {
    final uri = Uri.parse('$_host/api/search').replace(queryParameters: {'q': q});
    final res = await _http.get(uri, headers: _headers).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return const [];
    return parseSearch(utf8.decode(res.bodyBytes));
  }
}
