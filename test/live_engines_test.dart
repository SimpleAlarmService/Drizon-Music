// Hits the real YouTube Music and Bugs services. Skipped unless DRIZON_LIVE=1:
//   DRIZON_LIVE=1 flutter test test/live_engines_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oye/models/track.dart';
import 'package:oye/services/engines/bugs_client.dart';
import 'package:oye/services/engines/lrclib_client.dart';
import 'package:oye/services/engines/matching.dart';
import 'package:oye/services/engines/ytmusic_client.dart';
import 'package:oye/services/metadata_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _skip = Platform.environment['DRIZON_LIVE'] == '1' ? false : 'set DRIZON_LIVE=1';

void main() {
  test('YouTube Music search returns playable items', () async {
    final items = await YtmClient().search('아이유 밤편지');
    for (final i in items.take(6)) {
      // ignore: avoid_print
      print('${i.kind.name.padRight(10)} ${i.videoId} | ${i.title} | ${i.artist} | '
          '${i.album ?? '-'} | ${i.durationSec}s | art=${i.albumArt != null}');
    }
    expect(items, isNotEmpty);
    expect(items.every((i) => i.videoId.length == 11), isTrue);
  }, skip: _skip);

  test('YouTube Music suggestions', () async {
    final s = await YtmClient().suggestions('아이유 밤');
    // ignore: avoid_print
    print(s);
    expect(s, isNotEmpty);
  }, skip: _skip);

  test('video title → Bugs match → synced lyrics', () async {
    final bugs = BugsClient();
    for (final (title, artist) in [
      ('아이유(IU) - 밤편지 [가사/Lyrics]', '웅키'), // fan upload, artist in title
      ('밤편지', '아이유'), // MV by the artist
      ('The Weeknd - Blinding Lights (Official Video)', 'TheWeekndVEVO'),
      ('Justin Bieber - Peaches ft. Daniel Caesar, Giveon', 'JustinBieberVEVO'),
      ('Dynamite', 'BTS - Topic'),
    ]) {
      final q = SongQuery.from(title: title, artist: artist);
      final (best, candidates) = await bugs.match(q);
      final lyrics = best == null ? null : await bugs.lyrics(best.id);
      // ignore: avoid_print
      print('"$title" → query(${q.title} / ${q.artist}) → '
          '${best == null ? 'NO MATCH' : '${best.id} ${best.title} / ${best.artist} / ${best.album}'}'
          ' (${candidates.length} candidates) · '
          '${lyrics == null ? 'no lyrics' : lyrics.isSynced ? '${lyrics.synced.length} synced lines, first: "${lyrics.synced.first.text}"' : 'plain'}');
      expect(best, isNotNull, reason: title);
      expect(lyrics?.isSynced, isTrue, reason: title);
    }
  }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));

  test('LRCLIB fallback finds synced lyrics within ±5 s', () async {
    final q = SongQuery.from(title: 'Through the Night (밤편지)', artist: 'IU', durationSec: 253);
    final r = await LrclibClient().match(q);
    // ignore: avoid_print
    print('LRCLIB → ${r?.id} ${r?.title} / ${r?.artist} / ${r?.duration}s synced=${r?.synced != null}');
    expect(r, isNotNull);
    expect(r!.toLyrics()!.isSynced, isTrue);
  }, skip: _skip);

  test('MetadataService: lyrics chain end to end', () async {
    SharedPreferences.setMockInitialValues({});
    final meta = MetadataService(
        await SharedPreferences.getInstance(), YtmClient(), BugsClient());
    for (final t in [
      const Track(videoId: 'EjMTw4xLcBI', title: '아이유(IU) - 밤편지 [가사/Lyrics]', artist: '웅키', thumbnail: ''),
      const Track(videoId: 'xxxxxxxxxxx', title: 'Dynamite', artist: 'BTS - Topic', thumbnail: ''),
    ]) {
      final r = await meta.lyricsFor(t);
      // ignore: avoid_print
      print('${t.title} → ${r.provider} · ${r.sourceTitle} / ${r.sourceArtist} · '
          'synced=${r.lyrics?.isSynced} lines=${r.lyrics?.synced.length}');
      expect(r.found, isTrue);
    }
  }, skip: _skip, timeout: const Timeout(Duration(minutes: 2)));
}
