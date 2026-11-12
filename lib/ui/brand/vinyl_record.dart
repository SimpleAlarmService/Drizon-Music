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

/// Flat, simple record: black disc, two faint grooves, red label, a small dot
/// on the label (so the spin is visible) and the spindle hole.
class _DiscPainter extends CustomPainter {
  const _DiscPainter(this.label);
  final Color label;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;

    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF141416));

    final groove = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(0.5, r * 0.035)
      ..color = Colors.white.withValues(alpha: 0.13);
    canvas.drawCircle(c, r * 0.80, groove);
    canvas.drawCircle(c, r * 0.62, groove);

    canvas.drawCircle(c, r * 0.40, Paint()..color = label);
    canvas.drawCircle(
        c + Offset(0, -r * 0.26), math.max(0.6, r * 0.055), Paint()..color = Colors.white);
    canvas.drawCircle(c, math.max(0.6, r * 0.07), Paint()..color = const Color(0xFF141416));
  }

  @override
  bool shouldRepaint(_DiscPainter old) => old.label != label;
}

/// A single soft highlight that stays put while the record turns.
class _SheenPainter extends CustomPainter {
  const _SheenPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r * 0.71),
      -math.pi * 0.92,
      math.pi * 0.34,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(0.6, r * 0.09)
        ..color = Colors.white.withValues(alpha: 0.22),
    );
  }

  @override
  bool shouldRepaint(_SheenPainter old) => false;
}
