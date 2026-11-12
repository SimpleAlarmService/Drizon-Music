// Parsers and matchers, run against responses captured from the real services
// (test/fixtures). The songs-filter item below is synthesized: the capture
// region had no YouTube Music song catalogue, so it follows the same verified
// renderer structure with an ATV video type, album link and duration.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oye/services/engines/bugs_client.dart';
import 'package:oye/services/engines/lrclib_client.dart';
import 'package:oye/services/engines/lyrics.dart';
import 'package:oye/services/engines/matching.dart';
import 'package:oye/services/engines/ytmusic_client.dart';

String fixture(String name) => File('test/fixtures/$name').readAsStringSync();
Map<String, dynamic> jsonFixture(String name) =>
    jsonDecode(fixture(name)) as Map<String, dynamic>;

Map<String, dynamic> _run(String text, {String? pageType, String? browseId}) => {
      'text': text,
      if (pageType != null)
        'navigationEndpoint': {
          'browseEndpoint': {
            'browseId': browseId ?? 'X',
            'browseEndpointContextSupportedConfigs': {
              'browseEndpointContextMusicConfig': {'pageType': pageType},
            },
          },
        },
    };

Map<String, dynamic> songItem() => {
      'contents': [
        {
          'musicResponsiveListItemRenderer': {
            'thumbnail': {
              'musicThumbnailRenderer': {
                'thumbnail': {
                  'thumbnails': [
                    {'url': 'https://lh3.googleusercontent.com/abc=w60-h60-l90-rj'},
                    {'url': 'https://lh3.googleusercontent.com/abc=w120-h120-l90-rj'},
                  ],
                },
              },
            },
            'flexColumns': [
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      {
                        'text': '밤편지',
                        'navigationEndpoint': {
                          'watchEndpoint': {
                            'videoId': 'BzYnNdJhZQw',
                            'watchEndpointMusicSupportedConfigs': {
                              'watchEndpointMusicConfig': {'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV'},
                            },
                          },
                        },
                      },
                    ],
                  },
                },
              },
              {
                'musicResponsiveListItemFlexColumnRenderer': {
                  'text': {
                    'runs': [
                      _run('노래'),
                      _run(' • '),
                      _run('아이유', pageType: 'MUSIC_PAGE_TYPE_ARTIST'),
                      _run(' • '),
                      _run('Palette', pageType: 'MUSIC_PAGE_TYPE_ALBUM'),
                      _run(' • '),
                      _run('4:14'),
                    ],
                  },
                },
              },
            ],
          },
        },
      ],
    };

void main() {
  group('YouTube Music parser', () {
    test('parses captured search: videos with artists, no podcast episodes', () {
      final items = YtmClient.parseSearch(jsonFixture('ytm_search_unfiltered.json'));
      expect(items, isNotEmpty);
      expect(items.every((i) => i.videoId.length == 11), isTrue);
      final mv = items.firstWhere((i) => i.videoId == 'DFzPmaNb7fk');
      expect(mv.title, '밤편지');
      expect(mv.artist, '아이유');
      expect(mv.kind, YtmKind.musicVideo);
      // The top-result card includes the duration in its subtitle.
      expect(items.firstWhere((i) => i.videoId == 'EjMTw4xLcBI').durationSec, 254);
      expect(items.any((i) => i.artist == '에피소드'), isFalse);
    });

    test('ranks songs before music videos before other videos', () {
      final items = YtmClient.rank([
        ...YtmClient.parseSearch(jsonFixture('ytm_search_unfiltered.json')),
        ...YtmClient.parseSearch(songItem()),
      ]);
      expect(items.first.kind, YtmKind.song);
      expect(items.indexWhere((i) => i.kind == YtmKind.video),
          greaterThan(items.indexWhere((i) => i.kind == YtmKind.musicVideo)));
    });

    test('song item: artist, album, duration and a large square cover', () {
      final song = YtmClient.parseSearch(songItem()).single;
      expect(song.kind, YtmKind.song);
      expect(song.artist, '아이유');
      expect(song.album, 'Palette');
      expect(song.durationSec, 254);
      expect(song.albumArt, 'https://lh3.googleusercontent.com/abc=w544-h544-l90-rj');
      expect(song.toTrack().albumArt, song.albumArt);
    });

    test('no songs filter chip in a region without the catalogue', () {
      expect(YtmClient.songsFilterParams(jsonFixture('ytm_search_unfiltered.json')), isNull);
    });

    test('suggestions', () {
      final s = YtmClient.parseSuggestions(jsonFixture('ytm_suggestions.json'));
      expect(s, contains('아이유 밤편지'));
    });
  });

  group('Bugs parser', () {
    test('search rows: id, title, artist, album, 500px cover', () {
      final rows = BugsClient.parseSearch(fixture('bugs_search_iu.html'));
      final first = rows.first;
      expect(first.id, '30598121');
      expect(first.title, '밤편지');
      expect(first.artist, '아이유(IU)');
      expect(first.album, '밤편지');
      expect(first.imageUrl, contains('/album/images/500/'));
    });

    test('adult-only rows (19금 badge) still parse', () {
      final rows = BugsClient.parseSearch(fixture('bugs_search_peaches.html'));
      expect(rows.first.title, 'Peaches (feat. Daniel Caesar, Giveon)');
      expect(rows.first.artist, 'Justin Bieber(저스틴 비버)');
    });

    test('synced and plain lyrics', () {
      final synced = Lyrics.parseBugsSynced(
          (jsonDecode(fixture('bugs_lyrics_synced.json')) as Map)['lyrics'] as String);
      expect(synced.first.text, '이 밤 그날의 반딧불을');
      expect(synced.first.time, const Duration(milliseconds: 300));
      final l = Lyrics(synced: synced);
      expect(l.indexAt(Duration.zero), -1);
      expect(l.indexAt(const Duration(seconds: 10)), 1);
      expect(l.indexAt(const Duration(hours: 1)), synced.length - 1);
    });

    test('picks the original over covers and karaoke', () {
      final q = SongQuery.from(title: 'Justin Bieber - Peaches ft. Daniel Caesar', artist: 'VEVO');
      final best = BugsClient.pickBest(q, BugsClient.parseSearch(fixture('bugs_search_peaches.html')));
      expect(best?.id, '76991876');
    });

    test('prefers the single/album original, not a cover band', () {
      final q = SongQuery.from(title: 'Blinding Lights', artist: 'The Weeknd - Topic', isSong: true);
      final best = BugsClient.pickBest(q, BugsClient.parseSearch(fixture('bugs_search_weeknd.html')));
      expect(best?.artist, startsWith('The Weeknd'));
    });
  });

  group('LRC / LRCLIB', () {
    test('parses LRC with blank instrumental lines and multi-stamps', () {
      final lines = Lyrics.parseLrc('[ar: x]\n[00:01.50] a\n[00:03.00]\n[00:05.00][00:09.25] chorus');
      expect(lines.map((l) => l.text), ['a', '', 'chorus', 'chorus']);
      expect(lines.last.time, const Duration(milliseconds: 9250));
    });

    test('duration within ±5 s, synced preferred, instrumental skipped', () {
      final records = LrclibClient.parseSearch(fixture('lrclib_search_iu.json'));
      final q = SongQuery.from(title: '밤편지', artist: 'IU', durationSec: 253, isSong: true);
      final best = LrclibClient.pickBest(q, records)!;
      expect(best.instrumental, isFalse);
      expect((best.duration - 253).abs(), lessThanOrEqualTo(5));
      expect(best.toLyrics()!.isSynced, isTrue);

      final far = SongQuery.from(title: '밤편지', artist: 'IU', durationSec: 400, isSong: true);
      expect(LrclibClient.pickBest(far, records), isNull);
    });
  });

  group('matching', () {
    test('"Artist - Title" uploads by someone else', () {
      final q = SongQuery.from(title: '아이유(IU) - 밤편지 [가사/Lyrics]', artist: '웅키');
      expect(q.title, '밤편지');
      expect(q.artist, '아이유(IU)');
      expect(q.primaryArtist, '아이유');
      expect(q.searchTerms, ['밤편지 아이유', '밤편지']);
    });

    test('"Title - Artist" is recognised too', () {
      final q = SongQuery.from(title: 'Blinding Lights - The Weeknd', artist: 'The Weeknd');
      expect(q.title, 'Blinding Lights');
    });

    test('bracketed alternate titles match across languages', () {
      expect(titleSimilarity('밤편지', 'Through the Night (밤편지)'), 1.0);
      expect(titleAliases('Peaches (feat. Daniel Caesar)'), {'peaches'});
    });

    test('artist aliases', () {
      expect(artistAliases('아이유(IU)'), {'아이유', 'iu'});
      expect(artistSimilarity('IU', '아이유(IU)'), 1.0);
      expect(artistSimilarity('BTS - Topic', 'BTS'), 1.0);
    });

    test('a top result of an artist search is trusted despite different names', () {
      final q = SongQuery.from(title: 'Dynamite', artist: 'BTS - Topic', isSong: true);
      final plain = q.score(candidateTitle: 'Dynamite', candidateArtist: '방탄소년단');
      final trusted = q.score(
          candidateTitle: 'Dynamite', candidateArtist: '방탄소년단', rankInArtistSearch: 0);
      expect(plain, lessThan(matchThreshold));
      expect(trusted, greaterThanOrEqualTo(matchThreshold));
      // ...but never a cover, even at the top.
      expect(
          q.score(
              candidateTitle: 'Dynamite',
              candidateArtist: 'Acoustic Heartstrings',
              candidateAlbum: 'Acoustic Guitar Renditions of BTS',
              rankInArtistSearch: 0),
          lessThan(matchThreshold));
    });

    test('alternate versions are penalised unless asked for', () {
      final q = SongQuery.from(title: 'Dynamite', artist: 'BTS', isSong: true);
      expect(q.score(candidateTitle: 'Dynamite (Holiday Remix)', candidateArtist: 'BTS'),
          lessThan(q.score(candidateTitle: 'Dynamite', candidateArtist: 'BTS')));
    });
  });
}
