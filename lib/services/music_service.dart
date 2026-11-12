import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../models/track.dart';
import '../models/settings_model.dart';
import '../models/video_streams.dart';
import 'engines/ytmusic_client.dart';

/// Abstract music service: search tracks + resolve audio stream URL.
///
/// Extractor behaviour is controlled at runtime via [applySettings].
/// Android → NewPipe via MethodChannel (primary) with Dart fallback.
/// iOS     → embedded Python + yt-dlp via MethodChannel (primary) with Dart fallback.
/// Forced "innertube" → youtube_explode_dart only.
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

  /// iOS only: download the newest yt-dlp (applied on next launch).
  /// Returns a human-readable status line.
  Future<String> updateExtractor();

  Future<void> dispose();

  /// Apply extractor settings at runtime without recreating the service.
  void applySettings(AppSettings settings);

  /// With [ytm], search goes to the YouTube Music engine first (songs with album
  /// art and album names); the platform extractor's search is the fallback.
  factory MusicService({YtmClient? ytm}) {
    final MusicService inner = (Platform.isAndroid || Platform.isIOS)
        ? _NativeMusicService()
        : _DartMusicService();
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

  String get _engine => Platform.isIOS ? 'yt-dlp' : 'NewPipe';

  @override
  Future<List<Track>> search(String query) async {
    if (!_skipNative) {
      try {
        final raw = await _ch.invokeMethod<List>('search', {'query': query});
        if (raw != null && raw.isNotEmpty) {
          return raw.cast<Map<dynamic, dynamic>>().map(Track.fromMap).toList();
        }
      } catch (e) {
        debugPrint('[MusicService] $_engine search error: $e');
      }
    }
    return _dartService.search(query);
  }

  @override
  Future<String> getStreamUrl(String videoId) async =>
      (await getStreamInfo(videoId)).url;

  @override
  Future<StreamInfo> getStreamInfo(String videoId) async {
    if (!_skipNative) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          final info = await _nativeStream(videoId);
          if (info != null) return info;
        } catch (e) {
          debugPrint(
              '[MusicService] $_engine stream error (attempt ${attempt + 1}): $e');
          if (attempt == 0) {
            await Future.delayed(const Duration(milliseconds: 600));
          }
        }
      }
      debugPrint('[MusicService] $_engine failed twice.');
    }

    if (_enableFallback || _skipNative) {
      return _dartService.getStreamInfo(videoId);
    }
    throw Exception('Stream unavailable: $_engine failed and fallback disabled');
  }

  Future<StreamInfo?> _nativeStream(String videoId) async {
    final args = {
      'videoId': videoId,
      'clientType': _clientType.value,
      'quality': _audioQuality.value,
    };
    if (Platform.isIOS) {
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
    if (!_skipNative) {
      try {
        final raw = await _ch.invokeMapMethod<String, dynamic>('getVideoStreams', {
          'videoId': videoId,
          'clientType': _clientType.value,
        });
        if (raw != null) {
          final streams = VideoStreams.fromMap(raw);
          if (streams.playbackUrl != null) return streams;
        }
      } catch (e) {
        debugPrint('[MusicService] $_engine video error: $e');
      }
    }
    if (_enableFallback || _skipNative) return _dartService.getVideoStreams(videoId);
    throw Exception('Video unavailable');
  }

  @override
  Future<void> muxVideo(String video, String audio, String output) async {
    await _ch.invokeMethod<String>(
        'muxVideo', {'video': video, 'audio': audio, 'output': output});
  }

  @override
  Future<String> updateExtractor() async {
    if (!Platform.isIOS) return 'Only available on iOS';
    final r = await _ch.invokeMapMethod<String, dynamic>('updateExtractor');
    final installed = r?['installed'];
    final running = r?['running'];
    return r?['restartRequired'] == true
        ? 'yt-dlp $installed downloaded — restart the app to use it'
        : 'yt-dlp $running is up to date';
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
  Future<StreamInfo> getStreamInfo(String videoId) async =>
      StreamInfo(await getStreamUrl(videoId), _defaultStreamHeaders);

  @override
  Future<String> updateExtractor() async => 'Not supported by the Dart extractor';

  @override
  Future<VideoStreams> getVideoStreams(String videoId) async {
    final m = await _yt.videos.streams.getManifest(videoId);
    return VideoStreams(
      headers: _defaultStreamHeaders,
      formats: [
        for (final s in m.muxed)
          VideoFormat(
            url: s.url.toString(),
            kind: 'muxed',
            ext: s.container.name,
            height: s.videoResolution.height,
            bitrate: s.bitrate.bitsPerSecond,
            vcodec: s.videoCodec,
            acodec: s.audioCodec,
          ),
        for (final s in m.videoOnly)
          VideoFormat(
            url: s.url.toString(),
            kind: 'video',
            ext: s.container.name,
            height: s.videoResolution.height,
            bitrate: s.bitrate.bitsPerSecond,
            vcodec: s.videoCodec,
          ),
        for (final s in m.audioOnly)
          VideoFormat(
            url: s.url.toString(),
            kind: 'audio',
            ext: s.container.name == 'mp4' ? 'm4a' : s.container.name,
            bitrate: s.bitrate.bitsPerSecond,
            acodec: s.audioCodec,
          ),
      ],
    );
  }

  @override
  Future<void> muxVideo(String video, String audio, String output) =>
      throw UnsupportedError('Muxing needs the native platform channel');

  @override
  Future<String> getStreamUrl(String videoId) async {
    final manifest = await _yt.videos.streams.getManifest(videoId);
    var candidates = manifest.audioOnly.toList();
    if (candidates.isEmpty) {
      throw Exception('No audio streams for $videoId');
    }
    if (Platform.isIOS) {
      // AVPlayer cannot decode WebM/Opus — restrict to MP4/AAC when available.
      final mp4 =
          candidates.where((s) => s.container == StreamContainer.mp4).toList();
      if (mp4.isNotEmpty) candidates = mp4;
    }

    final sorted = candidates
      ..sort((a, b) => a.bitrate.compareTo(b.bitrate));

    switch (_audioQuality) {
      case AudioQuality.low:
        return sorted.first.url.toString();
      case AudioQuality.medium:
        return sorted[sorted.length ~/ 2].url.toString();
      case AudioQuality.high:
        return sorted.last.url.toString();
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
