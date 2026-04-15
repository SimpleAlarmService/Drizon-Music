import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/settings_model.dart';

/// Owns the [AppSettings] singleton, persists it to SharedPreferences,
/// and notifies listeners on every change.
///
/// Use [context.read<SettingsService>().settings] for one-off reads.
/// Use [context.watch<SettingsService>().settings] for reactive UI.
class SettingsService extends ChangeNotifier {
  static const _key = 'oye_settings';

  late SharedPreferences _prefs;
  AppSettings _settings = AppSettings.defaults;

  AppSettings get settings => _settings;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init(SharedPreferences prefs) async {
    _prefs = prefs;
    _load();
  }

  void _load() {
    final raw = _prefs.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _settings = AppSettings.fromMap(map);
    } catch (e) {
      debugPrint('[SettingsService] corrupt settings, using defaults: $e');
      _settings = AppSettings.defaults;
    }
  }

  // ── Write ─────────────────────────────────────────────────────────────────

  void update(AppSettings Function(AppSettings current) updater) {
    _settings = updater(_settings);
    _persist();
    notifyListeners();
  }

  void _persist() {
    _prefs.setString(_key, jsonEncode(_settings.toMap()));
  }

  // ── Convenience setters ───────────────────────────────────────────────────

  void setAutoplay(bool value) =>
      update((s) => s.copyWith(autoplay: value));

  void setAudioQuality(AudioQuality value) =>
      update((s) => s.copyWith(audioQuality: value));

  void setRepeatMode(String value) =>
      update((s) => s.copyWith(repeatMode: value));

  void setWifiOnly(bool value) =>
      update((s) => s.copyWith(wifiOnly: value));

  void setDataSaver(bool value) =>
      update((s) => s.copyWith(dataSaver: value));

  void setPrimaryExtractor(ExtractorType value) =>
      update((s) => s.copyWith(primaryExtractor: value));

  void setEnableFallback(bool value) =>
      update((s) => s.copyWith(enableFallback: value));

  void setClientType(ClientType value) =>
      update((s) => s.copyWith(clientType: value));

  void setCacheEnabled(bool value) =>
      update((s) => s.copyWith(cacheEnabled: value));

  void setCacheSizeMb(int value) =>
      update((s) => s.copyWith(cacheSizeMb: value));

  void setDarkMode(bool value) =>
      update((s) => s.copyWith(darkMode: value));

  void setAdvancedMode(bool value) =>
      update((s) => s.copyWith(advancedMode: value));

  // ── Reset ─────────────────────────────────────────────────────────────────

  void resetToDefaults() {
    _settings = AppSettings.defaults;
    _persist();
    notifyListeners();
  }
}
