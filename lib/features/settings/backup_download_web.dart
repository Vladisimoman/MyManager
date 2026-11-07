import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Браузер (етап 21): файл копії йде в «Завантаження», як звичайне скачування.
Future<void> downloadFile(
  String fileName,
  Uint8List bytes,
  String mimeType,
) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final link = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.append(link);
  link.click();
  link.remove();
  // Даємо браузеру почати завантаження, потім звільняємо посилання.
  await Future<void>.delayed(const Duration(seconds: 1));
  web.URL.revokeObjectURL(url);
}
