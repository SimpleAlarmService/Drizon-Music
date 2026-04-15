import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/track.dart';
import '../models/settings_model.dart';
import 'music_service.dart';
import 'storage_service.dart';
import 'settings_service.dart';

enum RepeatMode { none, one, all }

class PlayerService extends ChangeNotifier {
  final MusicService _music;
  final StorageService _storage;
  final SettingsService _settings;
  final AudioPlayer _player = AudioPlayer();
  final Random _rng = Random();

  // ── Core state ───────────────────────────────────────────────────────────────

  List<Track> _queue = [];
  int _currentIndex = 0;

  /// Tracks the sequence of indices actually played, so that prev() works
  /// correctly even in shuffle mode.
  final List<int> _shuffleHistory = [];

  bool _shuffleEnabled = false;
  RepeatMode _repeatMode = RepeatMode.none;
  bool _isLoading = false;
  String? _errorMessage;

  // Guard to prevent the completion listener from firing during setup
  bool _isSwitching = false;

  // ── Constructor ──────────────────────────────────────────────────────────────

  PlayerService(this._music, this._storage, this._settings) {
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed &&
          !_isLoading &&
          !_isSwitching &&
          _repeatMode != RepeatMode.one) {
        _onTrackCompleted();
      }
      notifyListeners();
    });
    _player.positionStream.listen((_) => notifyListeners());
    _player.durationStream.listen((_) => notifyListeners());
  }

  // ── Getters ──────────────────────────────────────────────────────────────────

  List<Track> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  Track? get currentTrack =>
      _queue.isNotEmpty && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  bool get isPlaying => _player.playing;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  double get progress {
    final d = _player.duration?.inMilliseconds ?? 0;
    if (d == 0) return 0.0;
    return (_player.position.inMilliseconds / d).clamp(0.0, 1.0);
  }

  bool get shuffleEnabled => _shuffleEnabled;
  RepeatMode get repeatMode => _repeatMode;

  // ── State Restore ────────────────────────────────────────────────────────────

  Future<void> restoreState() async {
    // Apply extractor / quality settings to MusicService before any playback
    _music.applySettings(_settings.settings);

    // Restore saved repeat mode from settings
    final savedRepeat = _settings.settings.repeatMode;
    _repeatMode = RepeatMode.values.firstWhere(
      (r) => r.name == savedRepeat,
      orElse: () => RepeatMode.none,
    );
    _player.setLoopMode(
        _repeatMode == RepeatMode.one ? LoopMode.one : LoopMode.off);

    // Restore queue / position
    final saved = _storage.loadPlayerState();
    if (saved == null) {
      notifyListeners();
      return;
    }
    _queue = saved.queue;
    _currentIndex =
        saved.currentIndex.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
    notifyListeners();
  }

  // ── Playback Control ─────────────────────────────────────────────────────────

  Future<void> playTrack(Track track, {List<Track>? queue, int? index}) async {
    _shuffleHistory.clear();
    if (queue != null) {
      _queue = List.of(queue);
      _currentIndex = index ?? _queue.indexWhere((t) => t.videoId == track.videoId);
      if (_currentIndex < 0) _currentIndex = 0;
    } else if (!_queue.any((t) => t.videoId == track.videoId)) {
      _queue = [track];
      _currentIndex = 0;
    } else {
      _currentIndex = _queue.indexWhere((t) => t.videoId == track.videoId);
    }
    await _loadAndPlay(_currentIndex);
  }

  Future<void> _loadAndPlay(int index, {int attempt = 0}) async {
    if (_queue.isEmpty || index < 0 || index >= _queue.length) return;

    final track = _queue[index];
    _currentIndex = index;
    _isSwitching = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final url = await _music.getStreamUrl(track.videoId);

      await _player.setAudioSource(
        AudioSource.uri(
          Uri.parse(url),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Linux; Android 14; SM-G991B) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/130.0.6723.103 Mobile Safari/537.36',
            'Referer': 'https://www.youtube.com/',
            'Origin': 'https://www.youtube.com',
          },
          tag: MediaItem(
            id: track.videoId,
            album: 'Drizon',
            title: track.title,
            artist: track.artist,
            artUri: Uri.parse(track.thumbnail),
          ),
        ),
      );

      _isSwitching = false;
      await _player.play();
      await _storage.addToHistory(track);
      _persistState();
    } catch (e) {
      debugPrint('[PlayerService] load error (attempt ${attempt + 1}) '
          'for ${track.videoId}: $e');

      if (attempt < 1) {
        // One retry with back-off
        _isLoading = false;
        _isSwitching = false;
        await Future.delayed(Duration(seconds: attempt + 1));
        await _loadAndPlay(index, attempt: attempt + 1);
        return;
      }

      // Both attempts failed → skip to next
      _errorMessage = 'Failed to load: ${e.toString().split('\n').first}';
      _isLoading = false;
      _isSwitching = false;
      notifyListeners();

      await Future.delayed(const Duration(seconds: 1));
      await _skipAfterFailure(index);
      return;
    } finally {
      _isLoading = false;
      _isSwitching = false;
      notifyListeners();
    }
  }

  /// Called when both retry attempts fail. Advances to next available track.
  Future<void> _skipAfterFailure(int failedIndex) async {
    if (_repeatMode == RepeatMode.one) return;
    final next = _nextIndex(failedIndex, afterFailure: true);
    if (next != null && next != failedIndex) {
      await _loadAndPlay(next);
    }
  }

  // ── Auto-advance ─────────────────────────────────────────────────────────────

  Future<void> _onTrackCompleted() async {
    if (!_settings.settings.autoplay) return;
    if (_queue.isEmpty) return;
    final next = _nextIndex(_currentIndex);
    if (next != null) await _loadAndPlay(next);
  }

  // ── Next / Prev ──────────────────────────────────────────────────────────────

  Future<void> next() async {
    if (_queue.isEmpty) return;
    final next = _nextIndex(_currentIndex);
    if (next != null) await _loadAndPlay(next);
  }

  Future<void> prev() async {
    if (_queue.isEmpty) return;

    // Restart if > 3 s into track
    if (_player.position.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    // Shuffle mode: use actual play history to go back
    if (_shuffleEnabled && _shuffleHistory.isNotEmpty) {
      final prevIdx = _shuffleHistory.removeLast();
      await _loadAndPlay(prevIdx);
      return;
    }

    int prev = _currentIndex - 1;
    if (prev < 0) {
      if (_repeatMode == RepeatMode.all) {
        prev = _queue.length - 1;
      } else {
        await _player.seek(Duration.zero);
        return;
      }
    }
    await _loadAndPlay(prev);
  }

  /// Returns the index of the next track to play, or null if playback should stop.
  int? _nextIndex(int from, {bool afterFailure = false}) {
    if (_queue.isEmpty) return null;

    if (_shuffleEnabled && !afterFailure) {
      final candidates = List.generate(_queue.length, (i) => i)
          .where((i) => i != from)
          .toList();
      if (candidates.isEmpty) {
        // Single track, only loop if repeatAll
        return _repeatMode == RepeatMode.all ? from : null;
      }
      final picked = candidates[_rng.nextInt(candidates.length)];
      _shuffleHistory.add(from);
      return picked;
    }

    final next = from + 1;
    if (next < _queue.length) return next;
    if (_repeatMode == RepeatMode.all) return 0;
    return null;
  }

  // ── Seek / Controls ──────────────────────────────────────────────────────────

  Future<void> togglePlay() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.duration == null && currentTrack != null) {
        await _loadAndPlay(_currentIndex);
      } else {
        await _player.play();
      }
    }
    notifyListeners();
  }

  Future<void> seek(double fraction) async {
    final d = _player.duration;
    if (d == null) return;
    await _player.seek(
        Duration(milliseconds: (fraction * d.inMilliseconds).round()));
  }

  Future<void> seekToPosition(Duration position) async {
    await _player.seek(position);
  }

  void toggleShuffle() {
    _shuffleEnabled = !_shuffleEnabled;
    _shuffleHistory.clear();
    notifyListeners();
  }

  void cycleRepeat() {
    _repeatMode =
        RepeatMode.values[(_repeatMode.index + 1) % RepeatMode.values.length];
    _player.setLoopMode(
      _repeatMode == RepeatMode.one ? LoopMode.one : LoopMode.off,
    );
    // Persist so the next session starts with the same repeat mode
    _settings.setRepeatMode(_repeatMode.name);
    notifyListeners();
  }

  // ── Queue Management ─────────────────────────────────────────────────────────

  void addToQueue(Track track) {
    if (_queue.any((t) => t.videoId == track.videoId)) return;
    _queue = [..._queue, track];
    notifyListeners();
    _persistState();
  }

  /// Remove the track at [index]. Cannot remove the currently playing track.
  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _currentIndex) return;
    final list = List.of(_queue)..removeAt(index);
    _queue = list;
    if (index < _currentIndex) _currentIndex--;
    notifyListeners();
    _persistState();
  }

  /// Drag-and-drop reorder. Pass [newIndex] BEFORE the removal (Flutter convention).
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final list = List.of(_queue);
    final item = list.removeAt(oldIndex);
    // Flutter's ReorderableListView passes newIndex after removal for insert;
    // adjust if needed.
    final insertAt = newIndex > oldIndex ? newIndex - 1 : newIndex;
    list.insert(insertAt, item);
    _queue = list;

    // Keep _currentIndex pointing at the same track
    if (_currentIndex == oldIndex) {
      _currentIndex = insertAt;
    } else if (oldIndex < _currentIndex && insertAt >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && insertAt <= _currentIndex) {
      _currentIndex++;
    }

    notifyListeners();
    _persistState();
  }

  // ── Likes ────────────────────────────────────────────────────────────────────

  bool isLiked(String videoId) => _storage.isLiked(videoId);

  Future<void> toggleLike(Track track) async {
    await _storage.toggleLike(track);
    notifyListeners();
  }

  // ── Persistence ──────────────────────────────────────────────────────────────

  void _persistState() {
    _storage.savePlayerState(_queue, _currentIndex);
  }

  // ── Dispose ──────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _player.dispose();
    _music.dispose();
    super.dispose();
  }
}
