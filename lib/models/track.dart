class Track {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnail;
  final String duration;
  final int durationSec;

  const Track({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnail,
    this.duration = '0:00',
    this.durationSec = 0,
  });

  factory Track.fromMap(Map<dynamic, dynamic> m) {
    final durSec = (m['durationSec'] as num?)?.toInt() ?? 0;
    final dur = m['duration'] as String? ?? _secToString(durSec);
    return Track(
      videoId: m['videoId'] as String,
      title: m['title'] as String? ?? 'Unknown',
      artist: m['artist'] as String? ?? '',
      thumbnail: m['thumbnail'] as String? ?? '',
      duration: dur,
      durationSec: durSec,
    );
  }

  Map<String, dynamic> toMap() => {
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnail': thumbnail,
        'duration': duration,
        'durationSec': durationSec,
      };

  static String _secToString(int sec) {
    final m = sec ~/ 60;
    final s = sec % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  bool operator ==(Object other) => other is Track && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;
}
