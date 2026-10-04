import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'report_downloader_stub.dart'
    if (dart.library.html) 'report_downloader_web.dart';

class ReportFileService {
  static const MethodChannel _channel =
      MethodChannel('com.workhours.tracker/widget_sync');

  static bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<String?> saveAndOpenReport({
    required Uint8List bytes,
    required String filename,
  }) async {
    if (!_isAndroid) {
      if (kIsWeb) {
        triggerBrowserDownload(bytes, filename);
        return filename;
      }
      return null;
    }

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
    if (!_isAndroid) {
      return false;
    }

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
