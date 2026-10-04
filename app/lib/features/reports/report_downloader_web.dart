// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

void triggerBrowserDownload(Uint8List bytes, String filename) {
  final blob = html.Blob(
    [bytes],
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
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
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    final url = html.Url.createObjectUrlFromBlob(blob);
    final win = html.window.open(url, '_blank');
    if (win == null) {
      // Fallback if popup blocker intercepted window.open
      html.AnchorElement(href: url)
        ..setAttribute('download', filename)
        ..click();
    }
    return true;
  } catch (_) {
    return false;
  }
}
