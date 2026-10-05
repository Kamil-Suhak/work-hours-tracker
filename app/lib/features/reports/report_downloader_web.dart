// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';
import '../../config/app_config.dart';

void triggerBrowserDownload(Uint8List bytes, String filename) {
  final blob = html.Blob(
    [bytes],
    AppConfig.reportMimeType,
  );
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

bool openReportInBrowser(Uint8List bytes, String filename) {
  try {
    final blob = html.Blob(
      [bytes],
      AppConfig.reportMimeType,
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    html.window.open(url, '_blank');
    return true;
  } catch (_) {
    return false;
  }
}
