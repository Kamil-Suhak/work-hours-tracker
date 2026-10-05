import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_config.dart';
import '../../features/reports/report_downloader_stub.dart'
    if (dart.library.html) '../../features/reports/report_downloader_web.dart';

abstract class ReportFileService {
  Future<String?> saveAndOpenReport({
    required Uint8List bytes,
    required String filename,
  });
  Future<bool> openReportFile(String filePath);
}

class AndroidReportFileService implements ReportFileService {
  static const MethodChannel _channel =
      MethodChannel(AppConfig.widgetSyncChannel);

  const AndroidReportFileService();

  @override
  Future<String?> saveAndOpenReport({
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

  @override
  Future<bool> openReportFile(String filePath) async {
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

class WebReportFileService implements ReportFileService {
  static Uint8List? _lastBytes;
  static String? _lastFilename;

  const WebReportFileService();

  @override
  Future<String?> saveAndOpenReport({
    required Uint8List bytes,
    required String filename,
  }) async {
    _lastBytes = bytes;
    _lastFilename = filename;
    triggerBrowserDownload(bytes, filename);
    return filename;
  }

  @override
  Future<bool> openReportFile(String filePath) async {
    if (_lastBytes != null) {
      return openReportInBrowser(_lastBytes!, _lastFilename ?? filePath);
    }
    return false;
  }
}

class NoOpReportFileService implements ReportFileService {
  const NoOpReportFileService();

  @override
  Future<String?> saveAndOpenReport({
    required Uint8List bytes,
    required String filename,
  }) async => null;

  @override
  Future<bool> openReportFile(String filePath) async => false;
}

final reportFileServiceProvider = Provider<ReportFileService>((ref) {
  if (kIsWeb) {
    return const WebReportFileService();
  }
  if (defaultTargetPlatform == TargetPlatform.android) {
    return const AndroidReportFileService();
  }
  return const NoOpReportFileService();
});
