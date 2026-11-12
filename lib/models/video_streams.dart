/// One downloadable/playable format of a YouTube video.
class VideoFormat {
  final String url;
  final String kind; // muxed | video | audio
  final String ext;
  final int height;
  final int bitrate;
  final String vcodec;
  final String acodec;

  const VideoFormat({
    required this.url,
    required this.kind,
    this.ext = '',
    this.height = 0,
    this.bitrate = 0,
    this.vcodec = '',
    this.acodec = '',
  });

  factory VideoFormat.fromMap(Map<dynamic, dynamic> m) => VideoFormat(
        url: m['url'] as String,
        kind: m['kind'] as String? ?? 'muxed',
        ext: m['ext'] as String? ?? '',
        height: (m['height'] as num?)?.toInt() ?? 0,
        bitrate: (m['bitrate'] as num?)?.toInt() ?? 0,
        vcodec: m['vcodec'] as String? ?? '',
        acodec: m['acodec'] as String? ?? '',
      );

  bool get isMp4 => ext == 'mp4' || ext == 'm4a';
  bool get isH264 => vcodec.startsWith('avc1') || vcodec.startsWith('avc');
  bool get isAac => acodec.startsWith('mp4a') || ext == 'm4a';
}

/// How to fetch a video at a chosen quality.
class VideoDownloadPlan {
  final int height;
  final VideoFormat video; // muxed file, or video-only when [audio] is set
  final VideoFormat? audio; // set when the two must be joined after download

  const VideoDownloadPlan({required this.height, required this.video, this.audio});
  bool get needsMux => audio != null;
}

/// All formats for a video, as returned by the platform extractor.
class VideoStreams {
  final Map<String, String> headers;
  final String? hls;
  final List<VideoFormat> formats;
  final int durationSec;

  const VideoStreams({
    this.headers = const {},
    this.hls,
    this.formats = const [],
    this.durationSec = 0,
  });

  factory VideoStreams.fromMap(Map<dynamic, dynamic> m) => VideoStreams(
        headers: {
          for (final e in ((m['headers'] as Map?) ?? const {}).entries)
            e.key.toString(): e.value.toString(),
        },
        hls: (m['hls'] as String?)?.isEmpty == true ? null : m['hls'] as String?,
        formats: [
          for (final f in (m['formats'] as List?) ?? const [])
            VideoFormat.fromMap(f as Map),
        ],
        durationSec: (m['durationSec'] as num?)?.toInt() ?? 0,
      );

  List<VideoFormat> _of(String kind) => formats.where((f) => f.kind == kind).toList();

  /// The best AAC audio track (needed to build 720p+ downloads).
  VideoFormat? get bestAacAudio {
    final aac = _of('audio').where((f) => f.isAac).toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    return aac.isEmpty ? null : aac.first;
  }

  /// URL to stream: HLS when offered (adaptive quality; native on AVPlayer and
  /// ExoPlayer), otherwise the highest muxed MP4.
  String? get playbackUrl {
    if (hls != null) return hls;
    final muxed = _of('muxed')..sort((a, b) => b.height.compareTo(a.height));
    final mp4 = muxed.where((f) => f.isMp4);
    return mp4.isNotEmpty ? mp4.first.url : (muxed.isEmpty ? null : muxed.first.url);
  }

  /// Download qualities we can produce as a single MP4 (H.264 + AAC), highest first.
  List<int> get downloadHeights {
    final heights = <int>{
      for (final f in _of('muxed').where((f) => f.isMp4 && f.height > 0)) f.height,
      if (bestAacAudio != null)
        for (final f in _of('video').where((f) => f.isMp4 && f.isH264 && f.height > 0)) f.height,
    };
    return heights.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Muxed file when one exists at [height], else video-only + audio to join.
  VideoDownloadPlan? planFor(int height) {
    final muxed = _of('muxed').where((f) => f.isMp4 && f.height == height).toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (muxed.isNotEmpty) return VideoDownloadPlan(height: height, video: muxed.first);

    final audio = bestAacAudio;
    final video = _of('video').where((f) => f.isMp4 && f.isH264 && f.height == height).toList()
      ..sort((a, b) => b.bitrate.compareTo(a.bitrate));
    if (audio == null || video.isEmpty) return null;
    return VideoDownloadPlan(height: height, video: video.first, audio: audio);
  }
}
