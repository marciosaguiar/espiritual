import 'dart:ui';
import 'package:flutter/material.dart';

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
    this.blur = 18,
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
                        Colors.white.withOpacity(0.12),
                        Colors.white.withOpacity(0.04),
                      ]
                    : [
                        Colors.white.withOpacity(0.65),
                        Colors.white.withOpacity(0.35),
                      ],
              ),
              border: Border.all(
                color: isDark
                    ? Colors.white.withOpacity(0.14)
                    : Colors.white.withOpacity(0.70),
                width: 1,
              ),
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
