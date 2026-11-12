import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:oye/models/video_streams.dart';
import 'package:oye/services/engines/ytmusic_client.dart';

VideoFormat f(String kind, {int h = 0, String ext = 'mp4', String v = '', String a = '', int br = 0}) =>
    VideoFormat(url: '$kind-$h-$ext-$v', kind: kind, height: h, ext: ext, vcodec: v, acodec: a, bitrate: br);

void main() {
  group('VideoStreams', () {
    final streams = VideoStreams(formats: [
      f('muxed', h: 360, v: 'avc1.42001E', a: 'mp4a.40.2'),
      f('video', h: 1080, v: 'avc1.640028', br: 4000),
      f('video', h: 1080, ext: 'webm', v: 'vp9', br: 3000),
      f('video', h: 720, v: 'avc1.4d401f', br: 2000),
      f('video', h: 1440, ext: 'webm', v: 'vp9'), // no H.264 → can't make an MP4
      f('audio', ext: 'm4a', a: 'mp4a.40.2', br: 128000),
      f('audio', ext: 'webm', a: 'opus', br: 160000),
    ]);

    test('download qualities are those we can build as H.264+AAC MP4', () {
      expect(streams.downloadHeights, [1080, 720, 360]);
    });

    test('360p downloads the muxed file directly', () {
      final plan = streams.planFor(360)!;
      expect(plan.needsMux, isFalse);
      expect(plan.video.kind, 'muxed');
    });

    test('1080p joins H.264 video with AAC audio', () {
      final plan = streams.planFor(1080)!;
      expect(plan.needsMux, isTrue);
      expect(plan.video.vcodec, startsWith('avc1'));
      expect(plan.audio!.acodec, startsWith('mp4a'));
      expect(streams.planFor(1440), isNull);
    });

    test('playback prefers HLS, else the best muxed MP4', () {
      expect(streams.playbackUrl, 'muxed-360-mp4-avc1.42001E');
      final hls = VideoStreams(hls: 'https://x/master.m3u8', formats: streams.formats);
      expect(hls.playbackUrl, 'https://x/master.m3u8');
    });

    test('without AAC audio only muxed files are offered', () {
      final noAac = VideoStreams(formats: [
        f('muxed', h: 360, v: 'avc1', a: 'mp4a'),
        f('video', h: 1080, v: 'avc1'),
        f('audio', ext: 'webm', a: 'opus'),
      ]);
      expect(noAac.downloadHeights, [360]);
    });

    test('parses the platform channel map', () {
      final s = VideoStreams.fromMap({
        'headers': {'User-Agent': 'UA'},
        'hls': '',
        'durationSec': 215,
        'formats': [
          {'url': 'u', 'kind': 'muxed', 'ext': 'mp4', 'height': 360, 'bitrate': 1, 'vcodec': 'avc1', 'acodec': 'mp4a'},
        ],
      });
      expect(s.hls, isNull);
      expect(s.headers['User-Agent'], 'UA');
      expect(s.formats.single.height, 360);
    });
  });

  group('YouTube Music video search (captured response)', () {
    final json = jsonDecode(File('test/fixtures/ytm_search_videos.json').readAsStringSync())
        as Map<String, dynamic>;

    test('videos carry channel, views and duration', () {
      final items = YtmClient.parseSearch(json);
      expect(items, hasLength(20));
      final first = items.first;
      expect(first.videoId, 'BQsc6rE9IEQ');
      expect(first.artist, 'smile -wA-');
      expect(first.views, '조회수 19만회');
      expect(first.durationSec, 239);
      expect(first.albumArt, isNull);
      expect(first.videoThumb(), 'https://i.ytimg.com/vi/BQsc6rE9IEQ/hqdefault.jpg');
    });

    test('the Videos filter chip is read from a normal search', () {
      final unfiltered = jsonDecode(File('test/fixtures/ytm_search_unfiltered.json').readAsStringSync())
          as Map<String, dynamic>;
      expect(YtmClient.videosFilterParams(unfiltered), 'EgWKAQIQAWoKEAQQBRAVEBAQEQ==');
    });

    test('YtmItem survives a save/load round trip', () {
      final item = YtmClient.parseSearch(json).first;
      final back = YtmItem.fromMap(jsonDecode(jsonEncode(item.toMap())) as Map);
      expect(back.videoId, item.videoId);
      expect(back.views, item.views);
      expect(back.kind, item.kind);
    });
  });
}
