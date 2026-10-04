import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract class HapticFeedbackService {
  bool get isSupported;
  Future<void> lightImpact();
  Future<void> mediumImpact();
  Future<void> vibrate();
}

class MobileHapticService implements HapticFeedbackService {
  const MobileHapticService();

  @override
  bool get isSupported => true;

  @override
  Future<void> lightImpact() => HapticFeedback.lightImpact();

  @override
  Future<void> mediumImpact() => HapticFeedback.mediumImpact();

  @override
  Future<void> vibrate() => HapticFeedback.vibrate();
}

class WebHapticService implements HapticFeedbackService {
  const WebHapticService();

  @override
  bool get isSupported => false;

  @override
  Future<void> lightImpact() async {}

  @override
  Future<void> mediumImpact() async {}

  @override
  Future<void> vibrate() async {}
}

final hapticServiceProvider = Provider<HapticFeedbackService>((ref) {
  if (kIsWeb) {
    return const WebHapticService();
  }
  return const MobileHapticService();
});
