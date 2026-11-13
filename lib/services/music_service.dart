import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/track.dart';
import '../models/settings_model.dart';
import '../models/video_streams.dart';
import 'engines/ytmusic_client.dart';

/// Abstract music service: search tracks + resolve audio stream URL.
///
/// Extractor behaviour is controlled at runtime via [applySettings].
/// Android → NewPipe via MethodChannel.
/// iOS, macOS → embedded Python + yt-dlp via MethodChannel.
abstract class MusicService {
  Future<List<Track>> search(String query);
  Future<String> getStreamUrl(String videoId);

  /// Stream URL plus the HTTP headers the player must send with it.
  Future<StreamInfo> getStreamInfo(String videoId);

  /// Every format of a video (for watching and downloading music videos,
  /// stages, fancams…).
  Future<VideoStreams> getVideoStreams(String videoId);

  /// Joins a video-only file and an audio file into [output] (MP4, no re-encode).
  Future<void> muxVideo(String video, String audio, String output);

  /// iOS and macOS: download the newest yt-dlp (applied on next launch).
  /// Returns a human-readable status line.
  Future<String> updateExtractor();

  Future<void> dispose();

  /// Apply extractor settings at runtime without recreating the service.
  void applySettings(AppSettings settings);

  /// With [ytm], search goes to the YouTube Music engine first (songs with album
  /// art and album names); the platform extractor's search is the fallback.
  factory MusicService({YtmClient? ytm}) {
    final MusicService inner = _NativeMusicService();
    return ytm == null ? inner : _YtmSearchFirst(ytm, inner);
  }
}

class _YtmSearchFirst implements MusicService {
  _YtmSearchFirst(this._ytm, this._inner);
  final YtmClient _ytm;
  final MusicService _inner;

  @override
  Future<List<Track>> search(String query) async {
    try {
      final items = await _ytm.search(query);
      if (items.isNotEmpty) return items.map((i) => i.toTrack()).toList();
    } catch (e) {
      debugPrint('[MusicService] YouTube Music search failed, falling back: $e');
    }
    return _inner.search(query);
  }

  @override
  Future<String> getStreamUrl(String videoId) => _inner.getStreamUrl(videoId);
  @override
  Future<StreamInfo> getStreamInfo(String videoId) => _inner.getStreamInfo(videoId);
  @override
  Future<VideoStreams> getVideoStreams(String videoId) => _inner.getVideoStreams(videoId);
  @override
  Future<void> muxVideo(String video, String audio, String output) =>
      _inner.muxVideo(video, audio, output);
  @override
  Future<String> updateExtractor() => _inner.updateExtractor();
  @override
  void applySettings(AppSettings settings) => _inner.applySettings(settings);
  @override
  Future<void> dispose() => _inner.dispose();
}

/// A resolved audio stream.
class StreamInfo {
  final String url;
  final Map<String, String> headers;
  const StreamInfo(this.url, this.headers);
}

const _defaultStreamHeaders = {
  'User-Agent': 'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.6723.103 Mobile Safari/537.36',
  'Referer': 'https://www.youtube.com/',
  'Origin': 'https://www.youtube.com',
};

// ─── Android: NewPipe / iOS: yt-dlp — both via MethodChannel ──────────────────

class _NativeMusicService implements MusicService {
  static const _ch = MethodChannel('music.extractor');

  // Runtime-configurable knobs
  ClientType _clientType = ClientType.android;
  AudioQuality _audioQuality = AudioQuality.high;

  @override
  void applySettings(AppSettings s) {
    _clientType = s.clientType;
    _audioQuality = s.audioQuality;
  }

  String get _engine => (Platform.isIOS || Platform.isMacOS) ? 'yt-dlp' : 'NewPipe';

  @override
  Future<List<Track>> search(String query) async {
    try {
      final raw = await _ch.invokeMethod<List>('search', {'query': query});
      return (raw ?? const [])
          .cast<Map<dynamic, dynamic>>()
          .map(Track.fromMap)
          .toList();
    } catch (e) {
      debugPrint('[MusicService] $_engine search error: $e');
      rethrow;
    }
  }

  @override
  Future<String> getStreamUrl(String videoId) async =>
      (await getStreamInfo(videoId)).url;

  @override
  Future<StreamInfo> getStreamInfo(String videoId) async {
    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final info = await _nativeStream(videoId);
        if (info != null) return info;
      } catch (e) {
        debugPrint(
            '[MusicService] $_engine stream error (attempt ${attempt + 1}): $e');
        if (attempt == 1) rethrow;
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
    throw Exception('Stream unavailable: $_engine returned no URL');
  }

  Future<StreamInfo?> _nativeStream(String videoId) async {
    final args = {
      'videoId': videoId,
      'clientType': _clientType.value,
      'quality': _audioQuality.value,
    };
    if ((Platform.isIOS || Platform.isMacOS)) {
      // yt-dlp tells us which headers the URL needs (they depend on the client).
      final raw = await _ch.invokeMapMethod<String, dynamic>('getStreamInfo', args);
      final url = raw?['url'] as String?;
      if (url == null || url.isEmpty) return null;
      final headers = <String, String>{
        for (final e in ((raw?['headers'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value.toString(),
      };
      return StreamInfo(url, headers);
    }
    final url = await _ch.invokeMethod<String>('getStream', args);
    if (url == null || url.isEmpty) return null;
    return StreamInfo(url, _defaultStreamHeaders);
  }

  @override
  Future<VideoStreams> getVideoStreams(String videoId) async {
    final raw = await _ch.invokeMapMethod<String, dynamic>('getVideoStreams', {
      'videoId': videoId,
      'clientType': _clientType.value,
    });
    final streams = raw == null ? null : VideoStreams.fromMap(raw);
    if (streams?.playbackUrl == null) throw Exception('Video unavailable');
    return streams!;
  }

  @override
  Future<void> muxVideo(String video, String audio, String output) async {
    await _ch.invokeMethod<String>(
        'muxVideo', {'video': video, 'audio': audio, 'output': output});
  }

  @override
  Future<String> updateExtractor() async {
    if (!(Platform.isIOS || Platform.isMacOS)) return 'Only available on iOS and macOS';
    final r = await _ch.invokeMapMethod<String, dynamic>('updateExtractor');
    final installed = r?['installed'];
    final running = r?['running'];
    return r?['restartRequired'] == true
        ? 'yt-dlp $installed downloaded — restart the app to use it'
        : 'yt-dlp $running is up to date';
  }

  @override
  Future<void> dispose() async {}
}
