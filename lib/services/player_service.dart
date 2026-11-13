import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../models/track.dart';
import 'music_service.dart';
import 'storage_service.dart';
import 'settings_service.dart';

enum RepeatMode { none, one, all }

class PlayerService extends ChangeNotifier {
  final MusicService _music;
  final StorageService _storage;
  final SettingsService _settings;
  // Headers go straight to AVFoundation / ExoPlayer. just_audio's local proxy
  // server (the default for requests with headers) has a start-up race that
  // surfaced as "LateInitializationError: Field '_server' has not been
  // initialized" on every track.
  final AudioPlayer _player = AudioPlayer(useProxyForRequestHeaders: false);
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

  /// Called after a track is written to the play history, so the library UI can refresh.
  VoidCallback? onHistoryChanged;

  /// Called as soon as a track is selected for playback (before the stream resolves).
  void Function(Track track)? onTrackStarted;

  /// Path of an offline copy, if the user downloaded this track.
  String? Function(String videoId)? localFileFor;

  /// Saved cover of a downloaded track (lock screen art that works offline).
  String? Function(String videoId)? localCoverFor;

  /// Downloads a track's audio into a temporary cache and returns the file path
  /// (fallback when streaming fails).
  Future<String?> Function(Track track)? cacheFor;

  /// More songs like [seed], used to keep playing when the queue runs out.
  Future<List<Track>> Function(Track seed)? moreLike;

  // ── Sleep timer & speed ──────────────────────────────────────────────────────

  Timer? _sleepTimer;
  DateTime? _sleepAt;
  bool _sleepAfterTrack = false;
  double _speed = 1.0;

  DateTime? get sleepAt => _sleepAt;
  bool get sleepAfterTrack => _sleepAfterTrack;
  bool get sleepTimerActive => _sleepAt != null || _sleepAfterTrack;
  double get speed => _speed;

  void setSleepTimer(Duration? d) {
    _sleepTimer?.cancel();
    _sleepAfterTrack = false;
    _sleepAt = d == null ? null : DateTime.now().add(d);
    if (d != null) {
      _sleepTimer = Timer(d, () {
        _sleepAt = null;
        _player.pause();
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Pause when the current track ends instead of moving on.
  void sleepAtEndOfTrack() {
    _sleepTimer?.cancel();
    _sleepAt = null;
    _sleepAfterTrack = true;
    notifyListeners();
  }

  Future<void> setSpeed(double v) async {
    _speed = v;
    await _player.setSpeed(v);
    notifyListeners();
  }

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
    if (attempt == 0) onTrackStarted?.call(track);
    _isSwitching = true;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final tag = MediaItem(
        id: track.videoId,
        album: track.album ?? 'Drizon',
        title: track.title,
        artist: track.artist,
        artUri: switch (localCoverFor?.call(track.videoId)) {
          final String cover => Uri.file(cover),
          _ => Uri.parse(track.albumArt ?? track.thumbnail),
        },
      );
      final local = localFileFor?.call(track.videoId);
      if (local != null) {
        await _player.setAudioSource(AudioSource.file(local, tag: tag));
      } else if (attempt > 0 && cacheFor != null) {
        // Streaming failed once: download the audio first, then play the file
        // (the way a desktop downloader would), which sidesteps stream-side quirks.
        final path = await cacheFor!(track);
        if (path == null) throw Exception('Could not cache audio for playback');
        await _player.setAudioSource(AudioSource.file(path, tag: tag));
      } else {
        final stream = await _music.getStreamInfo(track.videoId);
        await _player.setAudioSource(
          AudioSource.uri(Uri.parse(stream.url), headers: stream.headers, tag: tag),
        );
      }

      _isSwitching = false;
      _isLoading = false; // loaded: show play/pause, not the spinner
      notifyListeners();
      // play() only completes when playback stops, so it must not be awaited
      // (the spinner and the history entry would wait for the end of the track).
      unawaited(_player.play().catchError((Object e) {
        debugPrint('[PlayerService] play error for ${track.videoId}: $e');
      }));
      await _storage.addToHistory(track);
      onHistoryChanged?.call();
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
    if (_sleepAfterTrack) {
      _sleepAfterTrack = false;
      await _player.pause();
      notifyListeners();
      return;
    }
    if (!_settings.settings.autoplay) return;
    if (_queue.isEmpty) return;
    final next = _nextIndex(_currentIndex) ?? await _extendQueue();
    if (next != null) await _loadAndPlay(next);
  }

  /// Queue ended: append songs like the last one and return the first new index.
  Future<int?> _extendQueue() async {
    if (!_settings.settings.radio || moreLike == null || _queue.isEmpty) return null;
    if (_repeatMode == RepeatMode.all) return null;
    try {
      final seed = _queue.last;
      final have = _queue.map((t) => t.videoId).toSet();
      final more = (await moreLike!(seed)).where((t) => !have.contains(t.videoId)).take(15).toList();
      if (more.isEmpty) return null;
      final first = _queue.length;
      _queue = [..._queue, ...more];
      notifyListeners();
      return first;
    } catch (e) {
      debugPrint('[PlayerService] could not extend queue: $e');
      return null;
    }
  }

  // ── Next / Prev ──────────────────────────────────────────────────────────────

  Future<void> next() async {
    if (_queue.isEmpty) return;
    final next = _nextIndex(_currentIndex) ?? await _extendQueue();
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

  bool _disposed = false;

  /// In-flight loads/retries may finish after [dispose]; ignore their updates.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _player.dispose();
    _music.dispose();
    super.dispose();
  }
}
