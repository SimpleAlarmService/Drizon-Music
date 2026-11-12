import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'engines/bugs_client.dart';
import 'engines/lrclib_client.dart';
import 'engines/lyrics.dart';
import 'engines/matching.dart';
import 'engines/ytmusic_client.dart';

/// Where downloaded songs keep their cover and lyrics for offline use
/// (implemented by DownloadService, next to the audio file).
abstract class OfflineStore {
  bool isDownloaded(String videoId);
  Future<void> saveCover(String videoId, String url);
  Future<String?> readLyrics(String videoId);
  Future<void> writeLyrics(String videoId, String json);
  Future<void> deleteLyrics(String videoId);
}

/// Lyrics lookup outcome for one track.
class LyricsResult {
  final Lyrics? lyrics;
  final String? provider; // '벅스' or 'LRCLIB'
  final String? sourceTitle;
  final String? sourceArtist;
  final BugsTrack? bugs; // set when the lyrics came from Bugs
  final String? error;

  const LyricsResult({
    this.lyrics,
    this.provider,
    this.sourceTitle,
    this.sourceArtist,
    this.bugs,
    this.error,
  });

  bool get found => lyrics != null && !lyrics!.isEmpty;

  Map<String, dynamic> toJson() => {
        'lyrics': lyrics!.toJson(),
        'provider': provider,
        'sourceTitle': sourceTitle,
        'sourceArtist': sourceArtist,
        if (bugs != null) 'bugs': bugs!.toMap(),
      };

  factory LyricsResult.fromJson(Map<String, dynamic> j) => LyricsResult(
        lyrics: Lyrics.fromJson(Map<String, dynamic>.from(j['lyrics'] as Map)),
        provider: j['provider'] as String?,
        sourceTitle: j['sourceTitle'] as String?,
        sourceArtist: j['sourceArtist'] as String?,
        bugs: j['bugs'] is Map ? BugsTrack.fromMap(j['bugs'] as Map) : null,
      );
}

/// Album covers (YouTube Music) and lyrics (Bugs) matched to tracks.
///
/// Matches are persisted per video, so each song is looked up once. Covers are
/// exposed synchronously ([artFor]) so every artwork in the UI can pick them up
/// as soon as they're found; this notifies listeners when something new lands.
class MetadataService extends ChangeNotifier {
  MetadataService(this._prefs, this._ytm, this._bugs, [LrclibClient? lrclib])
      : _lrclib = lrclib ?? LrclibClient();

  final SharedPreferences _prefs;
  final YtmClient _ytm;
  final BugsClient _bugs;
  final LrclibClient _lrclib;

  static const _prefix = 'drizon_meta_';
  static const _retryAfter = Duration(days: 3);

  final _meta = <String, Map<String, dynamic>>{};
  final _artInFlight = <String>{};
  final _lyrics = <String, Future<LyricsResult>>{};

  /// Offline copies of lyrics for downloaded tracks.
  OfflineStore? offline;

  // ── Synchronous lookups for the UI ───────────────────────────────────────

  String? artFor(Track t) => t.albumArt ?? _get(t.videoId)['albumArt'] as String?;
  String? albumFor(Track t) => t.album ?? _get(t.videoId)['album'] as String?;

  SongQuery queryFor(Track t) => SongQuery.from(
        title: t.title,
        artist: t.artist,
        album: albumFor(t),
        durationSec: t.durationSec,
        isSong: t.albumArt != null || t.artist.endsWith(' - Topic'),
      );

  /// Called when a track starts playing: fetch its cover and lyrics ahead of time.
  void prefetch(Track t) {
    ensureArt(t);
    lyricsFor(t);
  }

  // ── Album art (YouTube Music) ────────────────────────────────────────────

  /// Finds a square album cover for videos (songs from YT Music already have one)
  /// by looking up the same song in YouTube Music.
  Future<void> ensureArt(Track t) async {
    if (artFor(t) != null || _artInFlight.contains(t.videoId)) return;
    if (_recentlyChecked(_get(t.videoId)['artCheckedAt'])) return;
    _artInFlight.add(t.videoId);
    try {
      final query = queryFor(t);
      final terms = query.searchTerms;
      for (var i = 0; i < terms.length; i++) {
        final best = YtmClient.bestSong(query, await _ytm.search(terms[i]),
            artistInTerm: query.termHasArtist(i));
        if (best != null) {
          _update(t.videoId, {'albumArt': best.albumArt, 'album': best.album, 'artSource': 'ytmusic'});
          return;
        }
      }
      _update(t.videoId, {'artCheckedAt': DateTime.now().millisecondsSinceEpoch});
    } catch (e) {
      debugPrint('[Metadata] album art lookup failed for ${t.videoId}: $e');
    } finally {
      _artInFlight.remove(t.videoId);
    }
  }

  // ── Lyrics (Bugs) ────────────────────────────────────────────────────────

  /// Memoised: the same Future is returned until the match changes.
  Future<LyricsResult> lyricsFor(Track t) =>
      _lyrics[t.videoId] ??= _lyricsWithOffline(t).then((r) {
        if (r.error != null) _lyrics.remove(t.videoId); // allow a retry later
        return r;
      });

  /// Downloaded tracks read their saved lyrics first (works offline); a
  /// successful online lookup for a downloaded track is saved for next time.
  Future<LyricsResult> _lyricsWithOffline(Track t) async {
    final store = offline;
    final downloaded = store?.isDownloaded(t.videoId) ?? false;
    if (downloaded) {
      try {
        final raw = await store!.readLyrics(t.videoId);
        if (raw != null) {
          final saved = LyricsResult.fromJson(jsonDecode(raw) as Map<String, dynamic>);
          if (saved.found) return saved;
        }
      } catch (e) {
        debugPrint('[Metadata] unreadable offline lyrics for ${t.videoId}: $e');
      }
    }
    final r = await _loadLyrics(t);
    if (downloaded && r.found) {
      try {
        await store!.writeLyrics(t.videoId, jsonEncode(r.toJson()));
      } catch (e) {
        debugPrint('[Metadata] could not save offline lyrics for ${t.videoId}: $e');
      }
    }
    return r;
  }

  /// Called when a song finishes downloading: store its cover and lyrics so
  /// both work offline. The cover is YouTube Music's (matched first if needed).
  Future<void> saveOffline(Track t) async {
    await ensureArt(t);
    _lyrics.remove(t.videoId); // re-run so the result gets written to disk
    // Lyrics first: matching on Bugs may supply the fallback cover.
    await lyricsFor(t);
    final art = artFor(t) ?? 'https://i.ytimg.com/vi/${t.videoId}/hqdefault.jpg';
    await offline?.saveCover(t.videoId, art);
  }

  /// Bugs first (synced), then LRCLIB (synced). Plain lyrics found along the
  /// way are kept as a fallback while a synced version is still being looked for.
  Future<LyricsResult> _loadLyrics(Track t) async {
    try {
      final query = queryFor(t);
      LyricsResult? plainFallback;

      final bugsTrack = await _bugsMatch(t, query);
      if (bugsTrack != null) {
        _fallbackArtFromBugs(t, bugsTrack);
        final l = await _bugs.lyrics(bugsTrack.id);
        final r = LyricsResult(
          lyrics: l,
          provider: '벅스',
          sourceTitle: bugsTrack.title,
          sourceArtist: bugsTrack.artist,
          bugs: bugsTrack,
        );
        if (l != null && l.isSynced) return r;
        if (l != null && !l.isEmpty) plainFallback = r;
        // An explicit choice by the user is final.
        if (_get(t.videoId)['bugsManual'] == true) return plainFallback ?? r;
      }

      final record = await _lrclibMatch(t, query);
      final l = record?.toLyrics();
      if (record != null && l != null) {
        final r = LyricsResult(
          lyrics: l,
          provider: 'LRCLIB',
          sourceTitle: record.title,
          sourceArtist: record.artist,
        );
        if (l.isSynced) return r;
        plainFallback ??= r;
      }
      return plainFallback ?? const LyricsResult();
    } catch (e) {
      debugPrint('[Metadata] lyrics lookup failed for ${t.videoId}: $e');
      return const LyricsResult(error: '가사를 불러오지 못했어요');
    }
  }

  Future<BugsTrack?> _bugsMatch(Track t, SongQuery query) async {
    final meta = _get(t.videoId);
    if (meta['bugs'] is Map) return BugsTrack.fromMap(meta['bugs'] as Map);
    if (meta['bugsNone'] == true && _recentlyChecked(meta['lyricsCheckedAt'])) return null;
    final (best, _) = await _bugs.match(query);
    _update(t.videoId, best == null
        ? {'bugsNone': true, 'lyricsCheckedAt': DateTime.now().millisecondsSinceEpoch}
        : {'bugs': best.toMap(), 'bugsNone': false});
    return best;
  }

  Future<LrclibRecord?> _lrclibMatch(Track t, SongQuery query) async {
    final meta = _get(t.videoId);
    if (meta['lrclibId'] is int) return _lrclib.byId(meta['lrclibId'] as int);
    if (_recentlyChecked(meta['lrclibCheckedAt'])) return null;
    final best = await _lrclib.match(query);
    _update(t.videoId, best == null
        ? {'lrclibCheckedAt': DateTime.now().millisecondsSinceEpoch}
        : {'lrclibId': best.id});
    return best;
  }

  /// Candidates for manually choosing the lyrics source.
  Future<List<BugsTrack>> searchBugs(String query) => _bugs.search(query);

  /// User picked the right song in Bugs: remember it and reload lyrics.
  Future<void> setLyricsSource(Track t, BugsTrack source) async {
    _update(t.videoId, {'bugs': source.toMap(), 'bugsNone': false, 'bugsManual': true});
    // The saved copy is the old choice; drop it so the new lyrics replace it.
    await offline?.deleteLyrics(t.videoId);
    _lyrics.remove(t.videoId);
    notifyListeners();
  }

  /// YouTube Music is the cover source; if it has no match, Bugs' album cover
  /// of the matched song is better than a video frame.
  void _fallbackArtFromBugs(Track t, BugsTrack source) {
    if (artFor(t) != null || source.imageUrl == null) return;
    if (!_recentlyChecked(_get(t.videoId)['artCheckedAt'])) return; // YTM not tried yet
    _update(t.videoId, {
      'albumArt': source.imageUrl,
      'album': source.album.isEmpty ? null : source.album,
      'artSource': 'bugs',
    });
  }

  // ── Persistence ──────────────────────────────────────────────────────────

  Map<String, dynamic> _get(String videoId) => _meta.putIfAbsent(videoId, () {
        final raw = _prefs.getString('$_prefix$videoId');
        if (raw == null) return <String, dynamic>{};
        try {
          return Map<String, dynamic>.from(jsonDecode(raw) as Map);
        } catch (_) {
          return <String, dynamic>{};
        }
      });

  void _update(String videoId, Map<String, dynamic> values) {
    final m = _get(videoId);
    values.forEach((k, v) => v == null ? m.remove(k) : m[k] = v);
    _prefs.setString('$_prefix$videoId', jsonEncode(m));
    notifyListeners();
  }

  bool _recentlyChecked(Object? epochMs) =>
      epochMs is int &&
      DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(epochMs)) < _retryAfter;
}
