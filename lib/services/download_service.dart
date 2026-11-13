import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'engines/ytmusic_client.dart';
import 'metadata_service.dart';
import 'music_service.dart';

enum DownloadStatus { none, queued, downloading, done, failed }

/// A music video / stage / fancam saved for offline viewing.
class DownloadedVideo {
  final YtmItem item;
  final int height;
  final String path;
  final String? thumbPath;
  final int bytes;

  const DownloadedVideo({
    required this.item,
    required this.height,
    required this.path,
    required this.bytes,
    this.thumbPath,
  });
}

sealed class _Job {
  String get key;
  String get videoId;
}

class _AudioJob extends _Job {
  _AudioJob(this.track);
  final Track track;
  @override
  String get key => 'a:${track.videoId}';
  @override
  String get videoId => track.videoId;
}

class _VideoJob extends _Job {
  _VideoJob(this.item, this.height);
  final YtmItem item;
  final int height;
  @override
  String get key => 'v:${item.videoId}';
  @override
  String get videoId => item.videoId;
}

/// Optional offline copies of songs (with cover and lyrics) and videos.
/// Streaming is the default; anything downloaded plays from disk instead.
///
/// Files are fetched from the same stream URLs used for playback, in 10 MB
/// Range requests: YouTube throttles single large requests (yt-dlp does the same).
/// Videos above the highest muxed quality are fetched as separate video and
/// audio streams and joined on the device without re-encoding.
class DownloadService extends ChangeNotifier implements OfflineStore {
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

  static const _audioIndexKey = 'drizon_downloads';
  static const _videoIndexKey = 'drizon_video_downloads';
  static const chunkSize = 10 * 1024 * 1024;

  Directory? _audioDir;
  Directory? _videoDir;
  final _songs = <String, Map<String, dynamic>>{}; // videoId → {track, file, bytes, at}
  final _videos = <String, Map<String, dynamic>>{}; // videoId → {item, file, height, thumb, bytes, at}
  final _covers = <String>{};

  final _progress = <String, double>{};
  final _status = <String, DownloadStatus>{};
  final _errors = <String, String>{};
  final _queue = <_Job>[];
  final _cancelled = <String>{};
  bool _running = false;

  /// Called after a song finishes downloading (saves its cover and lyrics).
  void Function(Track track)? onDownloaded;

  // ── Setup ────────────────────────────────────────────────────────────────

  Future<void> init() async {
    await _dirs();
    _load(_audioIndexKey, _songs, _audioDir!, (m) => (m['track'] as Map)['videoId'] as String);
    _load(_videoIndexKey, _videos, _videoDir!, (m) => (m['item'] as Map)['videoId'] as String);
    for (final id in _songs.keys) {
      if (File(_coverPath(id)).existsSync()) _covers.add(id);
    }
    _save();
  }

  Future<void> _dirs() async {
    if (_audioDir != null) return;
    final base = await _directory();
    _audioDir = Directory('${base.path}/downloads');
    _videoDir = Directory('${base.path}/videos');
    await _audioDir!.create(recursive: true);
    await _videoDir!.create(recursive: true);
  }

  void _load(String key, Map<String, Map<String, dynamic>> into, Directory dir,
      String Function(Map<String, dynamic>) idOf) {
    final raw = _prefs.getString(key);
    if (raw == null) return;
    try {
      for (final e in (jsonDecode(raw) as List).cast<Map>()) {
        final m = Map<String, dynamic>.from(e);
        // Drop entries whose file was removed (e.g. iOS storage cleanup).
        if (File('${dir.path}/${m['file']}').existsSync()) into[idOf(m)] = m;
      }
    } catch (_) {}
  }

  void _save() {
    _prefs.setString(_audioIndexKey, jsonEncode(_songs.values.toList()));
    _prefs.setString(_videoIndexKey, jsonEncode(_videos.values.toList()));
  }

  // ── Songs ────────────────────────────────────────────────────────────────

  @override
  bool isDownloaded(String videoId) => _songs.containsKey(videoId);

  String? localPath(String videoId) {
    final e = _songs[videoId];
    return (e == null || _audioDir == null) ? null : '${_audioDir!.path}/${e['file']}';
  }

  /// Saved album cover of a downloaded song (works offline).
  String? localCover(String videoId) => _covers.contains(videoId) ? _coverPath(videoId) : null;

  DownloadStatus status(String videoId) =>
      isDownloaded(videoId) ? DownloadStatus.done : (_status['a:$videoId'] ?? DownloadStatus.none);
  double progress(String videoId) => _progress['a:$videoId'] ?? 0;
  String? error(String videoId) => _errors['a:$videoId'];

  /// Downloaded songs, newest first.
  List<Track> get tracks {
    final list = _songs.values.toList()..sort((a, b) => (b['at'] as int).compareTo(a['at'] as int));
    return [for (final e in list) Track.fromMap(e['track'] as Map)];
  }

  void download(Track track) => _enqueue(_AudioJob(track), status(track.videoId));
  void cancel(String videoId) => _cancel('a:$videoId');

  Future<void> remove(String videoId) async {
    final path = localPath(videoId);
    _songs.remove(videoId);
    _status.remove('a:$videoId');
    _covers.remove(videoId);
    _save();
    notifyListeners();
    await deleteLyrics(videoId);
    for (final p in [path, if (_audioDir != null) _coverPath(videoId)]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }

  // ── Videos ───────────────────────────────────────────────────────────────

  bool isVideoDownloaded(String videoId) => _videos.containsKey(videoId);

  DownloadStatus videoStatus(String videoId) => isVideoDownloaded(videoId)
      ? DownloadStatus.done
      : (_status['v:$videoId'] ?? DownloadStatus.none);
  double videoProgress(String videoId) => _progress['v:$videoId'] ?? 0;
  String? videoError(String videoId) => _errors['v:$videoId'];

  DownloadedVideo? video(String videoId) {
    final e = _videos[videoId];
    if (e == null || _videoDir == null) return null;
    final thumb = e['thumb'] as String?;
    return DownloadedVideo(
      item: YtmItem.fromMap(e['item'] as Map),
      height: e['height'] as int? ?? 0,
      path: '${_videoDir!.path}/${e['file']}',
      thumbPath: thumb == null ? null : '${_videoDir!.path}/$thumb',
      bytes: e['bytes'] as int? ?? 0,
    );
  }

  /// Downloaded videos, newest first.
  List<DownloadedVideo> get videos {
    final ids = _videos.keys.toList()
      ..sort((a, b) => (_videos[b]!['at'] as int).compareTo(_videos[a]!['at'] as int));
    return [for (final id in ids) video(id)!];
  }

  void downloadVideo(YtmItem item, int height) =>
      _enqueue(_VideoJob(item, height), videoStatus(item.videoId));
  void cancelVideo(String videoId) => _cancel('v:$videoId');

  Future<void> removeVideo(String videoId) async {
    final v = video(videoId);
    _videos.remove(videoId);
    _status.remove('v:$videoId');
    _save();
    notifyListeners();
    for (final p in [v?.path, v?.thumbPath]) {
      if (p == null) continue;
      try {
        await File(p).delete();
      } catch (_) {}
    }
  }

  // ── Both ─────────────────────────────────────────────────────────────────

  int get totalBytes =>
      [..._songs.values, ..._videos.values].fold(0, (sum, e) => sum + (e['bytes'] as int? ?? 0));

  Future<void> removeAll() async {
    for (final id in _songs.keys.toList()) {
      await remove(id);
    }
    for (final id in _videos.keys.toList()) {
      await removeVideo(id);
    }
  }

  // ── Offline cover & lyrics (OfflineStore) ────────────────────────────────

  String _coverPath(String videoId) => '${_audioDir!.path}/$videoId.jpg';
  File? _lyricsFile(String videoId) =>
      _audioDir == null ? null : File('${_audioDir!.path}/$videoId.lyrics.json');

  @override
  Future<void> saveCover(String videoId, String url) async {
    if (!isDownloaded(videoId)) return;
    try {
      final res = await _http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200 || res.bodyBytes.isEmpty) return;
      await File(_coverPath(videoId)).writeAsBytes(res.bodyBytes);
      _covers.add(videoId);
      notifyListeners();
    } catch (e) {
      debugPrint('[Downloads] cover for $videoId not saved: $e');
    }
  }

  @override
  Future<String?> readLyrics(String videoId) async {
    final f = _lyricsFile(videoId);
    return (f != null && await f.exists()) ? f.readAsString() : null;
  }

  @override
  Future<void> writeLyrics(String videoId, String json) async {
    if (!isDownloaded(videoId)) return; // only downloaded songs keep lyrics
    final f = _lyricsFile(videoId);
    if (f == null) return;
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json);
    await tmp.rename(f.path);
  }

  @override
  Future<void> deleteLyrics(String videoId) async {
    final f = _lyricsFile(videoId);
    if (f != null && await f.exists()) await f.delete();
  }

  // ── Queue ────────────────────────────────────────────────────────────────

  void _enqueue(_Job job, DownloadStatus current) {
    if (current == DownloadStatus.done ||
        current == DownloadStatus.queued ||
        current == DownloadStatus.downloading) {
      return;
    }
    _cancelled.remove(job.key);
    _errors.remove(job.key);
    _status[job.key] = DownloadStatus.queued;
    _queue.add(job);
    notifyListeners();
    _pump();
  }

  void _cancel(String key) {
    _cancelled.add(key);
    _queue.removeWhere((j) => j.key == key);
    _status.remove(key);
    _progress.remove(key);
    notifyListeners();
  }

  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      while (_queue.isNotEmpty) {
        final job = _queue.removeAt(0);
        try {
          await _dirs();
          _status[job.key] = DownloadStatus.downloading;
          _progress[job.key] = 0;
          notifyListeners();
          switch (job) {
            case _AudioJob():
              await _runAudio(job);
            case _VideoJob():
              await _runVideo(job);
          }
        } catch (e) {
          if (!_cancelled.contains(job.key)) {
            _status[job.key] = DownloadStatus.failed;
            _errors[job.key] = e.toString().replaceFirst('Exception: ', '').split('\n').first;
            debugPrint('[Downloads] ${job.key} failed: $e');
          }
        } finally {
          _progress.remove(job.key);
          notifyListeners();
        }
      }
    } finally {
      _running = false;
    }
  }

  /// Fetches a track's audio into a temporary play cache (not added to the
  /// library) and returns the file path. Used when streaming directly fails.
  Future<String?> cacheForPlayback(Track t) async {
    final dir = Directory('${(await _directory()).path}/playcache');
    await dir.create(recursive: true);
    // Keep the cache small: drop all but the newest few files.
    final old = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    for (final f in old.skip(8)) {
      try {
        await f.delete();
      } catch (_) {}
    }
    for (final f in old) {
      final name = f.uri.pathSegments.last;
      if (name.startsWith('${t.videoId}.') && !name.endsWith('.part')) return f.path;
    }
    final stream = await _music.getStreamInfo(t.videoId);
    _rejectHls(stream.url);
    final path = '${dir.path}/${t.videoId}.${extensionFor(stream.url)}';
    await _fetch(stream.url, stream.headers, path, 'play:${t.videoId}', (p) => p);
    return path;
  }

  Future<void> _runAudio(_AudioJob job) async {
    final t = job.track;
    final stream = await _music.getStreamInfo(t.videoId);
    _rejectHls(stream.url);
    final file = '${t.videoId}.${extensionFor(stream.url)}';
    final bytes = await _fetch(stream.url, stream.headers, '${_audioDir!.path}/$file', job.key,
        (p) => p);
    _songs[t.videoId] = {
      'track': t.toMap(),
      'file': file,
      'bytes': bytes,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _status[job.key] = DownloadStatus.done;
    _save();
    onDownloaded?.call(t);
  }

  Future<void> _runVideo(_VideoJob job) async {
    final id = job.videoId;
    final streams = await _music.getVideoStreams(id);
    final plan = streams.planFor(job.height) ??
        (throw Exception('${job.height}p is not available for this video'));
    final dir = _videoDir!.path;
    final file = '$id.mp4';
    int bytes;
    if (!plan.needsMux) {
      bytes = await _fetch(plan.video.url, streams.headers, '$dir/$file', job.key, (p) => p);
    } else {
      // Video is the bulk of the bytes; reserve the tail for audio and joining.
      final v = await _fetch(plan.video.url, streams.headers, '$dir/$id.video.mp4', job.key,
          (p) => p * 0.85);
      final a = await _fetch(plan.audio!.url, streams.headers, '$dir/$id.audio.m4a', job.key,
          (p) => 0.85 + p * 0.12);
      try {
        await _music.muxVideo('$dir/$id.video.mp4', '$dir/$id.audio.m4a', '$dir/$file');
      } finally {
        for (final part in ['$dir/$id.video.mp4', '$dir/$id.audio.m4a']) {
          if (File(part).existsSync()) await File(part).delete();
        }
      }
      bytes = File('$dir/$file').existsSync() ? File('$dir/$file').lengthSync() : v + a;
    }

    String? thumb;
    try {
      final res = await _http.get(Uri.parse(job.item.videoThumb('hqdefault')));
      if (res.statusCode == 200) {
        thumb = '$id.jpg';
        await File('$dir/$thumb').writeAsBytes(res.bodyBytes);
      }
    } catch (_) {}

    _videos[id] = {
      'item': job.item.toMap(),
      'file': file,
      'height': job.height,
      'thumb': thumb,
      'bytes': bytes,
      'at': DateTime.now().millisecondsSinceEpoch,
    };
    _status[job.key] = DownloadStatus.done;
    _save();
  }

  void _rejectHls(String url) {
    if (url.contains('.m3u8') || url.contains('/manifest/hls')) {
      throw Exception('HLS streams can\'t be saved; try another extractor client');
    }
  }

  /// Ranged download into [path] (via a .part file). Returns the byte count.
  Future<int> _fetch(String url, Map<String, String> headers, String path, String key,
      double Function(double) scaleProgress) async {
    _rejectHls(url);
    final part = File('$path.part');
    final sink = part.openWrite();
    var received = 0;
    int? total;
    try {
      while (total == null || received < total) {
        if (_cancelled.contains(key)) throw Exception('cancelled');
        final req = http.Request('GET', Uri.parse(url))
          ..headers.addAll(headers)
          ..headers['Range'] = 'bytes=$received-${received + chunkSize - 1}';
        final res = await _http.send(req).timeout(const Duration(seconds: 30));
        if (res.statusCode != 206 && res.statusCode != 200) {
          throw Exception('HTTP ${res.statusCode}');
        }
        total ??= totalFromContentRange(res.headers['content-range']) ?? res.contentLength ?? 0;
        var got = 0;
        await for (final bytes in res.stream) {
          sink.add(bytes);
          got += bytes.length;
          received += bytes.length;
          if (total > 0) _progress[key] = scaleProgress(received / total);
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
    await part.rename(path);
    return received;
  }

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
