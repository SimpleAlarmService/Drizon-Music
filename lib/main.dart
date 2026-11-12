import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/library_service.dart';
import 'services/music_service.dart';
import 'services/player_service.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'theme.dart';
import 'ui/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  final music = MusicService();
  music.applySettings(settings.settings);
  // Keep extractor behaviour in sync with the settings screen.
  settings.addListener(() => music.applySettings(settings.settings));

  final library = LibraryService(storage);
  final player = PlayerService(music, storage, settings)
    ..onHistoryChanged = library.historyChanged;
  await player.restoreState();

  runApp(
    MultiProvider(
      providers: [
        Provider<MusicService>.value(value: music),
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<PlayerService>.value(value: player),
        ChangeNotifierProvider<LibraryService>.value(value: library),
      ],
      child: const DrizonApp(),
    ),
  );
}

class DrizonApp extends StatelessWidget {
  const DrizonApp({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = context.select<SettingsService, bool>((s) => s.settings.darkMode);
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
      home: const AppShell(),
    );
  }
}
