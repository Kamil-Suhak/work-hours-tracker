import 'dart:math' as math;
import 'package:flutter/material.dart';

class CyberOrbitBadge extends StatefulWidget {
  final bool isClockedIn;
  final bool enableAnimation;

  const CyberOrbitBadge({
    super.key,
    required this.isClockedIn,
    this.enableAnimation = true,
  });

  @override
  State<CyberOrbitBadge> createState() => _CyberOrbitBadgeState();
}

class _CyberOrbitBadgeState extends State<CyberOrbitBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    if (widget.isClockedIn && widget.enableAnimation) {
      _controller.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant CyberOrbitBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isClockedIn != oldWidget.isClockedIn ||
        widget.enableAnimation != oldWidget.enableAnimation) {
      if (widget.isClockedIn && widget.enableAnimation) {
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
              isActive: widget.isClockedIn,
              activeColor: activeColor,
              inactiveColor: inactiveColor,
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.isClockedIn ? activeColor : inactiveColor,
                      boxShadow: widget.isClockedIn
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
                    widget.isClockedIn ? 'CLOCKED IN' : 'CLOCKED OUT',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      letterSpacing: 1.6,
                      color: widget.isClockedIn ? activeColor : inactiveColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrbitRingPainter extends CustomPainter {
  final double progress;
  final bool isActive;
  final Color activeColor;
  final Color inactiveColor;

  _OrbitRingPainter({
    required this.progress,
    required this.isActive,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(size.height / 2),
    );

    // Background fill
    final bgPaint = Paint()
      ..color = isActive
          ? activeColor.withValues(alpha: 0.08)
          : inactiveColor.withValues(alpha: 0.06)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(rrect, bgPaint);

    // Base boundary track
    final baseTrackPaint = Paint()
      ..color = isActive
          ? activeColor.withValues(alpha: 0.25)
          : inactiveColor.withValues(alpha: 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawRRect(rrect, baseTrackPaint);

    if (!isActive) return;

    // High performance mathematical trajectory calculation: 0 path allocations
    final w = size.width;
    final h = size.height;
    final r = h / 2;
    final straightLen = w - 2 * r;
    final arcLen = math.pi * r;
    final totalLen = 2 * straightLen + 2 * arcLen;

    Offset getPointOnPerimeter(double dist) {
      dist = dist % totalLen;
      if (dist < 0) dist += totalLen;

      // Top straight: left to right (r -> w - r)
      if (dist <= straightLen) {
        return Offset(r + dist, 0);
      }
      dist -= straightLen;

      // Right semicircle: top to bottom (-pi/2 -> pi/2)
      if (dist <= arcLen) {
        final angle = -math.pi / 2 + (dist / arcLen) * math.pi;
        return Offset(w - r + math.cos(angle) * r, r + math.sin(angle) * r);
      }
      dist -= arcLen;

      // Bottom straight: right to left (w - r -> r)
      if (dist <= straightLen) {
        return Offset(w - r - dist, h);
      }
      dist -= straightLen;

      // Left semicircle: bottom to top (pi/2 -> 3*pi/2)
      final angle = math.pi / 2 + (dist / arcLen) * math.pi;
      return Offset(r + math.cos(angle) * r, r + math.sin(angle) * r);
    }

    final currentPos = getPointOnPerimeter(progress * totalLen);

    // Glowing trailing tail (concentric fading beads along perimeter)
    const trailSegments = 7;
    final trailDistStep = (totalLen * 0.22) / trailSegments;
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
    return oldDelegate.progress != progress || oldDelegate.isActive != isActive;
  }
}
