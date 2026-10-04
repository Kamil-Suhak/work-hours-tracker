import 'package:flutter/foundation.dart';
import '../../services/platform/platform_services.dart';

/// Backward-compatibility shim that delegates to [ReportFileService].
/// Prefer injecting [reportFileServiceProvider] via Riverpod.
class ReportFileService {
  static const AndroidReportFileService _android = AndroidReportFileService();
  static const WebReportFileService _web = WebReportFileService();

  static Future<String?> saveAndOpenReport({
    required Uint8List bytes,
    required String filename,
  }) {
    if (kIsWeb) {
      return _web.saveAndOpenReport(bytes: bytes, filename: filename);
    }
    return _android.saveAndOpenReport(bytes: bytes, filename: filename);
  }

  static Future<bool> openReportFile(String filePath) =>
      _android.openReportFile(filePath);
}
