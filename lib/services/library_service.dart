import 'package:flutter/foundation.dart';
import '../models/playlist.dart';
import '../models/track.dart';
import 'download_service.dart';
import 'storage_service.dart';

enum CollectionKind { liked, history, downloads, playlist }

/// Anything that shows up as a cover in the library: liked songs, history, or a playlist.
class Collection {
  final String id;
  final CollectionKind kind;
  final String title;
  final List<Track> tracks;
  final Playlist? playlist;

  const Collection({
    required this.id,
    required this.kind,
    required this.title,
    required this.tracks,
    this.playlist,
  });
}

/// Reactive facade over [StorageService] for the library UI: every mutation
/// goes through here so listeners rebuild.
class LibraryService extends ChangeNotifier {
  final StorageService _storage;
  final DownloadService? _downloads;

  LibraryService(this._storage, {DownloadService? downloads}) : _downloads = downloads {
    _downloads?.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _downloads?.removeListener(notifyListeners);
    super.dispose();
  }

  List<Track> get liked => _storage.getLikedTracks().reversed.toList();
  List<Track> get history => _storage.getHistory();
  List<Playlist> get playlists => _storage.getPlaylists();

  List<Collection> get collections => [
        Collection(
            id: 'liked',
            kind: CollectionKind.liked,
            title: '좋아요 표시한 곡',
            tracks: liked),
        Collection(
            id: 'history',
            kind: CollectionKind.history,
            title: '최근 재생',
            tracks: history),
        if (_downloads != null)
          Collection(
              id: 'downloads',
              kind: CollectionKind.downloads,
              title: '다운로드한 음악',
              tracks: _downloads.tracks),
        for (final p in playlists)
          Collection(
              id: p.id,
              kind: CollectionKind.playlist,
              title: p.name,
              tracks: _storage.getPlaylistTracks(p.id),
              playlist: p),
      ];

  bool isLiked(String videoId) => _storage.isLiked(videoId);

  Future<void> toggleLike(Track track) async {
    await _storage.toggleLike(track);
    notifyListeners();
  }

  Future<Playlist> createPlaylist(String name) async {
    final p = await _storage.createPlaylist(name);
    notifyListeners();
    return p;
  }

  Future<void> renamePlaylist(String id, String name) async {
    await _storage.renamePlaylist(id, name);
    notifyListeners();
  }

  Future<void> deletePlaylist(String id) async {
    await _storage.deletePlaylist(id);
    notifyListeners();
  }

  Future<void> addToPlaylist(String playlistId, Track track) async {
    await _storage.addTrackToPlaylist(playlistId, track);
    notifyListeners();
  }

  Future<void> removeFromPlaylist(String playlistId, String videoId) async {
    await _storage.removeTrackFromPlaylist(playlistId, videoId);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await _storage.clearHistory();
    notifyListeners();
  }

  /// Wired to [PlayerService.onHistoryChanged].
  void historyChanged() => notifyListeners();
}
