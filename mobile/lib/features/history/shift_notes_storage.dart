import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Local persistence service for shift notes to ensure notes are NEVER lost
/// even if the remote worker has not applied migrations or is offline.
class ShiftNotesStorage {
  static const String _storageKey = 'local_persisted_shift_notes';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  // In-memory cache for fast, synchronous lookups in ShiftRecord
  static final Map<String, String> _cache = {};
  static bool _isLoaded = false;

  /// Loads persisted notes from secure storage into memory.
  static Future<void> loadCache() async {
    if (_isLoaded) return;
    try {
      final jsonStr = await _storage.read(key: _storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
        _cache.clear();
        decoded.forEach((key, value) {
          if (value is String) {
            _cache[key] = value;
          }
        });
      }
    } catch (_) {}
    _isLoaded = true;
  }

  /// Formats a DateTime into a lookup key matching the shift date and time.
  static String formatKey(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$min';
  }

  /// Formats date-only key as fallback.
  static String formatDateKey(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// Records a note for a shift at clockOutTime.
  static Future<void> recordShiftNote(String note, DateTime clockOutTime) async {
    final trimmed = note.trim();
    if (trimmed.isEmpty) return;

    await loadCache();
    final exactKey = formatKey(clockOutTime);
    final dateKey = formatDateKey(clockOutTime);

    _cache[exactKey] = trimmed;
    _cache[dateKey] = trimmed;

    try {
      await _storage.write(key: _storageKey, value: jsonEncode(_cache));
    } catch (_) {}
  }

  /// Synchronously looks up cached note by matching exact minute or within +/- 5 minutes.
  static String? getCachedNote(DateTime time) {
    if (!_isLoaded) return null;

    final exactKey = formatKey(time);
    if (_cache.containsKey(exactKey)) return _cache[exactKey];

    // Check +/- 5 minute window for slight server/device clock drift
    for (int delta = -5; delta <= 5; delta++) {
      final shifted = time.add(Duration(minutes: delta));
      final key = formatKey(shifted);
      if (_cache.containsKey(key)) return _cache[key];
    }

    // Fallback to date key if available
    final dateKey = formatDateKey(time);
    return _cache[dateKey];
  }
}
