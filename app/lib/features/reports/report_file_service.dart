import 'package:flutter/services.dart';

class ReportFileService {
  static const MethodChannel _channel =
      MethodChannel('com.workhours.tracker/widget_sync');

  static Future<String?> saveAndOpenReport({
    required Uint8List bytes,
    required String filename,
  }) async {
    try {
      final path = await _channel.invokeMethod<String>('saveAndOpenReport', {
        'bytes': bytes,
        'filename': filename,
      });
      return path;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> openReportFile(String filePath) async {
    try {
      final success = await _channel.invokeMethod<bool>('openReportFile', {
        'filePath': filePath,
      });
      return success ?? false;
    } catch (_) {
      return false;
    }
  }
}
