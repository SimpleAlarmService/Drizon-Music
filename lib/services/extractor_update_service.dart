import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'music_service.dart';

class ExtractorComponent {
  const ExtractorComponent({
    required this.name,
    required this.current,
    required this.latest,
    required this.updateAvailable,
    required this.restartPending,
  });

  final String name;
  final String current;
  final String latest;
  final bool updateAvailable;
  final bool restartPending;

  factory ExtractorComponent.fromMap(Map<dynamic, dynamic> m) => ExtractorComponent(
        name: m['name'] as String? ?? '',
        current: m['current'] as String? ?? '',
        latest: m['latest'] as String? ?? '',
        updateAvailable: m['updateAvailable'] == true,
        restartPending: m['restartPending'] == true,
      );
}

/// Checks the embedded open-source extractor components (yt-dlp, yt-dlp-ejs) against
/// PyPI and downloads newer releases. Downloaded wheels take effect after a restart.
class ExtractorUpdateService extends ChangeNotifier {
  ExtractorUpdateService(this._music, this._prefs);

  static const _ch = MethodChannel('music.extractor');
  static const _lastCheckKey = 'extractorLastCheckMs';
  static const _autoKey = 'extractorAutoUpdate';
  static const _interval = Duration(hours: 24);

  final MusicService _music;
  final SharedPreferences _prefs;

  bool get supported => Platform.isIOS || Platform.isMacOS;

  List<ExtractorComponent> components = const [];
  bool checking = false;
  bool updating = false;
  String? message;

  bool get autoUpdate => _prefs.getBool(_autoKey) ?? true;
  set autoUpdate(bool v) {
    _prefs.setBool(_autoKey, v);
    notifyListeners();
  }

  DateTime? get lastChecked {
    final ms = _prefs.getInt(_lastCheckKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  bool get hasUpdate => components.any((c) => c.updateAvailable);
  bool get restartPending => components.any((c) => c.restartPending);

  /// Called once at launch: checks at most every 24 h and, when auto-update is on,
  /// downloads what it finds.
  Future<void> checkOnLaunch() async {
    if (!supported) return;
    final last = lastChecked;
    if (last != null && DateTime.now().difference(last) < _interval) {
      await _refresh();
      return;
    }
    await check(auto: true);
  }

  Future<void> check({bool auto = false}) async {
    if (!supported || checking || updating) return;
    checking = true;
    message = null;
    notifyListeners();
    try {
      await _refresh();
      await _prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      debugPrint('[ExtractorUpdate] check failed: $e');
      if (!auto) message = '업데이트를 확인하지 못했어요. 인터넷 연결을 확인해 주세요.';
    } finally {
      checking = false;
      notifyListeners();
    }
    if (auto && autoUpdate && hasUpdate) await update();
  }

  Future<void> update() async {
    if (!supported || updating) return;
    updating = true;
    message = null;
    notifyListeners();
    try {
      await _music.updateExtractor();
      await _refresh();
      message = restartPending ? '업데이트를 받았어요. 앱을 다시 시작하면 적용돼요.' : '최신 버전이에요.';
    } catch (e) {
      debugPrint('[ExtractorUpdate] update failed: $e');
      message = '업데이트에 실패했어요: $e';
    } finally {
      updating = false;
      notifyListeners();
    }
  }

  Future<void> _refresh() async {
    final raw = await _ch.invokeMapMethod<String, dynamic>('checkExtractorUpdates');
    components = [
      for (final c in (raw?['components'] as List? ?? const []))
        ExtractorComponent.fromMap(c as Map<dynamic, dynamic>),
    ];
  }
}
