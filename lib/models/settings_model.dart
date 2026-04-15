/// Strongly-typed application settings.
/// Serialised to / from a flat map so it can be stored in SharedPreferences
/// with a single JSON string (key: 'oye_settings').
class AppSettings {
  // ── Playback ──────────────────────────────────────────────────────────────
  final bool autoplay;
  final AudioQuality audioQuality;
  final String repeatMode; // 'off' | 'one' | 'all'

  // ── Network ───────────────────────────────────────────────────────────────
  final bool wifiOnly;
  final bool dataSaver;

  // ── Extractor ─────────────────────────────────────────────────────────────
  final ExtractorType primaryExtractor;
  final bool enableFallback;
  final ClientType clientType;

  // ── Cache ─────────────────────────────────────────────────────────────────
  final bool cacheEnabled;
  final int cacheSizeMb;

  // ── UI ────────────────────────────────────────────────────────────────────
  final bool darkMode;

  // ── Debug ─────────────────────────────────────────────────────────────────
  final bool advancedMode;

  const AppSettings({
    this.autoplay = true,
    this.audioQuality = AudioQuality.high,
    this.repeatMode = 'off',
    this.wifiOnly = false,
    this.dataSaver = false,
    this.primaryExtractor = ExtractorType.auto,
    this.enableFallback = true,
    this.clientType = ClientType.android,
    this.cacheEnabled = true,
    this.cacheSizeMb = 256,
    this.darkMode = true,
    this.advancedMode = false,
  });

  static const AppSettings defaults = AppSettings();

  AppSettings copyWith({
    bool? autoplay,
    AudioQuality? audioQuality,
    String? repeatMode,
    bool? wifiOnly,
    bool? dataSaver,
    ExtractorType? primaryExtractor,
    bool? enableFallback,
    ClientType? clientType,
    bool? cacheEnabled,
    int? cacheSizeMb,
    bool? darkMode,
    bool? advancedMode,
  }) =>
      AppSettings(
        autoplay: autoplay ?? this.autoplay,
        audioQuality: audioQuality ?? this.audioQuality,
        repeatMode: repeatMode ?? this.repeatMode,
        wifiOnly: wifiOnly ?? this.wifiOnly,
        dataSaver: dataSaver ?? this.dataSaver,
        primaryExtractor: primaryExtractor ?? this.primaryExtractor,
        enableFallback: enableFallback ?? this.enableFallback,
        clientType: clientType ?? this.clientType,
        cacheEnabled: cacheEnabled ?? this.cacheEnabled,
        cacheSizeMb: cacheSizeMb ?? this.cacheSizeMb,
        darkMode: darkMode ?? this.darkMode,
        advancedMode: advancedMode ?? this.advancedMode,
      );

  // ── Serialisation ─────────────────────────────────────────────────────────

  factory AppSettings.fromMap(Map<String, dynamic> m) => AppSettings(
        autoplay: m['autoplay'] as bool? ?? true,
        audioQuality: AudioQuality.fromString(m['audioQuality'] as String?),
        repeatMode: m['repeatMode'] as String? ?? 'off',
        wifiOnly: m['wifiOnly'] as bool? ?? false,
        dataSaver: m['dataSaver'] as bool? ?? false,
        primaryExtractor:
            ExtractorType.fromString(m['primaryExtractor'] as String?),
        enableFallback: m['enableFallback'] as bool? ?? true,
        clientType: ClientType.fromString(m['clientType'] as String?),
        cacheEnabled: m['cacheEnabled'] as bool? ?? true,
        cacheSizeMb: m['cacheSizeMb'] as int? ?? 256,
        darkMode: m['darkMode'] as bool? ?? true,
        advancedMode: m['advancedMode'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'autoplay': autoplay,
        'audioQuality': audioQuality.value,
        'repeatMode': repeatMode,
        'wifiOnly': wifiOnly,
        'dataSaver': dataSaver,
        'primaryExtractor': primaryExtractor.value,
        'enableFallback': enableFallback,
        'clientType': clientType.value,
        'cacheEnabled': cacheEnabled,
        'cacheSizeMb': cacheSizeMb,
        'darkMode': darkMode,
        'advancedMode': advancedMode,
      };
}

// ── Supporting enums ──────────────────────────────────────────────────────────

enum AudioQuality {
  low('low', 'Low  (64 kbps)'),
  medium('medium', 'Medium  (128 kbps)'),
  high('high', 'High  (256 kbps)');

  const AudioQuality(this.value, this.label);
  final String value;
  final String label;

  static AudioQuality fromString(String? s) =>
      AudioQuality.values.firstWhere((e) => e.value == s,
          orElse: () => AudioQuality.high);
}

enum ExtractorType {
  auto('auto', 'Auto (recommended)'),
  newpipe('newpipe', 'NewPipe  (Android native)'),
  innertube('innertube', 'InnerTube  (Dart)');

  const ExtractorType(this.value, this.label);
  final String value;
  final String label;

  static ExtractorType fromString(String? s) =>
      ExtractorType.values.firstWhere((e) => e.value == s,
          orElse: () => ExtractorType.auto);
}

enum ClientType {
  android('ANDROID', 'Android'),
  web('WEB', 'Web'),
  tv('TV', 'TV (Embeds)');

  const ClientType(this.value, this.label);
  final String value;
  final String label;

  static ClientType fromString(String? s) =>
      ClientType.values.firstWhere((e) => e.value == s,
          orElse: () => ClientType.android);
}
