import 'package:flutter/material.dart';

import '../glass/liquid_glass.dart';
import 'vinyl_record.dart';

/// The app icon artwork: a vinyl record resting on a pane of liquid glass over
/// a warm red gradient. Rendered to PNG by test/render_app_icon_test.dart.
///
/// [foregroundOnly] draws just the glass and record on transparency (Android
/// adaptive-icon foreground, inside the 66% safe zone).
class AppIconArt extends StatelessWidget {
  const AppIconArt({super.key, this.size = 1024, this.foregroundOnly = false});
  final double size;
  final bool foregroundOnly;

  static const background = [Color(0xFFFF6A5C), Color(0xFFFA2D48), Color(0xFF7A1035)];

  @override
  Widget build(BuildContext context) {
    final s = size;
    final pane = s * (foregroundOnly ? 0.56 : 0.70);
    final record = pane * 0.78;

    final glassAndRecord = SizedBox.square(
      dimension: pane,
      child: Stack(alignment: Alignment.center, children: [
        Theme(
          data: ThemeData(brightness: Brightness.dark),
          child: LiquidGlass(
            borderRadius: BorderRadius.all(Radius.circular(pane * 0.30)),
            blur: s * 0.03,
            tint: Colors.white.withValues(alpha: 0.16),
            highlight: 1.5,
            child: const SizedBox.expand(),
          ),
        ),
        // Soft contact shadow so the record sits on the glass.
        Container(
          width: record,
          height: record,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: s * 0.05,
                offset: Offset(0, s * 0.02),
              ),
            ],
          ),
        ),
        VinylRecord(size: record),
      ]),
    );

    if (foregroundOnly) {
      return SizedBox.square(dimension: s, child: Center(child: glassAndRecord));
    }

    return SizedBox.square(
      dimension: s,
      child: Stack(alignment: Alignment.center, children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: background,
              stops: [0.0, 0.45, 1.0],
            ),
          ),
          child: SizedBox.expand(),
        ),
        // Glow blobs give the glass something colourful to refract.
        Positioned(
          left: -s * 0.15,
          top: -s * 0.1,
          child: _Glow(size: s * 0.75, color: const Color(0xFFFFB199)),
        ),
        Positioned(
          right: -s * 0.2,
          bottom: -s * 0.2,
          child: _Glow(size: s * 0.8, color: const Color(0xFF5B0E8C)),
        ),
        glassAndRecord,
      ]),
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.size, required this.color});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color.withValues(alpha: 0.75), color.withValues(alpha: 0)]),
        ),
      );
}
