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
      duration: const Duration(milliseconds: 2800),
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
    final activeColor = const Color(0xFF10B981); // Emerald
    final inactiveColor = const Color(0xFF64748B); // Slate

    return AnimatedBuilder(
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
                              blurRadius: 8,
                              spreadRadius: 2,
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

    // Glowing orbiting tracer along perimeter
    final path = Path()..addRRect(rrect);
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;

    final metric = metrics.first;
    final totalLength = metric.length;
    final headDistance = progress * totalLength;
    final trailLength = totalLength * 0.35; // 35% trailing glow

    final trailStart = (headDistance - trailLength) % totalLength;

    final trailPath = Path();
    if (trailStart < headDistance) {
      trailPath.addPath(metric.extractPath(trailStart, headDistance), Offset.zero);
    } else {
      trailPath.addPath(metric.extractPath(trailStart, totalLength), Offset.zero);
      trailPath.addPath(metric.extractPath(0, headDistance), Offset.zero);
    }

    final trailPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: 0,
        endAngle: math.pi * 2,
        transform: GradientRotation(progress * math.pi * 2),
        colors: [
          activeColor.withValues(alpha: 0.0),
          activeColor.withValues(alpha: 0.8),
          Colors.white,
        ],
        stops: const [0.0, 0.85, 1.0],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    canvas.drawPath(trailPath, trailPaint);

    // Draw bright orbiting beacon head
    final tangent = metric.getTangentForOffset(headDistance);
    if (tangent != null) {
      final glowPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.7)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
      canvas.drawCircle(tangent.position, 4.0, glowPaint);

      final headPaint = Paint()..color = Colors.white;
      canvas.drawCircle(tangent.position, 2.5, headPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.isActive != isActive;
  }
}
