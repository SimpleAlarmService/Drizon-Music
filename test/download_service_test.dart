import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:oye/models/settings_model.dart';
import 'package:oye/models/video_streams.dart';
import 'package:oye/services/engines/ytmusic_client.dart';
import 'package:oye/models/track.dart';
import 'package:oye/services/download_service.dart';
import 'package:oye/services/music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Music implements MusicService {
  _Music(this.url, {this.video});
  final String url;
  final VideoStreams? video;
  final muxed = <List<String>>[];
  @override
  Future<VideoStreams> getVideoStreams(String id) async => video!;
  @override
  Future<void> muxVideo(String v, String a, String out) async {
    muxed.add([v, a, out]);
    // Stand-in for AVFoundation/MediaMuxer: concatenate.
    await File(out).writeAsBytes([...File(v).readAsBytesSync(), ...File(a).readAsBytesSync()]);
  }
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

  group('videos', () {
    const item = YtmItem(
        videoId: 'BQsc6rE9IEQ', title: 'Fancam', artist: 'cam', thumbnail: '', kind: YtmKind.video);
    final bytes = <String, List<int>>{
      'muxed': List.filled(3000, 1),
      'video': List.filled(5000, 2),
      'audio': List.filled(700, 3),
      'thumb': [9, 9, 9],
    };
    MockClient server() => MockClient((req) async {
          final key = req.url.host == 'i.ytimg.com' ? 'thumb' : req.url.pathSegments.last;
          final body = bytes[key]!;
          return http.Response.bytes(body, req.headers.containsKey('Range') ? 206 : 200,
              headers: {'content-range': 'bytes 0-${body.length - 1}/${body.length}'});
        });
    final streams = VideoStreams(formats: [
      const VideoFormat(url: 'https://g/muxed', kind: 'muxed', ext: 'mp4', height: 360, vcodec: 'avc1', acodec: 'mp4a'),
      const VideoFormat(url: 'https://g/video', kind: 'video', ext: 'mp4', height: 1080, vcodec: 'avc1.640028'),
      const VideoFormat(url: 'https://g/audio', kind: 'audio', ext: 'm4a', acodec: 'mp4a.40.2'),
    ]);

    Future<void> settleVideo(DownloadService d) async {
      for (var i = 0; i < 200 && d.videoStatus(item.videoId) != DownloadStatus.done &&
          d.videoStatus(item.videoId) != DownloadStatus.failed; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    }

    test('360p: the muxed file is saved as-is, with a thumbnail', () async {
      final music = _Music('', video: streams);
      final d = DownloadService(await SharedPreferences.getInstance(), music,
          client: server(), directory: () async => tmp);
      await d.init();
      d.downloadVideo(item, 360);
      await settleVideo(d);
      final v = d.video(item.videoId)!;
      expect(v.height, 360);
      expect(File(v.path).lengthSync(), 3000);
      expect(File(v.thumbPath!).readAsBytesSync(), [9, 9, 9]);
      expect(music.muxed, isEmpty);
    });

    test('1080p: video and audio are fetched, joined, and the parts removed', () async {
      final music = _Music('', video: streams);
      final d = DownloadService(await SharedPreferences.getInstance(), music,
          client: server(), directory: () async => tmp);
      await d.init();
      d.downloadVideo(item, 1080);
      await settleVideo(d);
      expect(d.videoStatus(item.videoId), DownloadStatus.done);
      expect(music.muxed, hasLength(1));
      final v = d.video(item.videoId)!;
      expect(File(v.path).lengthSync(), 5700);
      final leftovers = Directory('${tmp.path}/videos').listSync().map((e) => e.path.split('/').last);
      expect(leftovers, unorderedEquals(['BQsc6rE9IEQ.mp4', 'BQsc6rE9IEQ.jpg']));

      await d.removeVideo(item.videoId);
      expect(Directory('${tmp.path}/videos').listSync(), isEmpty);
    });

    test('a quality that does not exist fails clearly', () async {
      final d = DownloadService(await SharedPreferences.getInstance(), _Music('', video: streams),
          client: server(), directory: () async => tmp);
      await d.init();
      d.downloadVideo(item, 2160);
      await settleVideo(d);
      expect(d.videoError(item.videoId), contains('2160p'));
    });
  });

  test('cover and lyrics sidecars live and die with the song', () async {
    final client = MockClient((req) async => req.url.host == 'img'
        ? http.Response.bytes([1, 2, 3], 200)
        : http.Response.bytes(List.filled(10, 0), 206, headers: {'content-range': 'bytes 0-9/10'}));
    final d = DownloadService(await SharedPreferences.getInstance(),
        _Music('https://x/v?mime=audio%2Fmp4'), client: client, directory: () async => tmp);
    await d.init();
    await d.saveCover(_track.videoId, 'https://img/c.jpg'); // not downloaded yet → ignored
    expect(d.localCover(_track.videoId), isNull);

    d.download(_track);
    await settle(d);
    await d.saveCover(_track.videoId, 'https://img/c.jpg');
    await d.writeLyrics(_track.videoId, '{"x":1}');
    expect(File(d.localCover(_track.videoId)!).readAsBytesSync(), [1, 2, 3]);
    expect(await d.readLyrics(_track.videoId), '{"x":1}');

    await d.remove(_track.videoId);
    expect(d.localCover(_track.videoId), isNull);
    expect(await d.readLyrics(_track.videoId), isNull);
    expect(Directory('${tmp.path}/downloads').listSync(), isEmpty);
  });
}
