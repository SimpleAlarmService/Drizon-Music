import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'services/music_service.dart';
import 'services/player_service.dart';
import 'services/storage_service.dart';
import 'services/settings_service.dart';
import 'screens/main_screen.dart';
import 'theme.dart';

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

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF0D0D0D),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  // Shared prefs shared between StorageService and SettingsService
  final prefs = await SharedPreferences.getInstance();

  final storage = StorageService();
  await storage.initWithPrefs(prefs);

  final settingsService = SettingsService();
  await settingsService.init(prefs);

  final music = MusicService();
  // Apply persisted extractor settings before any stream calls
  music.applySettings(settingsService.settings);

  final player = PlayerService(music, storage, settingsService);
  await player.restoreState();

  runApp(
    MultiProvider(
      providers: [
        Provider<MusicService>.value(value: music),
        Provider<StorageService>.value(value: storage),
        ChangeNotifierProvider<SettingsService>.value(value: settingsService),
        ChangeNotifierProvider<PlayerService>.value(value: player),
      ],
      child: const OyeApp(),
    ),
  );
}

class OyeApp extends StatelessWidget {
  const OyeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drizon',
      theme: oyeTheme,
      debugShowCheckedModeBanner: false,
      home: const MainScreen(),
    );
  }
}
