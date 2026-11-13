// Shuffle and repeat: shuffle plays every song once before repeating, repeat-all
// wraps around, repeat-one is a loop-mode toggle, and both modes are remembered.
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:oye/models/settings_model.dart';
import 'package:oye/models/track.dart';
import 'package:oye/services/music_service.dart';
import 'package:oye/services/player_service.dart';
import 'package:oye/services/settings_service.dart';
import 'package:oye/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Music implements MusicService {
  @override
  Future<StreamInfo> getStreamInfo(String id) async =>
      StreamInfo('https://example.invalid/$id.m4a', const {});
  @override
  void applySettings(AppSettings s) {}
  @override
  dynamic noSuchMethod(Invocation i) => Future<dynamic>.value(null);
}

class _FakeAudioPlayer extends AudioPlayerPlatform {
  _FakeAudioPlayer(super.id);
  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => const Stream.empty();
  @override
  Future<LoadResponse> load(LoadRequest r) async =>
      LoadResponse(duration: const Duration(minutes: 3));
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

Track t(int i) => Track(videoId: 'v$i', title: 'Song $i', artist: 'A', thumbnail: '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SettingsService settings;
  late PlayerService player;
  final songs = [for (var i = 0; i < 5; i++) t(i)];

  setUp(() async {
    JustAudioPlatform.instance = _FakeJustAudio();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final storage = StorageService();
    await storage.initWithPrefs(prefs);
    settings = SettingsService();
    await settings.init(prefs);
    player = PlayerService(_Music(), storage, settings);
    player.setQueueForTest(songs, 0);
  });

  test('shuffle visits every song once before it stops', () {
    player.setShuffle(true);
    var at = 0;
    final seen = <int>{0};
    for (var step = 0; step < 4; step++) {
      final next = player.nextIndexForTest(at)!;
      expect(seen.add(next), isTrue, reason: 'song $next came up twice in one round');
      at = next;
    }
    expect(seen.length, 5);
    expect(player.nextIndexForTest(at), isNull, reason: 'round over and repeat is off');
  });

  test('shuffle + repeat all reshuffles and never repeats the same song back to back', () {
    player.setShuffle(true);
    player.cycleRepeat(); // one
    player.cycleRepeat(); // all
    expect(player.repeatMode, RepeatMode.all);
    var at = 0;
    for (var step = 0; step < 40; step++) {
      final next = player.nextIndexForTest(at);
      expect(next, isNotNull);
      expect(next, isNot(at));
      at = next!;
    }
  });

  test('repeat all wraps, repeat none ends', () {
    expect(player.nextIndexForTest(1), 2);
    expect(player.nextIndexForTest(4), isNull);
    player.cycleRepeat(); // one
    player.cycleRepeat(); // all
    expect(player.nextIndexForTest(4), 0);
  });

  test('repeat cycles none → one → all → none and is remembered', () {
    expect(player.repeatMode, RepeatMode.none);
    player.cycleRepeat();
    expect(player.repeatMode, RepeatMode.one);
    expect(settings.settings.repeatMode, 'one');
    player.cycleRepeat();
    expect(player.repeatMode, RepeatMode.all);
    player.cycleRepeat();
    expect(player.repeatMode, RepeatMode.none);
  });

  test('shuffle is remembered', () {
    player.toggleShuffle();
    expect(player.shuffleEnabled, isTrue);
    expect(settings.settings.shuffle, isTrue);
    player.toggleShuffle();
    expect(settings.settings.shuffle, isFalse);
  });
}
