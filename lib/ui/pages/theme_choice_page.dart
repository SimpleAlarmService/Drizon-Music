import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/settings_service.dart';
import '../../theme.dart';
import '../brand/drizon_logo.dart';

/// Shown once, on first launch: pick light or dark. The choice is applied live
/// behind the screen so the user sees it before confirming.
class ThemeChoicePage extends StatelessWidget {
  const ThemeChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final pal = context.pal;
    final settings = context.watch<SettingsService>();
    final dark = settings.settings.darkMode;

    return Scaffold(
      backgroundColor: pal.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const DrizonLogo(fontSize: 38, spinning: false),
                  const SizedBox(height: 28),
                  Text('화면 모드를 선택하세요', style: Type.title(pal)),
                  const SizedBox(height: 6),
                  Text('나중에 설정에서 언제든 바꿀 수 있어요.', style: Type.sub(pal)),
                  const SizedBox(height: 28),
                  Row(
                    children: [
                      Expanded(
                        child: _ModeCard(
                          label: '화이트',
                          dark: false,
                          selected: !dark,
                          onTap: () => settings.setDarkMode(false),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _ModeCard(
                          label: '다크',
                          dark: true,
                          selected: dark,
                          onTap: () => settings.setDarkMode(true),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: CupertinoButton.filled(
                      onPressed: settings.confirmTheme,
                      child: const Text('시작하기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.label,
    required this.dark,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = dark ? Palette.dark : Palette.light;
    final pal = context.pal;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 170,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: preview.background,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? kAccent : pal.separator,
                width: selected ? 3 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                    height: 10,
                    width: 60,
                    decoration: BoxDecoration(
                        color: preview.label, borderRadius: BorderRadius.circular(5))),
                const SizedBox(height: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                        color: preview.surface, borderRadius: BorderRadius.circular(12)),
                    child: Center(
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration:
                            BoxDecoration(color: preview.label, shape: BoxShape.circle),
                        child: Center(
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                                color: preview.background, shape: BoxShape.circle),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                  size: 20, color: selected ? kAccent : pal.secondaryLabel),
              const SizedBox(width: 6),
              Text(label, style: Type.row(pal)),
            ],
          ),
        ],
      ),
    );
  }
}
