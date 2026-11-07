import 'dart:typed_data';

/// Завантаження файлу браузером. На телефоні не використовується —
/// справжня реалізація в `backup_download_web.dart`.
Future<void> downloadFile(String fileName, Uint8List bytes, String mimeType) =>
    throw UnsupportedError('Завантаження файлу доступне лише в браузері');
