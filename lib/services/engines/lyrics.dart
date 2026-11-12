/// A timed lyric line.
class LyricLine {
  final Duration time;
  final String text;
  const LyricLine(this.time, this.text);
}

/// Lyrics for one track: time-synced lines when available, else plain text.
class Lyrics {
  final List<LyricLine> synced;
  final String? plain;

  const Lyrics({this.synced = const [], this.plain});

  bool get isSynced => synced.isNotEmpty;

  Map<String, dynamic> toJson() => {
        if (synced.isNotEmpty)
          'synced': [for (final l in synced) [l.time.inMilliseconds, l.text]],
        if (plain != null) 'plain': plain,
      };

  factory Lyrics.fromJson(Map<String, dynamic> j) => Lyrics(
        synced: [
          for (final l in (j['synced'] as List?) ?? const [])
            LyricLine(Duration(milliseconds: (l[0] as num).toInt()), l[1] as String),
        ],
        plain: j['plain'] as String?,
      );
  bool get isEmpty => synced.isEmpty && (plain == null || plain!.trim().isEmpty);

  /// Bugs synced format: "0.3|first line＃8.9|second line＃…" (full-width ＃).
  static List<LyricLine> parseBugsSynced(String raw) {
    final lines = <LyricLine>[];
    for (final part in raw.split('＃')) {
      final bar = part.indexOf('|');
      if (bar <= 0) continue;
      final seconds = double.tryParse(part.substring(0, bar).trim());
      if (seconds == null) continue;
      lines.add(LyricLine(
        Duration(milliseconds: (seconds * 1000).round()),
        part.substring(bar + 1).trim(),
      ));
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// LRC format: "[mm:ss.xx] line" per line; blank lines mark instrumental gaps.
  static List<LyricLine> parseLrc(String raw) {
    final lines = <LyricLine>[];
    final stamp = RegExp(r'\[(\d+):(\d+(?:\.\d+)?)\]');
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final stamps = stamp.allMatches(line).toList();
      if (stamps.isEmpty) continue; // metadata tags like [ar:…] have no digits
      final text = line.substring(stamps.last.end).trim();
      for (final m in stamps) {
        final ms = (int.parse(m.group(1)!) * 60000) +
            (double.parse(m.group(2)!) * 1000).round();
        lines.add(LyricLine(Duration(milliseconds: ms), text));
      }
    }
    lines.sort((a, b) => a.time.compareTo(b.time));
    return lines;
  }

  /// Index of the line being sung at [position], or -1 before the first line.
  int indexAt(Duration position) {
    var lo = 0, hi = synced.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (synced[mid].time <= position) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return found;
  }
}
