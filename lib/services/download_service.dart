import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'music_service.dart';

enum DownloadStatus { none, queued, downloading, done, failed }

/// Optional offline copies. Playback streams by default; a track the user
/// chose to download is played from its local file instead.
///
/// Files are fetched from the same stream URL the player would use, in 10 MB
/// Range requests: YouTube throttles single large requests (yt-dlp does the same).
class DownloadService extends ChangeNotifier {
  DownloadService(
    this._prefs,
    this._music, {
    http.Client? client,
    required Future<Directory> Function() directory,
  })  : _http = client ?? http.Client(),
        _directory = directory;

  final SharedPreferences _prefs;
  final MusicService _music;
  final http.Client _http;
  final Future<Directory> Function() _directory;

  static const _indexKey = 'drizon_downloads';
  static const chunkSize = 10 * 1024 * 1024;

  Directory? _dir;
  final _entries = <String, Map<String, dynamic>>{}; // videoId → {track, file, bytes, at}
  final _progress = <String, double>{};
  final _status = <String, DownloadStatus>{};
  final _errors = <String, String>{};
  final _queue = <Track>[];
  final _cancelled = <String>{};
  bool _running = false;

  // ── Setup ────────────────────────────────────────────────────────────────

  Future<void> init() async {
    final base = await _directory();
    _dir = Directory('${base.path}/downloads');
    await _dir!.create(recursive: true);
    final raw = _prefs.getString(_indexKey);
    if (raw != null) {
      try {
        for (final e in (jsonDecode(raw) as List).cast<Map>()) {
          final m = Map<String, dynamic>.from(e);
          // Drop entries whose file was removed (e.g. iOS storage cleanup).
          if (File('${_dir!.path}/${m['file']}').existsSync()) {
            _entries[(m['track'] as Map)['videoId'] as String] = m;
          }
        }
      } catch (_) {}
    }
    _save();
  }

  // ── Queries ──────────────────────────────────────────────────────────────

  bool isDownloaded(String videoId) => _entries.containsKey(videoId);

  String? localPath(String videoId) {
    final e = _entries[videoId];
    return (e == null || _dir == null) ? null : '${_dir!.path}/${e['file']}';
  }

  DownloadStatus status(String videoId) =>
      isDownloaded(videoId) ? DownloadStatus.done : (_status[videoId] ?? DownloadStatus.none);

  double progress(String videoId) => _progress[videoId] ?? 0;
  String? error(String videoId) => _errors[videoId];

  /// Downloaded tracks, newest first.
  List<Track> get tracks {
    final list = _entries.values.toList()
      ..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    return [for (final e in list) Track.fromMap(e['track'] as Map)];
  }

  int get totalBytes => _entries.values.fold(0, (sum, e) => sum + (e['bytes'] as int? ?? 0));

  // ── Commands ─────────────────────────────────────────────────────────────

  void download(Track track) {
    final s = status(track.videoId);
    if (s == DownloadStatus.done || s == DownloadStatus.queued || s == DownloadStatus.downloading) {
      return;
    }
    _cancelled.remove(track.videoId);
    _errors.remove(track.videoId);
    _status[track.videoId] = DownloadStatus.queued;
    _queue.add(track);
    notifyListeners();
    _pump();
  }

  void cancel(String videoId) {
    _cancelled.add(videoId);
    _queue.removeWhere((t) => t.videoId == videoId);
    _status.remove(videoId);
    _progress.remove(videoId);
    notifyListeners();
  }

  Future<void> remove(String videoId) async {
    final path = localPath(videoId);
    _entries.remove(videoId);
    _status.remove(videoId);
    _save();
    notifyListeners();
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> removeAll() async {
    for (final id in _entries.keys.toList()) {
      await remove(id);
    }
  }

  // ── Worker ───────────────────────────────────────────────────────────────

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final t = _queue.removeAt(0);
        try {
          await _fetch(t);
        } catch (e) {
          if (!_cancelled.contains(t.videoId)) {
            _status[t.videoId] = DownloadStatus.failed;
            _errors[t.videoId] = e.toString().split('\n').first;
            debugPrint('[Downloads] ${t.videoId} failed: $e');
          }
        } finally {
          _progress.remove(t.videoId);
          notifyListeners();
        }
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _fetch(Track t) async {
    _dir ??= Directory('${(await _directory()).path}/downloads');
    await _dir!.create(recursive: true);
    _status[t.videoId] = DownloadStatus.downloading;
    _progress[t.videoId] = 0;
    notifyListeners();

    final stream = await _music.getStreamInfo(t.videoId);
    if (stream.url.contains('.m3u8') || stream.url.contains('/manifest/hls')) {
      throw Exception('HLS streams can\'t be saved; try another extractor client');
    }
    final file = '${t.videoId}.${extensionFor(stream.url)}';
    final part = File('${_dir!.path}/$file.part');
    final sink = part.openWrite();
    var received = 0;
    int? total;
    try {
      while (total == null || received < total) {
        if (_cancelled.contains(t.videoId)) throw Exception('cancelled');
        final end = received + chunkSize - 1;
        final req = http.Request('GET', Uri.parse(stream.url))
          ..headers.addAll(stream.headers)
          ..headers['Range'] = 'bytes=$received-$end';
        final res = await _http.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode != 206 && res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        total ??= totalFromContentRange(res.headers['content-range']) ??
            res.contentLength ??
            0;
        var got = 0;
        await for (final bytes in res.stream) {
          sink.add(bytes);
          got += bytes.length;
          received += bytes.length;
          if (total > 0) _progress[t.videoId] = received / total;
          notifyListeners();
        }
        // A server that ignored Range sent everything in one go.
        if (res.statusCode == 200 || got == 0) break;
      }
      await sink.close();
    } catch (_) {
      await sink.close();
      if (part.existsSync()) await part.delete();
      rethrow;
    }

    await part.rename('${_dir!.path}/$file');
    _entries[t.videoId] = {
      'track': t.toMap(),
      'file': file,
      'bytes': received,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _status[t.videoId] = DownloadStatus.done;
    _save();
  }

  void _save() => _prefs.setString(_indexKey, jsonEncode(_entries.values.toList()));

  // ── Helpers (unit-tested) ────────────────────────────────────────────────

  /// "bytes 0-1023/5000" → 5000
  static int? totalFromContentRange(String? header) {
    if (header == null) return null;
    final m = RegExp(r'/(\d+)\s*$').firstMatch(header);
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Picks a file extension from googlevideo's `mime` query parameter.
  static String extensionFor(String url) {
    final mime = Uri.tryParse(url)?.queryParameters['mime'] ?? '';
    if (mime.contains('webm')) return 'webm';
    if (mime.contains('mp4') || mime.contains('m4a')) return 'm4a';
    final path = Uri.tryParse(url)?.path ?? '';
    final dot = path.lastIndexOf('.');
    if (dot > 0 && path.length - dot <= 5) return path.substring(dot + 1);
    return 'm4a';
  }
}
