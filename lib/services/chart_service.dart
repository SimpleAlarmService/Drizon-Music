import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'music_service.dart';

class ChartSpec {
  const ChartSpec(this.id, this.title);
  final String id; // YouTube playlist id
  final String title;
}

/// The "인기 음악" shelves on the home screen: YouTube Music's weekly chart
/// playlists (their anonymous browse API no longer serves charts, but the
/// playlists are public). Cached in preferences so the home screen is filled
/// right away on the next launch, then refreshed in the background.
class ChartService extends ChangeNotifier {
  ChartService(this._music, this._prefs) {
    for (final c in charts) {
      final raw = _prefs.getString('$_cachePrefix${c.id}');
      if (raw == null) continue;
      try {
        _tracks[c.id] = [
          for (final m in jsonDecode(raw) as List) Track.fromMap(m as Map),
        ];
      } catch (_) {/* corrupt cache: refetch */}
    }
  }

  static const _cachePrefix = 'drizonChart.';
  static const _maxAge = Duration(hours: 6);

  static const charts = [
    ChartSpec('PL4fGSI1pDJn6jXS_Tv_N9B8Z0HTRVJE0m', '한국 인기 음악 TOP'),
    ChartSpec('PL4fGSI1pDJn6puJdseH2Rt9sMvt9E2M4i', '글로벌 인기 음악 TOP'),
  ];

  final MusicService _music;
  final SharedPreferences _prefs;
  final _tracks = <String, List<Track>>{};
  bool _loading = false;

  /// Only the yt-dlp platforms can read playlists.
  bool get supported => Platform.isIOS || Platform.isMacOS;
  bool get loading => _loading;
  List<Track> tracks(String id) => _tracks[id] ?? const [];
  bool get hasAny => _tracks.values.any((t) => t.isNotEmpty);

  Future<void> load({bool force = false}) async {
    if (!supported || _loading) return;
    _loading = true;
    notifyListeners();
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in charts) {
      final at = _prefs.getInt('$_cachePrefix${c.id}.ms') ?? 0;
      final fresh = now - at < _maxAge.inMilliseconds && tracks(c.id).isNotEmpty;
      if (fresh && !force) continue;
      try {
        final list = await _music.playlist(c.id, limit: 30);
        if (list.isEmpty) continue;
        _tracks[c.id] = list;
        await _prefs.setString(
            '$_cachePrefix${c.id}', jsonEncode([for (final t in list) t.toMap()]));
        await _prefs.setInt('$_cachePrefix${c.id}.ms', now);
        notifyListeners();
      } catch (e) {
        debugPrint('[ChartService] ${c.title}: $e');
      }
    }
    _loading = false;
    notifyListeners();
  }
}
