import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/track.dart';
import '../models/playlist.dart';

// ── Simple value object for restored player state ─────────────────────────────

class SavedPlayerState {
  final List<Track> queue;
  final int currentIndex;
  const SavedPlayerState({required this.queue, required this.currentIndex});
}

// ── StorageService ────────────────────────────────────────────────────────────

class StorageService {
  static const _likedKey        = 'oye_liked';
  static const _historyKey      = 'oye_history';
  static const _playlistsKey    = 'oye_playlists';
  static const _playerStateKey  = 'oye_player_state';

  late SharedPreferences _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// Preferred: pass an already-initialised instance to avoid a duplicate call.
  Future<void> initWithPrefs(SharedPreferences prefs) async {
    _prefs = prefs;
  }

  // ── Liked tracks ────────────────────────────────────────────────────────────

  Set<String> getLikedIds() {
    return (_prefs.getStringList(_likedKey) ?? []).toSet();
  }

  bool isLiked(String videoId) => getLikedIds().contains(videoId);

  Future<void> toggleLike(Track track) async {
    final ids = getLikedIds();
    if (ids.contains(track.videoId)) {
      ids.remove(track.videoId);
    } else {
      ids.add(track.videoId);
    }
    await _prefs.setStringList(_likedKey, ids.toList());

    final key = 'oye_track_${track.videoId}';
    if (ids.contains(track.videoId)) {
      await _prefs.setString(key, jsonEncode(track.toMap()));
    }
  }

  List<Track> getLikedTracks() {
    final ids = getLikedIds().toList();
    return ids
        .map((id) {
          final raw = _prefs.getString('oye_track_$id');
          if (raw == null) return null;
          try {
            return Track.fromMap(jsonDecode(raw) as Map<dynamic, dynamic>);
          } catch (_) {
            return null;
          }
        })
        .whereType<Track>()
        .toList();
  }

  // ── Play history ────────────────────────────────────────────────────────────

  Future<void> addToHistory(Track track) async {
    final raw = _prefs.getString(_historyKey);
    final List<dynamic> list = raw != null ? jsonDecode(raw) as List : [];

    list.removeWhere((e) => (e as Map)['videoId'] == track.videoId);
    list.insert(0, track.toMap());
    if (list.length > 50) list.removeRange(50, list.length);

    await _prefs.setString(_historyKey, jsonEncode(list));
  }

  List<Track> getHistory() {
    final raw = _prefs.getString(_historyKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Track.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  // ── Playlists ───────────────────────────────────────────────────────────────

  List<Playlist> getPlaylists() {
    final raw = _prefs.getString(_playlistsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => Playlist.fromMap(e as Map<dynamic, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<Playlist> createPlaylist(String name) async {
    final playlists = getPlaylists();
    final playlist = Playlist(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      trackIds: [],
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    playlists.add(playlist);
    await _savePlaylistsRaw(playlists);
    return playlist;
  }

  Future<void> deletePlaylist(String id) async {
    final playlists = getPlaylists()..removeWhere((p) => p.id == id);
    await _savePlaylistsRaw(playlists);
  }

  Future<void> renamePlaylist(String id, String newName) async {
    final playlists = getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == id);
    if (idx < 0) return;
    playlists[idx] = playlists[idx].copyWith(name: newName);
    await _savePlaylistsRaw(playlists);
  }

  Future<void> addTrackToPlaylist(String playlistId, Track track) async {
    final playlists = getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final ids = List<String>.from(playlists[idx].trackIds);
    if (!ids.contains(track.videoId)) ids.add(track.videoId);
    playlists[idx] = playlists[idx].copyWith(trackIds: ids);
    await _savePlaylistsRaw(playlists);
    await _prefs.setString(
        'oye_track_${track.videoId}', jsonEncode(track.toMap()));
  }

  Future<void> removeTrackFromPlaylist(
      String playlistId, String videoId) async {
    final playlists = getPlaylists();
    final idx = playlists.indexWhere((p) => p.id == playlistId);
    if (idx < 0) return;
    final ids = List<String>.from(playlists[idx].trackIds)..remove(videoId);
    playlists[idx] = playlists[idx].copyWith(trackIds: ids);
    await _savePlaylistsRaw(playlists);
  }

  List<Track> getPlaylistTracks(String playlistId) {
    final playlist = getPlaylists().firstWhere(
      (p) => p.id == playlistId,
      orElse: () =>
          Playlist(id: '', name: '', trackIds: [], createdAt: 0),
    );
    return playlist.trackIds.map((id) {
      final raw = _prefs.getString('oye_track_$id');
      if (raw == null) return null;
      try {
        return Track.fromMap(jsonDecode(raw) as Map<dynamic, dynamic>);
      } catch (_) {
        return null;
      }
    }).whereType<Track>().toList();
  }

  Future<void> _savePlaylistsRaw(List<Playlist> playlists) async {
    await _prefs.setString(
      _playlistsKey,
      jsonEncode(playlists.map((p) => p.toMap()).toList()),
    );
  }

  // ── Player state persistence ─────────────────────────────────────────────────

  /// Fire-and-forget — called frequently; uses synchronous write path.
  void savePlayerState(List<Track> queue, int currentIndex) {
    _prefs.setString(
      _playerStateKey,
      jsonEncode({
        'queue': queue.map((t) => t.toMap()).toList(),
        'currentIndex': currentIndex,
      }),
    );
  }

  /// Returns null if nothing was saved or data is corrupt.
  SavedPlayerState? loadPlayerState() {
    final raw = _prefs.getString(_playerStateKey);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<dynamic, dynamic>;
      final queue = (map['queue'] as List)
          .map((e) => Track.fromMap(e as Map<dynamic, dynamic>))
          .toList();
      final index = (map['currentIndex'] as num).toInt();
      return SavedPlayerState(queue: queue, currentIndex: index);
    } catch (_) {
      return null;
    }
  }
}
