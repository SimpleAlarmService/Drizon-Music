import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

/// Saturation boost applied to whatever shows through the glass, so colours
/// behind it glow instead of turning grey (the "Liquid Glass" look).
const List<double> _saturate = [
  1.42, -0.37, -0.05, 0, 0, //
  -0.13, 1.18, -0.05, 0, 0, //
  -0.13, -0.37, 1.50, 0, 0, //
  0, 0, 0, 1, 0,
];

/// A pane of liquid glass: blurred and saturated backdrop, a soft tint, a
/// specular highlight along the top and a two-sided rim light, with
/// continuous-curvature (squircle) corners.
class LiquidGlass extends StatelessWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(28)),
    this.blur = 22,
    this.tint,
    this.shadow = true,
    this.highlight = 1.0,
  });

  /// Capsule (fully rounded ends).
  const LiquidGlass.capsule({
    super.key,
    required this.child,
    this.blur = 22,
    this.tint,
    this.shadow = true,
    this.highlight = 1.0,
  }) : borderRadius = const BorderRadius.all(Radius.circular(999));

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;
  final Color? tint;
  final bool shadow;

  /// 0..1+, how bright the rim and specular highlight are (raised when pressed).
  final double highlight;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final shape = RoundedSuperellipseBorder(borderRadius: borderRadius);
    final baseTint = tint ??
        (dark ? Colors.white.withValues(alpha: 0.07) : Colors.white.withValues(alpha: 0.42));

    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        shadows: shadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? 0.45 : 0.14),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : null,
      ),
      child: ClipRSuperellipse(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.compose(
            outer: const ColorFilter.matrix(_saturate),
            inner: ImageFilter.blur(sigmaX: blur, sigmaY: blur, tileMode: TileMode.mirror),
          ),
          child: CustomPaint(
            foregroundPainter: _RimPainter(borderRadius, dark, highlight),
            // Tint and highlight are separate layers: a BoxDecoration ignores
            // its colour when it also has a gradient.
            child: ColoredBox(
              color: baseTint,
              child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: (dark ? 0.13 : 0.30) * highlight),
                    Colors.white.withValues(alpha: 0.0),
                    Colors.white.withValues(alpha: dark ? 0.02 : 0.06),
                  ],
                  stops: const [0.0, 0.42, 1.0],
                ),
              ),
              child: child,
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Edge light: bright where light enters (top-left), a faint second reflection
/// on the opposite edge, plus a hairline inner edge for thickness.
class _RimPainter extends CustomPainter {
  _RimPainter(this.radius, this.dark, this.highlight);
  final BorderRadius radius;
  final bool dark;
  final double highlight;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outer = Path()..addRSuperellipse(radius.toRSuperellipse(rect.deflate(0.5)));
    final h = highlight.clamp(0.0, 1.6);
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: (dark ? 0.55 : 0.85) * h),
            Colors.white.withValues(alpha: dark ? 0.06 : 0.20),
            Colors.white.withValues(alpha: (dark ? 0.28 : 0.55) * h),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    final inner = Path()
      ..addRSuperellipse(radius
          .subtract(const BorderRadius.all(Radius.circular(1.5)))
          .resolve(TextDirection.ltr)
          .toRSuperellipse(rect.deflate(2)));
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = (dark ? Colors.black : Colors.white).withValues(alpha: dark ? 0.18 : 0.25),
    );
  }

  @override
  bool shouldRepaint(_RimPainter old) =>
      old.radius != radius || old.dark != dark || old.highlight != highlight;
}

/// Liquid press feedback: squashes a little under the finger and springs back
/// with a slight overshoot. [builder] gets 0..1 press depth (for highlights).
class GlassPressable extends StatefulWidget {
  const GlassPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.depth = 0.06,
    this.haptic = true,
    this.builder,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double depth;
  final bool haptic;
  final Widget Function(BuildContext, double press, Widget child)? builder;

  @override
  State<GlassPressable> createState() => _GlassPressableState();
}

class _GlassPressableState extends State<GlassPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController.unbounded(vsync: this);
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 420, ratio: 0.55);

  void _to(double target) => _c.animateWith(SpringSimulation(_spring, _c.value, target, _c.velocity));

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _to(1) : null,
      onTapUp: enabled ? (_) => _to(0) : null,
      onTapCancel: enabled ? () => _to(0) : null,
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) HapticFeedback.lightImpact();
              widget.onTap!();
            },
      onLongPress: widget.onLongPress,
      child: AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final p = _c.value;
          // Liquid squash: a touch wider than tall while pressed.
          final sx = 1 - widget.depth * p * 0.6;
          final sy = 1 - widget.depth * p;
          final inner = widget.builder?.call(context, p.clamp(0.0, 1.2), child!) ?? child!;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.diagonal3Values(sx, sy, 1),
            child: inner,
          );
        },
      ),
    );
  }
}

/// Glass button (circle or capsule) with liquid press feedback.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.onTap,
    this.icon,
    this.label,
    this.size = 44,
    this.color,
    this.tint,
    this.iconSize,
  });

  final VoidCallback? onTap;
  final IconData? icon;
  final String? label;
  final double size; // height (and width for icon-only)
  final Color? color;
  final Color? tint;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final fg = color ?? Theme.of(context).colorScheme.onSurface;
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (icon != null) Icon(icon, color: fg, size: iconSize ?? size * 0.46),
        if (icon != null && label != null) const SizedBox(width: 8),
        if (label != null)
          Text(label!,
              style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
    return GlassPressable(
      onTap: onTap,
      builder: (context, press, child) => LiquidGlass.capsule(
        tint: tint,
        shadow: false,
        highlight: 1 + press * 0.6,
        child: child,
      ),
      child: SizedBox(
        height: size,
        width: label == null ? size : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 0 : 18),
          child: Center(child: content),
        ),
      ),
    );
  }
}

class GlassTabItem {
  const GlassTabItem(this.icon, this.label);
  final IconData icon;
  final String label;
}

/// Floating glass tab bar. The selection is a glass droplet that springs to
/// the new tab, stretching with its speed and wobbling as it settles.
class GlassTabBar extends StatefulWidget {
  const GlassTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.activeColor = const Color(0xFFFA2D48),
  });

  final List<GlassTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final Color activeColor;

  static const height = 64.0;

  @override
  State<GlassTabBar> createState() => _GlassTabBarState();
}

class _GlassTabBarState extends State<GlassTabBar> with SingleTickerProviderStateMixin {
  late final AnimationController _pos =
      AnimationController.unbounded(vsync: this, value: widget.currentIndex.toDouble());
  static final _spring = SpringDescription.withDampingRatio(mass: 1, stiffness: 300, ratio: 0.68);

  @override
  void didUpdateWidget(GlassTabBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      _pos.animateWith(
          SpringSimulation(_spring, _pos.value, widget.currentIndex.toDouble(), _pos.velocity));
    }
  }

  @override
  void dispose() {
    _pos.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final inactive = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);
    return SizedBox(
      height: GlassTabBar.height,
      child: LiquidGlass.capsule(
        child: LayoutBuilder(builder: (context, c) {
          final itemW = c.maxWidth / widget.items.length;
          return AnimatedBuilder(
            animation: _pos,
            builder: (context, _) {
              final speed = _pos.velocity.abs();
              final stretch = 1 + math.min(0.5, speed * 0.09);
              final squeeze = 1 - math.min(0.18, speed * 0.03);
              final w = (itemW - 8) * stretch;
              final h = (GlassTabBar.height - 10) * squeeze;
              final cx = (_pos.value + 0.5) * itemW;
              return Stack(children: [
                Positioned(
                  left: cx - w / 2,
                  top: (GlassTabBar.height - h) / 2,
                  width: w,
                  height: h,
                  child: LiquidGlass.capsule(
                    shadow: false,
                    blur: 0.01,
                    tint: dark
                        ? Colors.white.withValues(alpha: 0.13)
                        : Colors.black.withValues(alpha: 0.06),
                    highlight: 1.2,
                    child: const SizedBox.expand(),
                  ),
                ),
                Row(children: [
                  for (var i = 0; i < widget.items.length; i++)
                    Expanded(
                      child: GlassPressable(
                        depth: 0.1,
                        onTap: () => widget.onTap(i),
                        child: _TabLabel(
                          item: widget.items[i],
                          // Light up as the droplet arrives.
                          active: (1 - (_pos.value - i).abs()).clamp(0.0, 1.0),
                          activeColor: widget.activeColor,
                          inactiveColor: inactive,
                        ),
                      ),
                    ),
                ]),
              ]);
            },
          );
        }),
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({
    required this.item,
    required this.active,
    required this.activeColor,
    required this.inactiveColor,
  });
  final GlassTabItem item;
  final double active;
  final Color activeColor;
  final Color inactiveColor;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(inactiveColor, activeColor, active)!;
    return Semantics(
      selected: active > 0.5,
      button: true,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Transform.scale(
            scale: 1 + 0.12 * active,
            child: Icon(item.icon, color: color, size: 23),
          ),
          const SizedBox(height: 2),
          Text(item.label,
              maxLines: 1,
              style: TextStyle(
                  color: color, fontSize: 10, fontWeight: active > 0.5 ? FontWeight.w700 : FontWeight.w500)),
        ],
      ),
    );
  }
}

/// Space the floating glass bars take at the bottom; scrolling content pads
/// by this so its end can scroll out from under the glass.
class ShellInsets extends InheritedWidget {
  const ShellInsets({super.key, required this.bottom, required super.child});
  final double bottom;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ShellInsets>()?.bottom ?? 0;

  @override
  bool updateShouldNotify(ShellInsets old) => old.bottom != bottom;
}

/// Fades and lifts a child in once, staggered by [index] (capped).
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 520));

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 45 * math.min(widget.index, 8)), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: t,
      child: AnimatedBuilder(
        animation: t,
        child: widget.child,
        builder: (_, child) => Transform.translate(
          offset: Offset(0, 14 * (1 - t.value)),
          child: child,
        ),
      ),
    );
  }
}
