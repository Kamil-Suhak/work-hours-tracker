import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Wraps [child] with an animated orbiting emerald beacon along its rounded
/// rectangular border when [isActive] and [enableAnimation] are true.
class CyberOrbitBorder extends StatefulWidget {
  final bool isActive;
  final bool enableAnimation;
  final double? borderRadius;
  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;
  final Duration duration;
  final Widget child;

  const CyberOrbitBorder({
    super.key,
    required this.isActive,
    this.enableAnimation = true,
    this.borderRadius,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 1.5,
    this.duration = const Duration(milliseconds: 3200),
    required this.child,
  });

  @override
  State<CyberOrbitBorder> createState() => _CyberOrbitBorderState();
}

class _CyberOrbitBorderState extends State<CyberOrbitBorder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    if (widget.isActive && widget.enableAnimation) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CyberOrbitBorder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive != oldWidget.isActive ||
        widget.enableAnimation != oldWidget.enableAnimation) {
      if (widget.isActive && widget.enableAnimation) {
        _controller.repeat();
      } else {
        _controller.stop();
        _controller.reset();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981); // Emerald
    const inactiveColor = Color(0xFF64748B); // Slate

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return CustomPaint(
            painter: _OrbitRingPainter(
              progress: _controller.value,
              isActive: widget.isActive,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
              borderRadius: widget.borderRadius,
              fillColor: widget.fillColor,
              borderColor: widget.borderColor,
              borderWidth: widget.borderWidth,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}

class CyberOrbitBadge extends StatelessWidget {
  final bool isClockedIn;
  final bool enableAnimation;
  final bool showOrbitRing;

  const CyberOrbitBadge({
    super.key,
    required this.isClockedIn,
    this.enableAnimation = true,
    this.showOrbitRing = true,
  });

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF10B981); // Emerald
    const inactiveColor = Color(0xFF64748B); // Slate

    final badgeContent = Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: showOrbitRing
          ? null
          : BoxDecoration(
              color: isClockedIn
                  ? activeColor.withValues(alpha: 0.08)
                  : inactiveColor.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isClockedIn
                    ? activeColor.withValues(alpha: 0.25)
                    : inactiveColor.withValues(alpha: 0.2),
                width: 1.5,
              ),
            ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isClockedIn ? activeColor : inactiveColor,
              boxShadow: isClockedIn
                  ? [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.8),
                        blurRadius: 6,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            isClockedIn ? 'CLOCKED IN' : 'CLOCKED OUT',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              letterSpacing: 1.6,
              color: isClockedIn ? activeColor : inactiveColor,
            ),
          ),
        ],
      ),
    );

    if (!showOrbitRing) return badgeContent;

    return CyberOrbitBorder(
      isActive: isClockedIn,
      enableAnimation: enableAnimation,
      child: badgeContent,
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  final double progress;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;
  final double? borderRadius;
  final Color? fillColor;
  final Color? borderColor;
  final double borderWidth;

  _OrbitRingPainter({
    required this.progress,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
    this.borderRadius,
    this.fillColor,
    this.borderColor,
    this.borderWidth = 1.5,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = (borderRadius ?? (size.height / 2))
        .clamp(0.0, math.min(size.width, size.height) / 2);
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(r),
    );

    // Background fill
    final bgPaint = Paint()
      ..color = fillColor ??
          (isActive
              ? activeColor.withValues(alpha: 0.08)
              : inactiveColor.withValues(alpha: 0.06))
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Base boundary track
    final baseTrackPaint = Paint()
      ..color = borderColor ??
          (isActive
              ? activeColor.withValues(alpha: 0.25)
              : inactiveColor.withValues(alpha: 0.2))
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawRRect(rrect, baseTrackPaint);

    if (!isActive) return;

    // High performance mathematical trajectory calculation: 0 path allocations
    final w = size.width;
    final h = size.height;
    final hStraight = math.max(0.0, w - 2 * r);
    final vStraight = math.max(0.0, h - 2 * r);
    final quarterArc = 0.5 * math.pi * r;
    final totalLen = 2 * hStraight + 2 * vStraight + 4 * quarterArc;
    if (totalLen <= 0) return;

    Offset getPointOnPerimeter(double dist) {
      dist = dist % totalLen;
      if (dist < 0) dist += totalLen;

      // Top straight: left to right
      if (dist <= hStraight) {
        return Offset(r + dist, 0);
      }
      dist -= hStraight;

      // Top-right corner: -pi/2 -> 0
      if (dist <= quarterArc) {
        final angle = -math.pi / 2 + (dist / quarterArc) * (math.pi / 2);
        return Offset(w - r + math.cos(angle) * r, r + math.sin(angle) * r);
      }
      dist -= quarterArc;

      // Right vertical straight: top to bottom
      if (dist <= vStraight) {
        return Offset(w, r + dist);
      }
      dist -= vStraight;

      // Bottom-right corner: 0 -> pi/2
      if (dist <= quarterArc) {
        final angle = (dist / quarterArc) * (math.pi / 2);
        return Offset(w - r + math.cos(angle) * r, h - r + math.sin(angle) * r);
      }
      dist -= quarterArc;

      // Bottom straight: right to left
      if (dist <= hStraight) {
        return Offset(w - r - dist, h);
      }
      dist -= hStraight;

      // Bottom-left corner: pi/2 -> pi
      if (dist <= quarterArc) {
        final angle = math.pi / 2 + (dist / quarterArc) * (math.pi / 2);
        return Offset(r + math.cos(angle) * r, h - r + math.sin(angle) * r);
      }
      dist -= quarterArc;

      // Left vertical straight: bottom to top
      if (dist <= vStraight) {
        return Offset(0, h - r - dist);
      }
      dist -= vStraight;

      // Top-left corner: pi -> 3*pi/2
      final angle = math.pi + (dist / quarterArc) * (math.pi / 2);
      return Offset(r + math.cos(angle) * r, r + math.sin(angle) * r);
    }

    final currentPos = getPointOnPerimeter(progress * totalLen);

    // Glowing trailing tail (concentric fading beads along perimeter)
    const trailSegments = 7;
    final trailDistStep = (totalLen * 0.18) / trailSegments;
    for (int i = 1; i <= trailSegments; i++) {
      final p = getPointOnPerimeter(progress * totalLen - i * trailDistStep);
      final factor = 1.0 - (i / trailSegments);
      final trailDotPaint = Paint()
        ..color = activeColor.withValues(alpha: factor * 0.6)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, 2.2 * factor + 0.8, trailDotPaint);
    }

    // Hardware-accelerated glow beacon head (concentric circles, 0 convolution passes)
    final outerGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(currentPos, 6.5, outerGlowPaint);

    final midGlowPaint = Paint()
      ..color = activeColor.withValues(alpha: 0.8)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(currentPos, 3.8, midGlowPaint);

    final headPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(currentPos, 2.2, headPaint);
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isActive != isActive ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.borderColor != borderColor ||
        oldDelegate.borderWidth != borderWidth;
  }
}
