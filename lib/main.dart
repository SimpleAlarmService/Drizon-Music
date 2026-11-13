import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/download_service.dart';
import 'services/extractor_update_service.dart';
import 'services/engines/bugs_client.dart';
import 'services/engines/ytmusic_client.dart';
import 'services/library_service.dart';
import 'services/metadata_service.dart';
import 'services/music_service.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'theme.dart';
import 'services/chart_service.dart';
import 'ui/pages/theme_choice_page.dart';
import 'ui/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // The SIL OFL asks for the licence to travel with the font.
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(
        const ['에이투지체 (A2Z)'], await rootBundle.loadString('assets/fonts/A2Z-OFL.txt'));
  });

  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.oye.oye.channel.audio',
    androidNotificationChannelName: 'Drizon Audio playback',
    androidNotificationOngoing: true,
  );

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Shared prefs shared between StorageService and SettingsService
  final prefs = await SharedPreferences.getInstance();

  final storage = StorageService();
  await storage.initWithPrefs(prefs);

  final settings = SettingsService();
  await settings.init(prefs);

  final ytm = YtmClient();
  final bugs = BugsClient();
  final metadata = MetadataService(prefs, ytm, bugs);

  final music = MusicService(ytm: ytm);
  music.applySettings(settings.settings);
  // Keep extractor behaviour in sync with the settings screen.
  settings.addListener(() => music.applySettings(settings.settings));

  final extractorUpdates = ExtractorUpdateService(music, prefs);
  final charts = ChartService(music, prefs);

  final downloads = DownloadService(prefs, music,
      directory: getApplicationDocumentsDirectory);
  await downloads.init();

  metadata.offline = downloads;
  downloads.onDownloaded = metadata.saveOffline;

  final library = LibraryService(storage, downloads: downloads);
  final player = PlayerService(music, storage, settings)
    ..onHistoryChanged = library.historyChanged
    ..onTrackStarted = metadata.prefetch
    ..localFileFor = downloads.localPath
    ..localCoverFor = downloads.localCover
    ..cacheFor = downloads.cacheForPlayback;
  await player.restoreState();

  runApp(
    MultiProvider(
      providers: [
        Provider<MusicService>.value(value: music),
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<PlayerService>.value(value: player),
        ChangeNotifierProvider<LibraryService>.value(value: library),
        ChangeNotifierProvider<MetadataService>.value(value: metadata),
        ChangeNotifierProvider<DownloadService>.value(value: downloads),
        Provider<YtmClient>.value(value: ytm),
        ChangeNotifierProvider<ExtractorUpdateService>.value(value: extractorUpdates),
        ChangeNotifierProvider<ChartService>.value(value: charts),
      ],
      child: const DrizonApp(),
    ),
  );

  extractorUpdates.checkOnLaunch();
  charts.load();
}

class DrizonApp extends StatelessWidget {
  const DrizonApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.select<SettingsService, bool>((s) => s.settings.darkMode);
    final chosen = context.select<SettingsService, bool>((s) => s.themeChosen);
    return MaterialApp(
      title: 'Drizon',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
        value: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: child!,
      ),
      home: chosen ? const AppShell() : const ThemeChoicePage(),
    );
  }
}
