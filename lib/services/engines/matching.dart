/// Fuzzy text matching shared by album-art matching (YouTube video → YouTube
/// Music song) and lyrics matching (any track → Bugs track).
library;

/// Phrases YouTube uploads add to titles that are not part of the song name.
final _noise = RegExp(
  r'\b(official|offical|music|video|audio|lyrics?|lyric video|visualizer|mv|m/v|'
  r'performance|teaser|full ver\.?|hd|4k|1080p|가사|뮤직비디오|공식|직캠)\b',
  caseSensitive: false,
);

/// Markers of covers / karaoke / tribute uploads.
const coverMarkers = [
  'made popular by', 'originally performed', 'cover', 'karaoke', 'tribute',
  'in the style of', '커버', '노래방', 'instrumental', 'party tyme',
  'rendition', 'lullaby', 'music box', '오르골', 'acoustic guitar', '연주곡',
];

/// Markers of alternate versions; penalised when the source title lacks them.
const versionMarkers = [
  'remix', 'live', 'inst', 'acoustic', 'sped up', 'slowed', 'nightcore',
  'mr', 'remaster', 'demo', 'edit', 'ver.', 'version', 'piano', 'orchestra',
];

/// Lower-cased, punctuation/space-free text (keeps Hangul, kana, CJK, Latin, digits).
String norm(String s) => s
    .toLowerCase()
    .replaceAll('&amp;', '&')
    .replaceAll(RegExp(r'[^0-9a-zÀ-ɏ぀-ヿ㄰-㆏一-鿿가-힣]'), '');

/// Song title without brackets, "feat.", "|" suffixes and upload noise.
String coreTitle(String title) {
  var t = title;
  final bar = t.indexOf(RegExp(r'\s[|｜]\s'));
  if (bar > 0) t = t.substring(0, bar);
  t = t.replaceAll(RegExp(r'[\(\[【「『（].*?[\)\]】」』）]'), ' ');
  t = t.replaceAll(RegExp(r'\s(feat\.?|ft\.?|prod\.?|with)\s.*$', caseSensitive: false), ' ');
  t = t.replaceAll(_noise, ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Every name a song title could stand for: "Through the Night (밤편지)" →
/// {through the night, 밤편지}. Bracketed parts that are credits or upload
/// noise (feat., Official MV, Remix…) are not titles and are skipped.
Set<String> titleAliases(String title) {
  final out = {norm(coreTitle(title))};
  for (final m in RegExp(r'[\(\[（【]([^\)\]）】]+)[\)\]）】]').allMatches(title)) {
    final inner = m.group(1)!;
    if (RegExp(r'(feat|ft\.|prod|with |remix|ver|version|live|inst|mv|m/v|official|lyrics?|가사|audio)',
            caseSensitive: false)
        .hasMatch(inner)) {
      continue;
    }
    out.add(norm(inner));
  }
  return out..removeWhere((s) => s.isEmpty);
}

double titleSimilarity(String a, String b) {
  var best = 0.0;
  for (final x in titleAliases(a)) {
    for (final y in titleAliases(b)) {
      final s = similarity(x, y);
      if (s > best) best = s;
    }
  }
  return best;
}

/// Every name an artist string could stand for: "아이유(IU)" → {아이유, iu};
/// "A & B feat. C" → {a, b, c}; YouTube channel suffixes are dropped.
Set<String> artistAliases(String artist) {
  final cleaned = artist
      .replaceAll(RegExp(r'\s-\s*topic$', caseSensitive: false), '')
      .replaceAll(RegExp(r'(vevo|official|offical)$', caseSensitive: false), '');
  return cleaned
      .split(RegExp(r'[\(\)（）,&/·]|\s(?:x|X|feat\.?|ft\.?|and|with)\s'))
      .map(norm)
      .where((s) => s.isNotEmpty)
      .toSet();
}

/// 0..1 similarity of two already-normalised strings.
double similarity(String a, String b) {
  if (a.isEmpty || b.isEmpty) return 0;
  if (a == b) return 1;
  final shorter = a.length < b.length ? a : b;
  final longer = a.length < b.length ? b : a;
  if (longer.contains(shorter)) return 0.7 + 0.3 * shorter.length / longer.length;
  return _dice(a, b);
}

double _dice(String a, String b) {
  if (a.length < 2 || b.length < 2) return 0;
  final grams = <String, int>{};
  for (var i = 0; i < a.length - 1; i++) {
    final g = a.substring(i, i + 2);
    grams[g] = (grams[g] ?? 0) + 1;
  }
  var hits = 0;
  for (var i = 0; i < b.length - 1; i++) {
    final g = b.substring(i, i + 2);
    final n = grams[g] ?? 0;
    if (n > 0) {
      grams[g] = n - 1;
      hits++;
    }
  }
  return 2 * hits / (a.length - 1 + b.length - 1);
}

double artistSimilarity(String a, String b) {
  final as = artistAliases(a), bs = artistAliases(b);
  var best = 0.0;
  for (final x in as) {
    for (final y in bs) {
      final s = similarity(x, y);
      if (s > best) best = s;
    }
  }
  return best;
}

/// What we know about the song being looked up.
class SongQuery {
  final String title; // cleaned song title
  final String artist; // best guess of the performing artist
  final String rawTitle;
  final String? album;
  final int durationSec;

  const SongQuery({
    required this.title,
    required this.artist,
    required this.rawTitle,
    this.album,
    this.durationSec = 0,
  });

  /// Builds a query from a track. Videos are often titled "Artist - Title" and
  /// uploaded by someone else, so that pattern overrides the channel name.
  factory SongQuery.from({
    required String title,
    required String artist,
    String? album,
    int durationSec = 0,
    bool isSong = false,
  }) {
    var songTitle = title;
    var songArtist = artist;
    if (!isSong) {
      final m = RegExp(r'^(.+?)\s+[-–—]\s+(.+)$').firstMatch(title);
      if (m != null) {
        final left = m.group(1)!, right = m.group(2)!;
        if (artistSimilarity(right, artist) > artistSimilarity(left, artist) &&
            artistSimilarity(right, artist) >= 0.8) {
          songTitle = left; // "Title - Artist"
          songArtist = right;
        } else {
          songTitle = right; // "Artist - Title" (also when uploader ≠ artist)
          songArtist = left;
        }
      }
    }
    return SongQuery(
      title: coreTitle(songTitle),
      artist: songArtist
          .replaceAll(RegExp(r'\s-\s*topic$', caseSensitive: false), '')
          .trim(),
      rawTitle: title,
      album: album,
      durationSec: durationSec,
    );
  }

  /// [title] plus any bracketed alternate title from the original upload.
  String get rawTitleForMatch {
    final alt = titleAliases(rawTitle).difference({norm(title)});
    return alt.isEmpty ? title : '$title (${alt.join(') (')})';
  }

  /// First credited artist without alternate names: "아이유(IU)" → "아이유".
  String get primaryArtist => artist
      .split(RegExp(r'[\(（,&]|\s(?:feat\.?|ft\.?|x)\s', caseSensitive: false))
      .first
      .trim();

  /// Whether [searchTerms]`[i]` includes the artist name.
  bool termHasArtist(int i) => i == 0 && searchTerms.length > 1;

  /// Search strings to try, most specific first.
  List<String> get searchTerms {
    return {
      if (primaryArtist.isNotEmpty) '$title $primaryArtist',
      title,
    }.where((s) => s.trim().isNotEmpty).toList();
  }

  /// 0..~1.1 score of a candidate song against this query.
  ///
  /// [rankInArtistSearch] is the candidate's position in results of a search
  /// that already included the artist name. The catalogue's own search maps
  /// names we can't (e.g. "BTS" → "방탄소년단"), so a top result with an exact
  /// title is trusted even when the artist strings don't look alike.
  double score({
    required String candidateTitle,
    required String candidateArtist,
    String? candidateAlbum,
    int candidateDurationSec = 0,
    int? rankInArtistSearch,
  }) {
    final t = titleSimilarity(rawTitleForMatch, candidateTitle);
    var a = artistSimilarity(artist, candidateArtist);
    if (rankInArtistSearch != null && rankInArtistSearch < 3 && t >= 0.95 && a < 0.6) {
      a = 0.6 - 0.1 * rankInArtistSearch;
    }
    var s = 0.6 * t + 0.4 * a;

    if (album != null && candidateAlbum != null &&
        similarity(norm(album!), norm(candidateAlbum)) >= 0.85) {
      s += 0.08;
    }
    if (durationSec > 0 && candidateDurationSec > 0) {
      final d = (durationSec - candidateDurationSec).abs();
      if (d <= 3) {
        s += 0.08;
      } else if (d > 20) {
        s -= 0.2;
      }
    }

    final source = rawTitle.toLowerCase();
    final cand = '$candidateTitle $candidateArtist ${candidateAlbum ?? ''}'.toLowerCase();
    for (final m in coverMarkers) {
      if (cand.contains(m) && !source.contains(m)) {
        s -= 0.4;
        break;
      }
    }
    final candTitle = candidateTitle.toLowerCase();
    for (final m in versionMarkers) {
      if (RegExp('(^|[^a-z])${RegExp.escape(m)}([^a-z]|\$)').hasMatch(candTitle) &&
          !source.contains(m)) {
        s -= 0.15;
      }
    }
    return s;
  }
}

/// Minimum score for an automatic match.
const matchThreshold = 0.62;
