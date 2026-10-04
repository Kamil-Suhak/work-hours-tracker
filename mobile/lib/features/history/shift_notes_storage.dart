import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Legacy cleanup service: Purges any locally cached shift notes so they
/// do not bleed across shifts in the recents history.
class ShiftNotesStorage {
  static const String _storageKey = 'local_persisted_shift_notes';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  /// Cleans up legacy local notes storage so only the server is authoritative.
  static Future<void> purgeLegacyCache() async {
    try {
      await _storage.delete(key: _storageKey);
    } catch (_) {}
  }
}
