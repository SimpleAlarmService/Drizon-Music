import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../widgets/mini_player.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'search_screen.dart';
import 'library_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _tab = 0;

  static const _screens = [
    HomeScreen(),
    SearchScreen(),
    LibraryScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerService>();
    final hasMiniPlayer = player.currentTrack != null;

    return Scaffold(
      backgroundColor: kSurface,
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: _BottomNav(
        currentIndex: _tab,
        hasMiniPlayer: hasMiniPlayer,
        onTap: (i) => setState(() => _tab = i),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final bool hasMiniPlayer;
  final ValueChanged<int> onTap;

  const _BottomNav({
    required this.currentIndex,
    required this.hasMiniPlayer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tabs = [
      (label: 'Home',    icon: Icons.home_outlined,         activeIcon: Icons.home),
      (label: 'Explore', icon: Icons.explore_outlined,       activeIcon: Icons.explore),
      (label: 'Library', icon: Icons.library_music_outlined, activeIcon: Icons.library_music),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasMiniPlayer) const MiniPlayer(),
        ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
          child: Container(
            decoration: BoxDecoration(
              color: kSurfaceContainer.withValues(alpha: 0.6),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(48)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  blurRadius: 40,
                  offset: const Offset(0, -20),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (int i = 0; i < tabs.length; i++)
                      _NavTab(
                        label: tabs[i].label,
                        icon: tabs[i].icon,
                        activeIcon: tabs[i].activeIcon,
                        isActive: currentIndex == i,
                        onTap: () => onTap(i),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _NavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final IconData activeIcon;
  final bool isActive;
  final VoidCallback onTap;

  const _NavTab({
    required this.label,
    required this.icon,
    required this.activeIcon,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
            horizontal: isActive ? 20 : 12, vertical: 8),
        decoration: BoxDecoration(
          gradient: isActive ? primaryGradient : null,
          borderRadius: BorderRadius.circular(48),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isActive ? activeIcon : icon,
              color: isActive ? kOnPrimary : kOnSurfaceVariant,
              size: 22,
            ),
            if (isActive) ...[
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: GoogleFonts.manrope(
                  color: kOnPrimary,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
