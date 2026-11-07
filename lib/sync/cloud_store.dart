import 'dart:convert';

import 'package:http/http.dart' as http;

/// Сховище файлів у хмарі. Реалізація для Google Drive — [DriveAppDataStore];
/// у тестах підміняється сховищем у пам'яті.
abstract class CloudStore {
  /// Вміст файлу або null, якщо файлу ще немає.
  Future<String?> read(String name);

  /// Створює або перезаписує файл.
  Future<void> write(String name, String content);
}

class CloudException implements Exception {
  const CloudException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isAuth => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// Видає токен доступу. [invalidToken] — токен, який Drive щойно відхилив;
/// його треба відкинути й отримати новий.
typedef TokenProvider = Future<String?> Function({String? invalidToken});

/// Файли в прихованій папці додатку на Google Drive (appDataFolder).
/// Додаток бачить лише цю папку, а не весь диск користувача.
class DriveAppDataStore implements CloudStore {
  DriveAppDataStore(this._token, {http.Client? client}) : _client = client ?? http.Client();

  final TokenProvider _token;
  final http.Client _client;
  final _ids = <String, String>{}; // ім'я файлу → id на Drive
  static const _timeout = Duration(seconds: 30);

  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  @override
  Future<String?> read(String name) async {
    final id = await _findId(name);
    if (id == null) return null;
    final res = await _send((h) => _client.get(Uri.parse('$_api/$id?alt=media'), headers: h));
    if (res.statusCode == 404) {
      _ids.remove(name);
      return null;
    }
    _check(res, 'завантажити $name');
    return utf8.decode(res.bodyBytes);
  }

  @override
  Future<void> write(String name, String content) async {
    final id = await _findId(name);
    if (id != null) {
      final res = await _send((h) => _client.patch(
            Uri.parse('$_upload/$id?uploadType=media'),
            headers: {...h, 'Content-Type': 'application/json; charset=UTF-8'},
            body: utf8.encode(content),
          ));
      if (res.statusCode != 404) {
        _check(res, 'зберегти $name');
        return;
      }
      _ids.remove(name); // файл видалили на Drive — створимо заново
    }

    const boundary = 'mymanager_boundary_7f3a';
    final meta = jsonEncode({'name': name, 'parents': ['appDataFolder']});
    final body = '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n$meta\r\n'
        '--$boundary\r\n'
        'Content-Type: application/json; charset=UTF-8\r\n\r\n$content\r\n'
        '--$boundary--';
    final res = await _send((h) => _client.post(
          Uri.parse('$_upload?uploadType=multipart&fields=id'),
          headers: {...h, 'Content-Type': 'multipart/related; boundary=$boundary'},
          body: utf8.encode(body),
        ));
    _check(res, 'створити $name');
    _ids[name] = (jsonDecode(res.body) as Map)['id'] as String;
  }

  Future<String?> _findId(String name) async {
    final cached = _ids[name];
    if (cached != null) return cached;
    final uri = Uri.parse(_api).replace(queryParameters: {
      'spaces': 'appDataFolder',
      'q': "name = '$name' and trashed = false",
      'fields': 'files(id,name,modifiedTime)',
      'orderBy': 'modifiedTime desc',
      'pageSize': '10',
    });
    final res = await _send((h) => _client.get(uri, headers: h));
    _check(res, 'знайти $name');
    final files = (jsonDecode(res.body) as Map)['files'] as List;
    if (files.isEmpty) return null;
    return _ids[name] = (files.first as Map)['id'] as String;
  }

  /// Надсилає запит з токеном; якщо Drive відповів 401 — оновлює токен і пробує ще раз.
  Future<http.Response> _send(Future<http.Response> Function(Map<String, String>) request) async {
    var token = await _token();
    if (token == null) throw const CloudException('Потрібно увійти в Google', statusCode: 401);
    var res = await request({'Authorization': 'Bearer $token'}).timeout(_timeout);
    if (res.statusCode == 401) {
      token = await _token(invalidToken: token);
      if (token == null) throw const CloudException('Потрібно увійти в Google', statusCode: 401);
      res = await request({'Authorization': 'Bearer $token'}).timeout(_timeout);
    }
    return res;
  }

  static void _check(http.Response res, String action) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    final hint = switch (res.statusCode) {
      401 => 'потрібно увійти в Google ще раз',
      403 => 'немає доступу (перевір, що Drive API увімкнено)',
      429 || 500 || 502 || 503 => 'Google Drive тимчасово недоступний',
      _ => 'помилка ${res.statusCode}',
    };
    throw CloudException('Не вдалося $action: $hint', statusCode: res.statusCode);
  }
}
