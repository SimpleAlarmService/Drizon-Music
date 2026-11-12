import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oye/models/settings_model.dart';
import 'package:oye/models/track.dart';
import 'package:oye/services/download_service.dart';
import 'package:oye/services/music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Music implements MusicService {
  _Music(this.url);
  final String url;
  @override
  Future<StreamInfo> getStreamInfo(String id) async =>
      StreamInfo(url, const {'User-Agent': 'test-agent'});
  @override
  Future<String> getStreamUrl(String id) async => url;
  @override
  Future<List<Track>> search(String q) async => const [];
  @override
  Future<String> updateExtractor() async => '';
  @override
  void applySettings(AppSettings s) {}
  @override
  Future<void> dispose() async {}
}

const _track = Track(videoId: 'abcdefghijk', title: 'Song', artist: 'Artist', thumbnail: '');

void main() {
  late Directory tmp;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('drizon_dl');
  });
  tearDown(() => tmp.delete(recursive: true));

  Future<void> settle(DownloadService d) async {
    for (var i = 0; i < 200 && d.status(_track.videoId) != DownloadStatus.done &&
        d.status(_track.videoId) != DownloadStatus.failed; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('downloads in Range chunks, then plays from disk', () async {
    // 25 MB file → three 10 MB range requests.
    final body = Uint8List(25 * 1024 * 1024)..[123] = 7;
    final ranges = <String>[];
    final client = MockClient.streaming((req, _) async {
      expect(req.headers['User-Agent'], 'test-agent');
      final range = req.headers['Range']!;
      ranges.add(range);
      final m = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
      final start = int.parse(m.group(1)!);
      final end = (int.parse(m.group(2)!)).clamp(0, body.length - 1);
      return http.StreamedResponse(
        Stream.value(body.sublist(start, end + 1)),
        206,
        headers: {'content-range': 'bytes $start-$end/${body.length}'},
      );
    });
    final prefs = await SharedPreferences.getInstance();
    final d = DownloadService(prefs, _Music('https://rr.googlevideo.com/videoplayback?mime=audio%2Fmp4'),
        client: client, directory: () async => tmp);
    await d.init();

    d.download(_track);
    await settle(d);

    expect(d.status(_track.videoId), DownloadStatus.done);
    expect(ranges, ['bytes=0-10485759', 'bytes=10485760-20971519', 'bytes=20971520-31457279']);
    final path = d.localPath(_track.videoId)!;
    expect(path, endsWith('.m4a'));
    expect(File(path).lengthSync(), body.length);
    expect(File(path).readAsBytesSync()[123], 7);
    expect(d.tracks.single.videoId, _track.videoId);
    expect(d.totalBytes, body.length);

    // Survives a restart.
    final again = DownloadService(prefs, _Music(''), client: client, directory: () async => tmp);
    await again.init();
    expect(again.isDownloaded(_track.videoId), isTrue);

    await again.remove(_track.videoId);
    expect(File(path).existsSync(), isFalse);
    expect(again.tracks, isEmpty);
  });

  test('HLS playlists are refused with a clear error', () async {
    final d = DownloadService(await SharedPreferences.getInstance(),
        _Music('https://manifest.googlevideo.com/api/manifest/hls_playlist/x/index.m3u8'),
        client: MockClient((_) async => http.Response('', 500)), directory: () async => tmp);
    await d.init();
    d.download(_track);
    await settle(d);
    expect(d.status(_track.videoId), DownloadStatus.failed);
    expect(d.error(_track.videoId), contains('HLS'));
    expect(tmp.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('HTTP errors leave no partial file behind', () async {
    final d = DownloadService(await SharedPreferences.getInstance(),
        _Music('https://x/videoplayback?mime=audio%2Fwebm'),
        client: MockClient((_) async => http.Response('nope', 403)), directory: () async => tmp);
    await d.init();
    d.download(_track);
    await settle(d);
    expect(d.status(_track.videoId), DownloadStatus.failed);
    expect(tmp.listSync(recursive: true).whereType<File>(), isEmpty);
  });

  test('helpers', () {
    expect(DownloadService.totalFromContentRange('bytes 0-9/5000'), 5000);
    expect(DownloadService.extensionFor('https://x/v?mime=audio%2Fwebm'), 'webm');
    expect(DownloadService.extensionFor('https://x/v?mime=audio%2Fmp4'), 'm4a');
  });
}
