import 'dart:typed_data';

void triggerBrowserDownload(Uint8List bytes, String filename) {
  // No-op for non-web platforms without native opener
}
