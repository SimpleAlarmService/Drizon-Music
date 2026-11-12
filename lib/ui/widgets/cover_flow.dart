import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// iTunes-style Cover Flow: the centre cover faces front, neighbours swing away
/// at an angle with perspective and a faded reflection underneath.
///
/// A single `position` (fractional item index) drives every cover's transform,
/// so dragging, flinging and programmatic jumps all animate the same way.
/// A plain PageView can't be used: it paints later pages over earlier ones, but
/// the centre cover must always be on top.
class CoverFlow extends StatefulWidget {
  const CoverFlow({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    required this.onIndexChanged,
    this.onTapCenter,
    this.initialIndex = 0,
    this.size = 240,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder; // builds a square cover
  final ValueChanged<int> onIndexChanged; // fires when the centred item changes
  final ValueChanged<int>? onTapCenter;
  final int initialIndex;
  final double size;

  @override
  State<CoverFlow> createState() => CoverFlowState();
}

class CoverFlowState extends State<CoverFlow>
    with SingleTickerProviderStateMixin {
  // Layout constants (fractions of `size`).
  static const _sideOffset = 0.62; // first neighbour's distance from centre
  static const _stackSpacing = 0.20; // spacing between further covers
  static const _maxAngle = 1.05; // radians (~60°)
  static const _sideScale = 0.84;
  static const _reflectionFraction = 0.34;

  late final AnimationController _controller;
  late int _lastIndex;

  double get _position => _controller.value;
  double get _dragUnit => widget.size * 0.40; // px dragged per item

  @override
  void initState() {
    super.initState();
    _controller = AnimationController.unbounded(
      vsync: this,
      value: widget.initialIndex.clamp(0, math.max(0, widget.itemCount - 1)).toDouble(),
    )..addListener(_onTick);
    _lastIndex = _currentIndex;
  }

  @override
  void didUpdateWidget(CoverFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      // Items were removed: pull the position back in range. Deferred, because the
      // resulting onIndexChanged would otherwise call setState during a build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final max = math.max(0, widget.itemCount - 1).toDouble();
        if (_controller.value > max) _controller.value = max;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _currentIndex =>
      _position.round().clamp(0, math.max(0, widget.itemCount - 1));

  void _onTick() {
    final i = _currentIndex;
    if (i != _lastIndex) {
      _lastIndex = i;
      HapticFeedback.selectionClick();
      widget.onIndexChanged(i);
    }
  }

  /// Animate to [index] with a spring.
  void animateTo(int index, {double velocity = 0}) {
    final target = index.clamp(0, math.max(0, widget.itemCount - 1)).toDouble();
    _controller.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(mass: 1, stiffness: 170, ratio: 1.0),
      _position,
      target,
      velocity,
    ));
  }

  void _onDragStart(DragStartDetails _) => _controller.stop();

  void _onDragUpdate(DragUpdateDetails d) {
    final max = math.max(0, widget.itemCount - 1).toDouble();
    // Allow a little rubber-band past either end.
    _controller.value =
        (_position - d.delta.dx / _dragUnit).clamp(-0.35, max + 0.35);
  }

  void _onDragEnd(DragEndDetails d) {
    final v = -(d.primaryVelocity ?? 0) / _dragUnit; // items per second
    final projected = _position + v * 0.12;
    animateTo(projected.round(), velocity: v);
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final height = size * (1 + _reflectionFraction) + 8;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            final pos = _position;
            final lo = math.max(0, (pos - 5).floor());
            final hi = math.min(widget.itemCount - 1, (pos + 5).ceil());
            // Far covers first so the centre cover paints last (on top).
            final indices = [for (var i = lo; i <= hi; i++) i]
              ..sort((a, b) => (b - pos).abs().compareTo((a - pos).abs()));
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [for (final i in indices) _cover(context, i, pos)],
            );
          },
        ),
      ),
    );
  }

  Widget _cover(BuildContext context, int i, double pos) {
    final size = widget.size;
    final d = i - pos;
    final ad = d.abs();
    final near = math.min(ad, 1.0);
    final x = d.sign * (near * _sideOffset + math.max(ad - 1, 0) * _stackSpacing) * size;
    final angle = d.clamp(-1.0, 1.0) * _maxAngle;
    final scale = 1 - (1 - _sideScale) * near;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, 0.0011) // perspective (+z points away from the viewer)
      ..rotateY(angle)
      ..multiply(Matrix4.diagonal3Values(scale, scale, 1.0));

    final cover = SizedBox(
      width: size,
      height: size,
      child: widget.itemBuilder(context, i),
    );

    return Align(
      alignment: Alignment.topCenter,
      child: Transform.translate(
        offset: Offset(x, 0),
        child: Transform(
          transform: matrix,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {
              if (ad < 0.5) {
                widget.onTapCenter?.call(i);
              } else {
                animateTo(i);
              }
            },
            child: SizedBox(
              width: size,
              height: size * (1 + _reflectionFraction) + 2,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  cover,
                  const SizedBox(height: 2),
                  _Reflection(
                    height: size * _reflectionFraction,
                    child: SizedBox(
                      width: size,
                      height: size,
                      child: widget.itemBuilder(context, i),
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

/// Mirrored, fading copy of the bottom of a cover.
class _Reflection extends StatelessWidget {
  const _Reflection({required this.child, required this.height});
  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: 0.32), Colors.transparent],
        ).createShader(rect),
        child: Transform.flip(
          flipY: true,
          child: ClipRect(
            child: OverflowBox(
              alignment: Alignment.bottomCenter,
              minHeight: 0,
              maxHeight: double.infinity,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
