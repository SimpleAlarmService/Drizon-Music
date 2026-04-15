import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';
import '../models/settings_model.dart';

/// Abstract music service: search tracks + resolve audio stream URL.
///
/// Extractor behaviour is controlled at runtime via [applySettings].
/// Android → NewPipe via MethodChannel (primary) with Dart fallback.
/// iOS / forced innertube → youtube_explode_dart only.
abstract class MusicService {
  Future<List<Track>> search(String query);
  Future<String> getStreamUrl(String videoId);
  Future<void> dispose();

  /// Apply extractor settings at runtime without recreating the service.
  void applySettings(AppSettings settings);

  factory MusicService() {
    if (Platform.isAndroid) return _AndroidMusicService();
    return _DartMusicService();
  }
}

// ─── Android: NewPipe via MethodChannel ───────────────────────────────────────

class _AndroidMusicService implements MusicService {
  static const _ch = MethodChannel('music.extractor');
  final _dartService = _DartMusicService();

  // Runtime-configurable knobs
  ExtractorType _primaryExtractor = ExtractorType.auto;
  bool _enableFallback = true;
  ClientType _clientType = ClientType.android;
  AudioQuality _audioQuality = AudioQuality.high;

  @override
  void applySettings(AppSettings s) {
    _primaryExtractor = s.primaryExtractor;
    _enableFallback = s.enableFallback;
    _clientType = s.clientType;
    _audioQuality = s.audioQuality;
    _dartService.applySettings(s);
  }

  bool get _skipNative =>
      _primaryExtractor == ExtractorType.innertube;

  @override
  Future<List<Track>> search(String query) async {
    if (!_skipNative) {
      try {
        final raw = await _ch.invokeMethod<List>('search', {'query': query});
        if (raw != null && raw.isNotEmpty) {
          return raw.cast<Map<dynamic, dynamic>>().map(Track.fromMap).toList();
        }
      } catch (e) {
        debugPrint('[MusicService] NewPipe search error: $e');
      }
    }
    return _dartService.search(query);
  }

  @override
  Future<String> getStreamUrl(String videoId) async {
    if (!_skipNative) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final url = await _ch.invokeMethod<String>('getStream', {
            'videoId': videoId,
            'clientType': _clientType.value,
            'quality': _audioQuality.value,
          });
          if (url != null && url.isNotEmpty) return url;
        } catch (e) {
          debugPrint(
              '[MusicService] NewPipe stream error (attempt ${attempt + 1}): $e');
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 600));
          }
        }
      }
      debugPrint('[MusicService] NewPipe failed twice.');
    }

    if (_enableFallback || _skipNative) {
      return _dartService.getStreamUrl(videoId);
    }
    throw Exception('Stream unavailable: NewPipe failed and fallback disabled');
  }

  @override
  Future<void> dispose() async => _dartService.dispose();
}

// ─── iOS / Dart fallback: youtube_explode_dart ────────────────────────────────

class _DartMusicService implements MusicService {
  final YoutubeExplode _yt = YoutubeExplode();
  AudioQuality _audioQuality = AudioQuality.high;

  @override
  void applySettings(AppSettings s) {
    _audioQuality = s.audioQuality;
  }

  @override
  Future<List<Track>> search(String query) async {
    final results =
        await _yt.search.search('$query music', filter: TypeFilters.video);
    final tracks = <Track>[];
    for (final v in results) {
      tracks.add(Track(
        videoId: v.id.value,
        title: v.title,
        artist: v.author,
        thumbnail: v.thumbnails.mediumResUrl,
        duration: v.duration != null ? _durStr(v.duration!) : '0:00',
        durationSec: v.duration?.inSeconds ?? 0,
      ));
      if (tracks.length >= 20) break;
    }
    return tracks;
  }

  @override
  Future<String> getStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streams.getManifest(videoId);
    final audioStreams = manifest.audioOnly;
    if (audioStreams.isEmpty) {
      throw Exception('No audio streams for $videoId');
    }

    final sorted = audioStreams.toList()
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));

    switch (_audioQuality) {
      case AudioQuality.low:
        return sorted.first.url.toString();
      case AudioQuality.medium:
        return sorted[sorted.length ~/ 2].url.toString();
      case AudioQuality.high:
        return audioStreams.withHighestBitrate().url.toString();
    }
  }

  @override
  Future<void> dispose() async => _yt.close();

  static String _durStr(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
