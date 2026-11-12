import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oye/models/track.dart';
import 'package:oye/services/engines/bugs_client.dart';
import 'package:oye/services/engines/lrclib_client.dart';
import 'package:oye/services/engines/ytmusic_client.dart';
import 'package:oye/services/metadata_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// In-memory stand-in for DownloadService's offline storage.
class _Store implements OfflineStore {
  final downloaded = <String>{};
  final lyrics = <String, String>{};
  final covers = <String, String>{};
  @override
  bool isDownloaded(String id) => downloaded.contains(id);
  @override
  Future<void> saveCover(String id, String url) async => covers[id] = url;
  @override
  Future<String?> readLyrics(String id) async => lyrics[id];
  @override
  Future<void> writeLyrics(String id, String json) async {
    if (isDownloaded(id)) lyrics[id] = json;
  }
  @override
  Future<void> deleteLyrics(String id) async => lyrics.remove(id);
}

String fixture(String n) => File('test/fixtures/$n').readAsStringSync();

/// Bugs as captured; YouTube Music has no song catalogue (as when captured).
MockClient online() => MockClient((req) async {
      final url = req.url.toString();
      if (url.contains('bugs.co.kr/search/track')) {
        return http.Response.bytes(utf8.encode(fixture('bugs_search_iu.html')), 200);
      }
      if (url.contains('bugs.co.kr/player/lyrics/T/')) {
        return http.Response.bytes(utf8.encode(fixture('bugs_lyrics_synced.json')), 200);
      }
      if (url.contains('youtubei/v1/search')) {
        return http.Response.bytes(utf8.encode(fixture('ytm_search_unfiltered.json')), 200);
      }
      if (url.contains('lrclib')) return http.Response('[]', 200);
      return http.Response('', 404);
    });

/// Airplane mode.
MockClient offline() => MockClient((_) async => throw const SocketException('offline'));

MetadataService service(SharedPreferences prefs, http.Client c, _Store store) =>
    MetadataService(prefs, YtmClient(client: c), BugsClient(client: c), LrclibClient(client: c))
      ..offline = store;

const _track = Track(videoId: 'EjMTw4xLcBI', title: '아이유(IU) - 밤편지 [가사/Lyrics]', artist: '웅키', thumbnail: '');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('downloading saves cover and synced lyrics; both work offline', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _Store()..downloaded.add(_track.videoId);

    await service(prefs, online(), store).saveOffline(_track);
    // No YouTube Music song here, so Bugs' album cover of the matched song is saved.
    expect(store.covers[_track.videoId], contains('image.bugsm.co.kr/album/images/500/'));
    expect(store.lyrics[_track.videoId], isNotNull);

    final r = await service(prefs, offline(), store).lyricsFor(_track);
    expect(r.provider, '벅스');
    expect(r.lyrics!.isSynced, isTrue);
    expect(r.lyrics!.synced.first.text, '이 밤 그날의 반딧불을');
    expect(r.lyrics!.synced.first.time, const Duration(milliseconds: 300));
  });

  test('songs that are not downloaded do not write lyrics', () async {
    final store = _Store();
    await service(await SharedPreferences.getInstance(), online(), store).lyricsFor(_track);
    expect(store.lyrics, isEmpty);
  });

  test('a manual re-match replaces the saved lyrics', () async {
    final prefs = await SharedPreferences.getInstance();
    final store = _Store()..downloaded.add(_track.videoId);
    final meta = service(prefs, online(), store);
    await meta.saveOffline(_track);
    final before = store.lyrics[_track.videoId];

    const other = BugsTrack(id: '999', title: 'Other', artist: 'X', album: 'Y');
    await meta.setLyricsSource(_track, other);
    expect(store.lyrics.containsKey(_track.videoId), isFalse);
    final r = await meta.lyricsFor(_track);
    expect(r.bugs?.id, '999');
    expect(store.lyrics[_track.videoId], isNot(before));
  });
}
