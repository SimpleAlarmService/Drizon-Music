import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import 'vinyl_record.dart';

/// "Drizon Music" set in 에이투지체 (A2Z), with the "o" drawn as a vinyl record
/// that spins while music plays. "Drizon" is heavy, "Music" light and red.
class DrizonLogo extends StatelessWidget {
  const DrizonLogo({
    super.key,
    this.fontSize = 40,
    this.color,
    this.spinning,
    this.fontFamily = DrizonLogo.font,
  });

  static const font = 'A2Z';

  final double fontSize;
  final Color? color;
  final bool? spinning; // null → follows playback
  final String fontFamily;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? Theme.of(context).colorScheme.onSurface;
    final playing = spinning ??
        (context.select<PlayerService?, bool>((p) => p?.isPlaying ?? false));
    final style = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.1,
      color: ink,
      fontWeight: FontWeight.w800,
      letterSpacing: -fontSize * 0.03,
    );
    final light = style.copyWith(fontWeight: FontWeight.w400, letterSpacing: -fontSize * 0.01);
    // The record sits on the baseline, a touch taller than the x-height so it
    // reads as a record rather than a dot.
    final record = fontSize * 0.60;

    return Semantics(
      label: 'Drizon Music',
      child: ExcludeSemantics(
        child: Text.rich(
          TextSpan(style: style, children: [
            const TextSpan(text: 'Driz'),
            // The record stands on the baseline like a lowercase "o".
            WidgetSpan(
              alignment: PlaceholderAlignment.aboveBaseline,
              baseline: TextBaseline.alphabetic,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: fontSize * 0.035),
                child: VinylRecord(size: record, spinning: playing),
              ),
            ),
            const TextSpan(text: 'n '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: ShaderMask(
                blendMode: BlendMode.srcIn,
                shaderCallback: (r) => const LinearGradient(
                  colors: [Color(0xFFFF5F6D), Color(0xFFFA2D48)],
                ).createShader(r),
                child: Text('Music', style: light),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
