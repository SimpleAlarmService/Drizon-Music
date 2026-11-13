import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/player_service.dart';
import '../../theme.dart';
import 'vinyl_record.dart';

/// "Drizon Music" set in 에이투지체 (A2Z), with the "o" drawn as a vinyl record
/// that spins while music plays. "Drizon" is heavy and "Music" light; everything
/// is white on dark and black on light.
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
    final pal = context.pal;
    final ink = color ?? pal.label; // white (dark mode) / black (light mode)
    final playing = spinning ??
        (context.select<PlayerService?, bool>((p) => p?.isPlaying ?? false));
    final style = TextStyle(
      fontFamily: fontFamily,
      fontSize: fontSize,
      height: 1.1,
      color: ink,
      fontWeight: FontWeight.w800,
      letterSpacing: 0,
    );
    final light = style.copyWith(fontWeight: FontWeight.w400, letterSpacing: -fontSize * 0.01);
    // The record takes the exact place of A2Z ExtraBold's "o" (font units /
    // em): it spans -0.089..0.528 vertically (A2Z letters sit a little below
    // the baseline) and is centred in the glyph's 0.672 advance, so its top
    // and bottom line up with "n" and "z" including the round overshoot.
    const oTop = 0.528, oBottom = -0.089, oAdvance = 0.672;
    final record = fontSize * (oTop - oBottom);
    final side = fontSize * (oAdvance - (oTop - oBottom)) / 2;
    final drop = -oBottom * fontSize;

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
                padding: EdgeInsets.symmetric(horizontal: side),
                // Placed bottom-on-baseline, then lowered to the letters' bottom.
                child: Transform.translate(
                  offset: Offset(0, drop),
                  child: VinylRecord(
                      size: record, spinning: playing, ink: ink, paper: pal.background),
                ),
              ),
            ),
            const TextSpan(text: 'n '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: Text('Music', style: light),
            ),
          ]),
        ),
      ),
    );
  }
}
