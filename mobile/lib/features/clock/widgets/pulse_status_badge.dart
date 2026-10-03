import 'package:flutter/material.dart';

class PulseStatusBadge extends StatefulWidget {
  final bool isClockedIn;
  final bool enablePulseAnimation;

  const PulseStatusBadge({
    super.key,
    required this.isClockedIn,
    this.enablePulseAnimation = true,
  });

  @override
  State<PulseStatusBadge> createState() => _PulseStatusBadgeState();
}

class _PulseStatusBadgeState extends State<PulseStatusBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _glowAnimation = Tween<double>(begin: 0.15, end: 0.5).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    if (widget.isClockedIn && widget.enablePulseAnimation) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant PulseStatusBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isClockedIn != oldWidget.isClockedIn ||
        widget.enablePulseAnimation != oldWidget.enablePulseAnimation) {
      if (widget.isClockedIn && widget.enablePulseAnimation) {
        _controller.repeat(reverse: true);
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
      animation: _glowAnimation,
      builder: (context, child) {
        final glowAlpha = widget.isClockedIn ? _glowAnimation.value : 0.0;

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isClockedIn
                ? activeColor.withValues(alpha: 0.12)
                : inactiveColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: widget.isClockedIn
                  ? activeColor.withValues(alpha: 0.8)
                  : inactiveColor.withValues(alpha: 0.4),
              width: 1.5,
            ),
            boxShadow: widget.isClockedIn
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: glowAlpha),
                      blurRadius: 14 * _glowAnimation.value * 2,
                      spreadRadius: 2 * _glowAnimation.value * 2,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isClockedIn ? activeColor : inactiveColor,
                  boxShadow: widget.isClockedIn
                      ? [
                          BoxShadow(
                            color: activeColor,
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
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 1.4,
                  color: widget.isClockedIn ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
