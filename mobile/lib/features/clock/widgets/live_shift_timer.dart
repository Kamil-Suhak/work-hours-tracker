import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class LiveShiftTimer extends StatefulWidget {
  final DateTime activeSince;
  final bool enablePeriodicTimer;

  const LiveShiftTimer({
    super.key,
    required this.activeSince,
    this.enablePeriodicTimer = true,
  });

  @override
  State<LiveShiftTimer> createState() => _LiveShiftTimerState();
}

class _LiveShiftTimerState extends State<LiveShiftTimer> {
  Timer? _timer;
  late Duration _elapsed;

  @override
  void initState() {
    super.initState();
    _updateElapsed();
    if (widget.enablePeriodicTimer) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(_updateElapsed);
        }
      });
    }
  }

  void _updateElapsed() {
    final now = DateTime.now();
    final difference = now.difference(widget.activeSince.toLocal());
    _elapsed = difference.isNegative ? Duration.zero : difference;
  }

  @override
  void didUpdateWidget(covariant LiveShiftTimer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSince != oldWidget.activeSince) {
      _updateElapsed();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours.toString().padLeft(2, '0');
    final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final timerString = _formatDuration(_elapsed);

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.timer_outlined,
                size: 16,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
              Text(
                'LIVE SHIFT TIMER',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            timerString,
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
              letterSpacing: 1.5,
              color: Color(0xFF065F46),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Active since ${DateFormat('HH:mm').format(widget.activeSince.toLocal())}',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}
