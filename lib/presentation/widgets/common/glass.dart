import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// A reusable frosted-glass ("Liquid Glass") surface: a real backdrop blur
/// clipped to rounded corners, with a translucent gradient fill, a hairline
/// highlight border and a soft drop shadow.
///
/// Use sparingly over scrollable / colourful content — each instance adds a
/// [BackdropFilter], which is the expensive part. For dense lists prefer a
/// faux-glass (translucent container without blur).
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double blur;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final List<BoxShadow>? shadow;

  const GlassContainer({
    super.key,
    required this.child,
    this.blur = 24,
    this.radius = 24,
    this.padding,
    this.margin,
    this.shadow,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderRadius = BorderRadius.circular(radius);

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow ??
            [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.35 : 0.12),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withOpacity(0.18),
                        Colors.white.withOpacity(0.06),
                      ]
                    : [
                        Colors.white.withOpacity(0.74),
                        Colors.white.withOpacity(0.46),
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.22)
                    : Colors.white.withOpacity(0.85),
                width: 1.2,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Faux-glass card: a translucent surface (no backdrop blur) that reads as
/// frosted glass over the app's gradient backdrop. Cheap enough for lists.
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double radius;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.radius = 16,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withOpacity(0.06)
            : Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.10)
              : Colors.white.withOpacity(0.65),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

/// The app-wide frosted backdrop: a soft brand gradient with a few blurred
/// colour "blobs" so translucent glass surfaces have something to refract.
/// Wrap the whole app with this (via MaterialApp.builder).
class GlassBackdrop extends StatelessWidget {
  final Widget child;
  const GlassBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: isDark
            ? AppColors.glassBackgroundDark
            : AppColors.glassBackgroundLight,
      ),
      child: Stack(
        children: [
          Positioned(
            top: -100,
            left: -80,
            child: _blob(AppColors.blue.withOpacity(isDark ? 0.30 : 0.24), 320),
          ),
          Positioned(
            bottom: -120,
            right: -90,
            child: _blob(AppColors.red.withOpacity(isDark ? 0.26 : 0.20), 340),
          ),
          Positioned(
            top: 220,
            right: -110,
            child: _blob(AppColors.yellow.withOpacity(isDark ? 0.18 : 0.18), 260),
          ),
          Positioned(
            bottom: 150,
            left: -100,
            child: _blob(AppColors.blue.withOpacity(isDark ? 0.18 : 0.14), 260),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }

  Widget _blob(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withOpacity(0)]),
        ),
      ),
    );
  }
}
