import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoSearchTextField;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:oye/main.dart';
import 'package:oye/models/settings_model.dart';
import 'package:oye/models/track.dart';
import 'package:oye/models/video_streams.dart';
import 'package:oye/services/download_service.dart';
import 'package:oye/services/engines/bugs_client.dart';
import 'package:oye/services/engines/lrclib_client.dart';
import 'package:oye/services/engines/ytmusic_client.dart';
import 'package:oye/services/library_service.dart';
import 'package:oye/services/metadata_service.dart';
import 'package:oye/services/music_service.dart';
import 'package:oye/services/player_service.dart';
import 'package:oye/services/settings_service.dart';
import 'package:oye/services/storage_service.dart';
import 'package:oye/ui/pages/now_playing_page.dart';
import 'package:oye/ui/widgets/mini_player.dart';
import 'package:oye/ui/widgets/video_widgets.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeMusic implements MusicService {
  @override
  Future<List<Track>> search(String q) async => [
        for (var i = 0; i < 4; i++)
          Track(
              videoId: 'r$i',
              title: 'Result $i for $q',
              artist: 'Some Artist',
              thumbnail: '',
              duration: '3:2$i',
              durationSec: 180 + i),
      ];
  @override
  Future<String> getStreamUrl(String id) async => 'https://example.invalid/$id.m4a';
  @override
  Future<StreamInfo> getStreamInfo(String id) async =>
      StreamInfo(await getStreamUrl(id), const {});
  @override
  Future<VideoStreams> getVideoStreams(String id) async => const VideoStreams(formats: [
        VideoFormat(url: 'https://example.invalid/v.mp4', kind: 'muxed', ext: 'mp4', height: 360,
            vcodec: 'avc1', acodec: 'mp4a'),
      ]);
  @override
  Future<void> muxVideo(String v, String a, String o) async {}
  @override
  Future<String> updateExtractor() async => 'yt-dlp test is up to date';
  @override
  void applySettings(AppSettings s) {}
  @override
  Future<void> dispose() async {}
}

class _FakeAudioPlayer extends AudioPlayerPlatform {
  _FakeAudioPlayer(super.id);
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => const Stream.empty();
  @override
  Future<LoadResponse> load(LoadRequest r) async =>
      LoadResponse(duration: const Duration(minutes: 3, seconds: 12));
  @override
  Future<PlayResponse> play(PlayRequest r) async => PlayResponse();
  @override
  Future<PauseResponse> pause(PauseRequest r) async => PauseResponse();
  @override
  Future<SeekResponse> seek(SeekRequest r) async => SeekResponse();
  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest r) async => SetVolumeResponse();
  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest r) async => SetSpeedResponse();
  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest r) async => SetLoopModeResponse();
  @override
  Future<SetShuffleModeResponse> setShuffleMode(SetShuffleModeRequest r) async =>
      SetShuffleModeResponse();
  @override
  Future<DisposeResponse> dispose(DisposeRequest r) async => DisposeResponse();
}

class _FakeJustAudio extends JustAudioPlatform {
  @override
  Future<AudioPlayerPlatform> init(InitRequest r) async => _FakeAudioPlayer(r.id);
  @override
  Future<DisposePlayerResponse> disposePlayer(DisposePlayerRequest r) async =>
      DisposePlayerResponse();
  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(DisposeAllPlayersRequest r) async =>
      DisposeAllPlayersResponse();
}

/// Set DRIZON_SHOT_DIR to also write a PNG of every screen (for eyeballing layouts).
final String? _shotDir = Platform.environment['DRIZON_SHOT_DIR'];

/// Loads a real font when available so screenshots look like the app; harmless otherwise.
Future<void> _loadFont(String family, String? path) async {
  if (path == null || !File(path).existsSync()) return;
  final bytes = File(path).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)));
  await loader.load();
}

String? _cupertinoIconsFont() {
  final cache = Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['HOME']}/.pub-cache';
  final hosted = Directory('$cache/hosted/pub.dev');
  if (!hosted.existsSync()) return null;
  final dirs = hosted
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.contains('cupertino_icons-'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return dirs.isEmpty ? null : '${dirs.last.path}/assets/CupertinoIcons.ttf';
}

Track _t(String id, String title, String artist) => Track(
    videoId: id, title: title, artist: artist, thumbnail: '', duration: '3:12', durationSec: 192);

/// Answers like YouTube Music / Bugs / LRCLIB did when the fixtures were captured.
MockClient _fakeWeb() => MockClient((req) async {
      String f(String n) => File('test/fixtures/$n').readAsStringSync();
      final url = req.url.toString();
      final utf8Headers = {'content-type': 'application/json; charset=utf-8'};
      if (url.contains('get_search_suggestions')) {
        return http.Response.bytes(utf8.encode(f('ytm_suggestions.json')), 200, headers: utf8Headers);
      }
      if (url.contains('youtubei/v1/search') && req.body.contains('EgWKAQIQ')) {
        return http.Response.bytes(utf8.encode(f('ytm_search_videos.json')), 200, headers: utf8Headers);
      }
      if (url.contains('youtubei/v1/search')) {
        return http.Response.bytes(utf8.encode(f('ytm_search_unfiltered.json')), 200, headers: utf8Headers);
      }
      if (url.contains('bugs.co.kr/search/track')) {
        return http.Response.bytes(utf8.encode(f('bugs_search_iu.html')), 200);
      }
      if (url.contains('bugs.co.kr/player/lyrics/T/')) {
        return http.Response.bytes(utf8.encode(f('bugs_lyrics_synced.json')), 200, headers: utf8Headers);
      }
      if (url.contains('lrclib.net')) return http.Response('[]', 200);
      return http.Response('', 404);
    });

// ── Test ─────────────────────────────────────────────────────────────────────

void main() {
  final boundary = GlobalKey();

  Future<void> shot(WidgetTester tester, String name) async {
    if (_shotDir == null) return;
    await tester.runAsync(() async {
      final b = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await b.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('${_shotDir!}/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  testWidgets('every screen renders without errors', (tester) async {
    JustAudioPlatform.instance = _FakeJustAudio();
    await tester.runAsync(() async {
      final fonts = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
      await _loadFont('Roboto', '$fonts/Roboto-Regular.ttf');
      await _loadFont('MaterialIcons', '$fonts/MaterialIcons-Regular.otf');
      await _loadFont('packages/cupertino_icons/CupertinoIcons', _cupertinoIconsFont());
    });
    await tester.pump(); // consume the frame scheduled by the font-change notification

    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService()..initWithPrefs(prefs);
    final settings = SettingsService();
    await settings.init(prefs);
    final music = _FakeMusic();
    final web = _fakeWeb();
    final ytm = YtmClient(client: web);
    final metadata = MetadataService(
        prefs, ytm, BugsClient(client: web), LrclibClient(client: web));
    final tmp = await tester.runAsync(() => Directory.systemTemp.createTemp('drizon_ui'));
    // The image cache asks the platform for a temp folder; there is no platform here.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'), (_) async => tmp!.path);
    final downloads = DownloadService(prefs, music, directory: () async => tmp!);
    await tester.runAsync(downloads.init);
    final library = LibraryService(storage, downloads: downloads);

    final songs = [
      _t('a', '밤편지', '아이유'),
      _t('b', 'Levitating', 'Dua Lipa'),
      _t('c', 'Peaches', 'Justin Bieber'),
      _t('d', 'As It Was', 'Harry Styles'),
      _t('e', 'Good 4 U', 'Olivia Rodrigo'),
    ];
    for (final s in songs.reversed) {
      await storage.addToHistory(s);
    }
    await storage.toggleLike(songs[0]);
    await storage.toggleLike(songs[2]);
    final road = await storage.createPlaylist('Road Trip');
    for (final s in songs) {
      await storage.addTrackToPlaylist(road.id, s);
    }
    final gym = await storage.createPlaylist('Gym');
    await storage.addTrackToPlaylist(gym.id, songs[1]);
    await storage.createPlaylist('Empty one');

    final player = PlayerService(music, storage, settings)
      ..onHistoryChanged = library.historyChanged;

    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: MultiProvider(
        providers: [
          Provider<MusicService>.value(value: music),
          Provider<StorageService>.value(value: storage),
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<PlayerService>.value(value: player),
          ChangeNotifierProvider<LibraryService>.value(value: library),
          ChangeNotifierProvider<MetadataService>.value(value: metadata),
          ChangeNotifierProvider<DownloadService>.value(value: downloads),
          Provider<YtmClient>.value(value: ytm),
        ],
        child: const DrizonApp(),
      ),
    ));
    await settle(tester);
    await shot(tester, 'ui_home');

    // Library tab with Cover Flow
    await tester.tap(find.byIcon(CupertinoIcons.music_albums_fill));
    await settle(tester);
    await shot(tester, 'ui_library');

    // Swipe the Cover Flow to the playlist
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 0));
    await tester.dragFrom(const Offset(195, 250), const Offset(-120, 0));
    await settle(tester);
    await shot(tester, 'ui_library_swiped');

    // Play the selected collection -> mini player
    await tester.tap(find.text('재생'));
    await settle(tester);
    await shot(tester, 'ui_library_playing');
    expect(player.currentTrack, isNotNull);

    // Open now playing from the mini player, on a single-song queue so the
    // fake player doesn't skip ahead.
    player.playTrack(songs[0], queue: [songs[0]]);
    await settle(tester);
    await tester.tap(find.byType(MiniPlayer));
    await settle(tester);
    await shot(tester, 'ui_now_playing');
    expect(find.byType(NowPlayingPage), findsOneWidget);

    // Lyrics: matched on Bugs (captured response) and shown synced.
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble));
    LyricsResult? lyricsResult;
    metadata.lyricsFor(songs[0]).then((r) => lyricsResult = r);
    for (var i = 0; i < 40 && lyricsResult == null; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // ignore: avoid_print
    print('lyrics: provider=${lyricsResult?.provider} error=${lyricsResult?.error} '
        'lines=${lyricsResult?.lyrics?.synced.length}');
    await settle(tester);
    await shot(tester, 'ui_lyrics');
    expect(find.text('이 밤 그날의 반딧불을'), findsOneWidget);
    expect(find.textContaining('가사 제공: 벅스'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.quote_bubble_fill));
    await settle(tester);

    // Queue sheet
    await tester.tap(find.byIcon(CupertinoIcons.list_bullet));
    await settle(tester);
    await shot(tester, 'ui_queue');
    await tester.tapAt(const Offset(195, 30)); // dismiss sheet (barrier)
    await settle(tester);
    Navigator.of(tester.element(find.byType(NowPlayingPage))).pop();
    await settle(tester);

    // Videos tab: shelves for the most-played artist (captured video search).
    await tester.tap(find.byIcon(CupertinoIcons.play_rectangle_fill));
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot(tester, 'ui_videos');
    expect(find.textContaining('직캠'), findsWidgets);

    // Video player: no video platform in tests, so it must fail gracefully.
    await tester.tap(find.byType(VideoThumb).first);
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    await shot(tester, 'ui_video_player');
    expect(find.text('음악으로 듣기'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.chevron_down));
    await settle(tester);

    // Search tab
    await tester.tap(find.text('검색')); // tab label
    await settle(tester);
    await tester.enterText(find.byType(CupertinoSearchTextField), '아이유 밤');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    await shot(tester, 'ui_suggestions');
    expect(find.text('아이유 밤편지 노래방'), findsOneWidget);
    await tester.tap(find.text('아이유 밤편지'));
    await settle(tester);
    await shot(tester, 'ui_search');
    expect(find.textContaining('Result 0'), findsOneWidget);

    // Settings from the home tab
    await tester.tap(find.byIcon(CupertinoIcons.play_circle_fill));
    await settle(tester);
    await tester.tap(find.byIcon(CupertinoIcons.person_crop_circle));
    await settle(tester);
    await shot(tester, 'ui_settings');

    expect(tester.takeException(), isNull);

    // Tear down so no timers outlive the test.
    await tester.pumpWidget(const SizedBox());
    player.dispose();
    await tester.pump(const Duration(seconds: 10));
  });
}
