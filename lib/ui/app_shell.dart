import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/player_service.dart';
import '../theme.dart';
import 'glass/liquid_glass.dart';
import 'pages/home_page.dart';
import 'pages/library_page.dart';
import 'pages/now_playing_page.dart';
import 'pages/search_page.dart';
import 'pages/videos_page.dart';
import 'widgets/mini_player.dart';

/// Pages fill the screen; the mini player and tab bar float above them as
/// liquid glass, so content scrolls underneath and shows through.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _tab = 0;

  static const _items = [
    GlassTabItem(CupertinoIcons.play_circle_fill, '지금 듣기'),
    GlassTabItem(CupertinoIcons.play_rectangle_fill, '비디오'),
    GlassTabItem(CupertinoIcons.music_albums_fill, '보관함'),
    GlassTabItem(CupertinoIcons.search, '검색'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = math.max(MediaQuery.paddingOf(context).bottom, 10.0);
    final hasTrack = context.select<PlayerService, bool>((p) => p.currentTrack != null);
    final inset = bottom + GlassTabBar.height + (hasTrack ? MiniPlayer.height + 8 : 0) + 20;

    return Scaffold(
      backgroundColor: context.pal.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: ShellInsets(
                bottom: inset,
                child: _TabStack(
                  index: _tab,
                  children: [
                    HomePage(onSearch: () => setState(() => _tab = 3)),
                    const VideosPage(),
                    const LibraryPage(),
                    const SearchPage(),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: bottom,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MiniPlayer(
                  onTap: () =>
                      Navigator.of(context, rootNavigator: true).push(NowPlayingPage.route()),
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: SizedBox(height: hasTrack ? 8 : 0),
                ),
                GlassTabBar(
                  items: _items,
                  currentIndex: _tab,
                  onTap: (i) => setState(() => _tab = i),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Keeps every tab alive (like IndexedStack) but cross-fades with a slight
/// zoom when switching. Hidden tabs go offstage once their fade finishes.
class _TabStack extends StatelessWidget {
  const _TabStack({required this.index, required this.children});
  final int index;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < children.length; i++)
            _FadingTab(active: i == index, child: children[i]),
        ],
      );
}

class _FadingTab extends StatefulWidget {
  const _FadingTab({required this.active, required this.child});
  final bool active;
  final Widget child;

  @override
  State<_FadingTab> createState() => _FadingTabState();
}

class _FadingTabState extends State<_FadingTab> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
    value: widget.active ? 1 : 0,
  )..addStatusListener((_) => setState(() {}));

  @override
  void didUpdateWidget(_FadingTab old) {
    super.didUpdateWidget(old);
    if (widget.active != old.active) widget.active ? _c.forward() : _c.reverse();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hidden = !widget.active && _c.isDismissed;
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return Offstage(
      offstage: hidden,
      child: TickerMode(
        enabled: !hidden,
        child: IgnorePointer(
          ignoring: !widget.active,
          child: FadeTransition(
            opacity: t,
            child: ScaleTransition(
              scale: Tween(begin: 0.975, end: 1.0).animate(t),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
