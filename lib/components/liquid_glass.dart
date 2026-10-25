import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

@immutable
class LiquidGlassTheme extends ThemeExtension<LiquidGlassTheme> {
  const LiquidGlassTheme({this.enabled = true});

  final bool enabled;

  @override
  LiquidGlassTheme copyWith({bool? enabled}) =>
      LiquidGlassTheme(enabled: enabled ?? this.enabled);

  @override
  LiquidGlassTheme lerp(LiquidGlassTheme? other, double t) =>
      t < .5 ? this : other ?? this;
}

/// Clear glass: the centre is untouched and a narrow bevel refracts the
/// backdrop. Renderers without shader filters keep a clear, unblurred surface.
class LiquidGlass extends StatefulWidget {
  const LiquidGlass({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(24)),
    this.padding = EdgeInsets.zero,
    this.refract = true,
    this.shadow = true,
    this.bevelWidth = 14,
    this.refraction = 5,
    this.lightIntensity = 1,
    this.tint = Colors.transparent,
  }) : assert(bevelWidth > 0),
       assert(refraction >= 0),
       assert(lightIntensity >= 0);

  final Widget child;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final bool refract;
  final bool shadow;
  final double bevelWidth;
  final double refraction;
  final double lightIntensity;
  // The centre can be tinted while the bevel stays clear enough to refract.
  final Color tint;

  static Future<ui.FragmentProgram>? _program;

  static Future<ui.FragmentProgram> loadProgram() =>
      _program ??= ui.FragmentProgram.fromAsset('shaders/clear_glass.frag');

  static bool enabledOf(BuildContext context) =>
      Theme.of(context).extension<LiquidGlassTheme>()?.enabled == true &&
      !(MediaQuery.maybeOf(context)?.highContrast ?? false);

  static Duration motionDuration(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations == true
      ? Duration.zero
      : const Duration(milliseconds: 220);

  static BoxDecoration selectionDecoration(
    BuildContext context, {
    double selected = 1,
    double radius = 20,
  }) {
    final colors = Theme.of(context).colorScheme;
    return BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.white.withValues(alpha: .04 * selected),
          colors.primary.withValues(alpha: .055 * selected),
        ],
      ),
      border: Border.all(color: Colors.white.withValues(alpha: .30 * selected)),
    );
  }

  @override
  State<LiquidGlass> createState() => _LiquidGlassState();
}

class _LiquidGlassState extends State<LiquidGlass> {
  ui.FragmentShader? _shader;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadShader();
  }

  @override
  void didUpdateWidget(LiquidGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    _loadShader();
  }

  void _loadShader() {
    if (_loading ||
        _shader != null ||
        !widget.refract ||
        !LiquidGlass.enabledOf(context) ||
        !ui.ImageFilter.isShaderFilterSupported) {
      return;
    }
    _loading = true;
    LiquidGlass.loadProgram()
        .then((program) {
          if (mounted) setState(() => _shader = program.fragmentShader());
        })
        .catchError((Object error) {
          debugPrint('Clear glass shader: $error');
        })
        .whenComplete(() => _loading = false);
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    if (!LiquidGlass.enabledOf(context)) {
      return Material(
        color: colors.surface,
        borderRadius: widget.borderRadius,
        child: Padding(padding: widget.padding, child: widget.child),
      );
    }
    final inkShadows = widget.refract
        ? [
            for (final offset in const [
              Offset(-.7, 0),
              Offset(.7, 0),
              Offset(0, -.7),
              Offset(0, .7),
            ])
              Shadow(
                color: colors.surface.withValues(alpha: .95),
                offset: offset,
                blurRadius: .6,
              ),
          ]
        : const <Shadow>[];
    Widget surface = Material(
      type: MaterialType.transparency,
      child: DefaultTextStyle.merge(
        style: TextStyle(shadows: inkShadows),
        child: IconTheme.merge(
          data: IconThemeData(shadows: inkShadows),
          child: Padding(padding: widget.padding, child: widget.child),
        ),
      ),
    );
    if ((_shader == null || !widget.refract) && widget.tint.a > 0) {
      surface = ColoredBox(color: widget.tint, child: surface);
    }
    if (_shader != null && widget.refract) {
      surface = BackdropFilter(
        filterConfig: _GlassRefractionFilter(
          _shader!,
          MediaQuery.devicePixelRatioOf(context),
          () {
            final box = context.findRenderObject()! as RenderBox;
            return _GlassGeometry.fromBox(box, widget.borderRadius);
          },
          bevelWidth: widget.bevelWidth,
          refraction: widget.refraction,
          lightIntensity: widget.lightIntensity,
          tint: widget.tint,
        ),
        child: surface,
      );
    }
    return CustomPaint(
      painter: widget.shadow
          ? _GlassCastShadow(widget.borderRadius, widget.lightIntensity)
          : null,
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: CustomPaint(
          foregroundPainter: _GlassRimPainter(
            widget.borderRadius,
            widget.lightIntensity,
          ),
          child: surface,
        ),
      ),
    );
  }
}

@immutable
class _GlassRefractionFilter implements ImageFilterConfig {
  const _GlassRefractionFilter(
    this.shader,
    this.pixelRatio,
    this.geometry, {
    required this.bevelWidth,
    required this.refraction,
    required this.lightIntensity,
    required this.tint,
  });
  final ui.FragmentShader shader;
  final double pixelRatio;
  final _GlassGeometry Function() geometry;
  final double bevelWidth;
  final double refraction;
  final double lightIntensity;
  final Color tint;

  @override
  ui.ImageFilter resolve(ImageFilterContext context) {
    final shape = geometry();
    final bounds = shape.bounds;
    final radius = shape.radius;
    final scale = shape.scale;
    shader
      ..setFloat(2, bounds.width)
      ..setFloat(3, bounds.height)
      ..setFloat(4, bounds.left)
      ..setFloat(5, bounds.top)
      ..setFloat(6, radius.topLeft.x)
      ..setFloat(7, radius.topRight.x)
      ..setFloat(8, radius.bottomRight.x)
      ..setFloat(9, radius.bottomLeft.x)
      ..setFloat(10, bevelWidth * scale)
      ..setFloat(11, refraction * scale)
      ..setFloat(12, pixelRatio)
      ..setFloat(13, tint.r)
      ..setFloat(14, tint.g)
      ..setFloat(15, tint.b)
      ..setFloat(16, tint.a)
      ..setFloat(17, lightIntensity);
    return ui.ImageFilter.shader(shader);
  }

  @override
  ui.ImageFilter? get filter => null;
  @override
  String get debugShortDescription => 'clearGlassRefraction';
}

class _GlassGeometry {
  const _GlassGeometry(this.bounds, this.radius, this.scale);
  final Rect bounds;
  final BorderRadius radius;
  final double scale;

  factory _GlassGeometry.fromBox(RenderBox box, BorderRadius radius) {
    final rect = Offset.zero & box.size;
    final bounds = MatrixUtils.transformRect(box.getTransformTo(null), rect);
    final scale =
        (box.localToGlobal(rect.topRight) - box.localToGlobal(rect.topLeft))
            .distance /
        box.size.width;
    final corners = <int, Radius>{};
    // Quarter turns change the global corner order as well as width/height.
    for (final corner in [
      (rect.topLeft, radius.topLeft),
      (rect.topRight, radius.topRight),
      (rect.bottomRight, radius.bottomRight),
      (rect.bottomLeft, radius.bottomLeft),
    ]) {
      final point = box.localToGlobal(corner.$1);
      final index =
          (point.dx > bounds.center.dx ? 1 : 0) +
          (point.dy > bounds.center.dy ? 2 : 0);
      corners[index] = corner.$2 * scale;
    }
    return _GlassGeometry(
      bounds,
      BorderRadius.only(
        topLeft: corners[0]!,
        topRight: corners[1]!,
        bottomLeft: corners[2]!,
        bottomRight: corners[3]!,
      ),
      scale,
    );
  }
}

class _GlassCastShadow extends CustomPainter {
  const _GlassCastShadow(this.radius, this.intensity);
  final BorderRadius radius;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final shape = radius.toRRect(Offset.zero & size);
    // A filled box shadow would darken the transparent centre as well.
    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect((Offset.zero & size).inflate(48))
        ..addRRect(shape),
    );
    canvas.drawRRect(
      shape.shift(Offset(0, 3 * intensity)),
      Paint()
        ..color = Colors.black.withValues(alpha: (.14 * intensity).clamp(0, .4))
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 * intensity),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_GlassCastShadow old) =>
      old.radius != radius || old.intensity != intensity;
}

class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter(this.radius, this.intensity);
  final BorderRadius radius;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final rect = (Offset.zero & size).deflate(.65);
    canvas.drawRRect(
      radius.toRRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xCFFFFFFF), Color(0x10FFFFFF), Color(0x65FFFFFF)],
          stops: [0, .48, 1],
        ).createShader(rect),
    );
    if (intensity > 1) {
      // A second light/dark band describes the curved inner wall. Keep the
      // centre untouched; the backdrop shader supplies the actual distortion.
      final inner = rect.deflate(2);
      canvas.drawRRect(
        radius.toRRect(inner).deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5)
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white.withValues(alpha: .38),
              Colors.white.withValues(alpha: 0),
              Colors.black.withValues(alpha: .13),
              Colors.white.withValues(alpha: .35),
            ],
            stops: const [0, .38, .7, 1],
          ).createShader(inner),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) =>
      old.radius != radius || old.intensity != intensity;
}

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry margin;
  final double radius;

  @override
  Widget build(BuildContext context) => Padding(
    padding: margin,
    child: LiquidGlass.enabledOf(context)
        ? LiquidGlass(
            borderRadius: BorderRadius.circular(radius),
            refract: false,
            shadow: false,
            child: child,
          )
        : Container(
            decoration: BoxDecoration(
              border: Border.all(
                color: Theme.of(context).colorScheme.outlineVariant,
                width: .6,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: child,
          ),
  );
}

class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!LiquidGlass.enabledOf(context)) return child;
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.surface),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-.9, -.8),
            radius: 1.6,
            colors: [
              colors.primary.withValues(alpha: .16),
              colors.primary.withValues(alpha: 0),
            ],
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(1, .7),
              radius: 1.25,
              colors: [
                colors.tertiary.withValues(alpha: .10),
                colors.tertiary.withValues(alpha: 0),
              ],
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
