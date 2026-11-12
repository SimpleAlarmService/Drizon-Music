import 'package:flutter_test/flutter_test.dart';
import 'package:oye/models/track.dart';
import 'package:oye/services/library_service.dart';
import 'package:oye/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Track _t(String id) => Track(
    videoId: id, title: 'Song $id', artist: 'Artist', thumbnail: '', durationSec: 90);

void main() {
  late LibraryService library;
  late StorageService storage;
  var notifications = 0;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
    await storage.initWithPrefs(await SharedPreferences.getInstance());
    library = LibraryService(storage);
    notifications = 0;
    library.addListener(() => notifications++);
  });

  test('starts with the two built-in collections', () {
    final c = library.collections;
    expect(c.map((e) => e.kind),
        [CollectionKind.liked, CollectionKind.history]);
  });

  test('playlists appear after the built-ins and hold their tracks', () async {
    final p = await library.createPlaylist('Drive');
    await library.addToPlaylist(p.id, _t('a'));
    await library.addToPlaylist(p.id, _t('b'));
    await library.addToPlaylist(p.id, _t('a')); // duplicate ignored

    final c = library.collections;
    expect(c.length, 3);
    expect(c.last.kind, CollectionKind.playlist);
    expect(c.last.title, 'Drive');
    expect(c.last.tracks.map((t) => t.videoId), ['a', 'b']);
    expect(notifications, greaterThanOrEqualTo(3));
  });

  test('rename, remove track, delete playlist', () async {
    final p = await library.createPlaylist('Old');
    await library.addToPlaylist(p.id, _t('a'));
    await library.renamePlaylist(p.id, 'New');
    expect(library.playlists.single.name, 'New');
    await library.removeFromPlaylist(p.id, 'a');
    expect(library.collections.last.tracks, isEmpty);
    await library.deletePlaylist(p.id);
    expect(library.playlists, isEmpty);
  });

  test('likes are newest-first and toggle off', () async {
    await library.toggleLike(_t('a'));
    await library.toggleLike(_t('b'));
    expect(library.liked.map((t) => t.videoId), ['b', 'a']);
    expect(library.isLiked('a'), isTrue);
    await library.toggleLike(_t('a'));
    expect(library.isLiked('a'), isFalse);
  });

  test('history can be cleared', () async {
    await storage.addToHistory(_t('a'));
    library.historyChanged();
    expect(library.history, hasLength(1));
    await library.clearHistory();
    expect(library.history, isEmpty);
  });
}
