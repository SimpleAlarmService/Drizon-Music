import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/now_playing_page.dart';
import 'pages/search_page.dart';
import 'widgets/mini_player.dart';

/// Tab scaffold: pages, the floating mini player, and a translucent tab bar.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: IndexedStack(
                index: _tab,
                children: [
                  HomePage(onSearch: () => setState(() => _tab = 1)),
                  const SearchPage(),
                  const LibraryPage(),
                ],
              ),
            ),
          ),
          MiniPlayer(
            onTap: () =>
                Navigator.of(context, rootNavigator: true).push(NowPlayingPage.route()),
          ),
          CupertinoTabBar(
            currentIndex: _tab,
            onTap: (i) => setState(() => _tab = i),
            activeColor: kAccent,
            inactiveColor: pal.secondaryLabel,
            backgroundColor: pal.surface.withValues(alpha: 0.94),
            border: Border(top: BorderSide(color: pal.separator, width: 0.33)),
            items: const [
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.play_circle_fill), label: '지금 듣기'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.search), label: '검색'),
              BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.music_albums_fill), label: '보관함'),
            ],
          ),
        ],
      ),
    );
  }
}
