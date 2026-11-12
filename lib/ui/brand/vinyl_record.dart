import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// A vinyl record: grooves, a red centre label and a light sheen.
///
/// While [spinning] it turns at 33⅓ rpm, spinning up and slowing down like a
/// real turntable. The sheen is painted on a separate, non-rotating layer, so
/// the reflection stays put while the record turns under it.
class VinylRecord extends StatefulWidget {
  const VinylRecord({
    super.key,
    required this.size,
    this.spinning = false,
    this.labelColor = const Color(0xFFFA2D48),
  });

  final double size;
  final bool spinning;
  final Color labelColor;

  @override
  State<VinylRecord> createState() => _VinylRecordState();
}

class _VinylRecordState extends State<VinylRecord> with SingleTickerProviderStateMixin {
  static const _rpm = 100 / 3; // 33⅓
  static const _maxSpeed = _rpm * 2 * math.pi / 60; // rad/s
  static const _spinUp = 1.6; // rad/s² — reaches speed in ~2 s

  late final Ticker _ticker;
  final _angle = ValueNotifier<double>(0);
  double _speed = 0;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    if (widget.spinning) _ticker.start();
  }

  @override
  void didUpdateWidget(VinylRecord old) {
    super.didUpdateWidget(old);
    if (widget.spinning && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final dt = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    final target = widget.spinning ? _maxSpeed : 0.0;
    // Ease the speed toward the target (turntable inertia).
    final step = _spinUp * dt * (widget.spinning ? 1 : 1.4);
    _speed = _speed < target ? math.min(target, _speed + step) : math.max(target, _speed - step);
    _angle.value = (_angle.value + _speed * dt) % (2 * math.pi);
    if (!widget.spinning && _speed == 0) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _angle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(fit: StackFit.expand, children: [
        ValueListenableBuilder<double>(
          valueListenable: _angle,
          builder: (_, a, child) => Transform.rotate(angle: a, child: child),
          child: CustomPaint(painter: _DiscPainter(widget.labelColor)),
        ),
        const IgnorePointer(child: CustomPaint(painter: _SheenPainter())),
      ]),
    );
  }
}

class _DiscPainter extends CustomPainter {
  const _DiscPainter(this.label);
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    // Vinyl body.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF2A2A2E), Color(0xFF111114), Color(0xFF050506)],
          stops: [0.0, 0.7, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Grooves: fine rings, slightly uneven like a pressed record.
    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.35, r * 0.006);
    for (var gr = r * 0.40; gr < r * 0.95; gr += r * 0.032) {
      final t = (gr / r * 37).floor() % 3;
      groove.color = Colors.white.withValues(alpha: t == 0 ? 0.10 : 0.05);
      canvas.drawCircle(c, gr, groove);
    }
    // Lead-in and run-out edges.
    canvas.drawCircle(
        c,
        r * 0.985,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.02
          ..color = Colors.white.withValues(alpha: 0.08));

    // Label with a tiny printed mark so the rotation is visible.
    final labelR = r * 0.34;
    canvas.drawCircle(
      c,
      labelR,
      Paint()
        ..shader = RadialGradient(
          colors: [Color.lerp(label, Colors.white, 0.18)!, label, Color.lerp(label, Colors.black, 0.25)!],
          stops: const [0.0, 0.6, 1.0],
        ).createShader(Rect.fromCircle(center: c, radius: labelR)),
    );
    canvas.drawCircle(
        c,
        labelR * 0.78,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.4, r * 0.008)
          ..color = Colors.white.withValues(alpha: 0.35));
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: labelR * 0.55),
        -math.pi * 0.85,
        math.pi * 0.5,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = math.max(0.6, r * 0.03)
          ..color = Colors.white.withValues(alpha: 0.85));

    // Spindle hole.
    canvas.drawCircle(c, r * 0.045, Paint()..color = const Color(0xFF0B0B0D));
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.label != label;
}

/// Light reflected off the grooves: two opposite soft wedges plus a rim light.
class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.save();
    canvas.clipPath(Path()
      ..addOval(rect)
      ..addOval(Rect.fromCircle(center: c, radius: r * 0.35))
      ..fillType = PathFillType.evenOdd);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.22),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.0),
            Colors.white.withValues(alpha: 0.14),
            Colors.white.withValues(alpha: 0.0),
          ],
          stops: const [0.02, 0.10, 0.20, 0.52, 0.60, 0.70],
        ).createShader(rect),
    );
    canvas.restore();
    canvas.drawCircle(
        c,
        r - 0.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0.02)],
          ).createShader(rect));
  }

  @override
  bool shouldRepaint(_SheenPainter old) => false;
}
