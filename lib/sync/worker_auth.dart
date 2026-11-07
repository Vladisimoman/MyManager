import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'cloud_store.dart';
import 'google_auth.dart';

/// Браузер (етап 23): вхід і токени через наш Cloudflare Worker.
///
/// Вікно Google дає одноразовий код, Worker обмінює його на ключ поновлення
/// (тримає в HttpOnly cookie) і далі сам видає свіжий доступ — без вікон.
/// Код Worker — `cloudflare/src/worker.js`.

/// Дозволи: прихована папка Drive і email акаунта.
const workerScopes = [driveAppDataScope, 'openid', 'email'];

/// Одноразовий код Google для сервера (у тестах підміняється).
typedef ServerCodeRequest = Future<String> Function(List<String> scopes);

class WorkerSyncAuth implements SyncAuth {
  WorkerSyncAuth({
    http.Client? client,
    ServerCodeRequest? requestCode,
    Uri? base,
    DateTime Function()? clock,
  }) : _client = client ?? http.Client(),
       _requestCode = requestCode ?? _googleServerCode,
       _base = base ?? Uri.base,
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final ServerCodeRequest _requestCode;
  final Uri _base;
  final DateTime Function() _clock;

  /// Запас до кінця дії токена, щоб не віддати майже прострочений.
  static const _margin = Duration(minutes: 1);

  String? _token;
  DateTime? _expires;

  @override
  bool get isConfigured => googleWebClientId.isNotEmpty;

  @override
  Future<String> signIn() async {
    final code = await _requestCode(workerScopes);
    final res = await _post('/api/auth/exchange', {'code': code});
    final data = _decode(res);
    if (res.statusCode == 409 && data['error'] == 'no_refresh_token') {
      throw const CloudException(
        'Google не видав ключ для автоматичної синхронізації. '
        'Відклич доступ MyManager на myaccount.google.com/permissions і увійди ще раз',
      );
    }
    if (res.statusCode != 200) {
      throw CloudException(
        'Сервер входу не відповів як слід (код ${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    final token = _remember(data);
    return fetchGoogleEmail(_client, token);
  }

  @override
  Future<void> authorizeInteractive() async {
    await signIn();
  }

  @override
  Future<String?> accessToken({String? invalidToken}) async {
    if (invalidToken != null && invalidToken == _token) _forget();
    final token = _token;
    final expires = _expires;
    if (token != null &&
        expires != null &&
        _clock().add(_margin).isBefore(expires)) {
      return token;
    }
    final res = await _post('/api/auth/token', const {});
    if (res.statusCode == 401) {
      _forget();
      return null; // потрібен вхід (ключа немає або він більше не діє)
    }
    if (res.statusCode != 200) {
      throw CloudException(
        'Сервер входу не відповів як слід (код ${res.statusCode})',
        statusCode: res.statusCode,
      );
    }
    return _remember(_decode(res));
  }

  @override
  Future<void> signOut() async {
    _forget();
    await _post('/api/auth/signout', const {});
  }

  String _remember(Map<String, dynamic> data) {
    final token = data['access_token'];
    if (token is! String || token.isEmpty) {
      throw const CloudException('Сервер входу не дав токен доступу');
    }
    final seconds = (data['expires_in'] as num?)?.toInt() ?? 3600;
    _token = token;
    _expires = _clock().add(Duration(seconds: seconds));
    return token;
  }

  void _forget() {
    _token = null;
    _expires = null;
  }

  Future<http.Response> _post(String path, Map<String, Object> body) => _client
      .post(
        _base.resolve(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      )
      .timeout(const Duration(seconds: 20));

  static Map<String, dynamic> _decode(http.Response res) {
    try {
      final v = jsonDecode(res.body);
      return v is Map<String, dynamic> ? v : const {};
    } on FormatException {
      return const {};
    }
  }
}

Future<void>? _gsiInit;

Future<String> _googleServerCode(List<String> scopes) async {
  final gsi = GoogleSignIn.instance;
  await (_gsiInit ??= gsi.initialize(clientId: googleWebClientId));
  final r = await gsi.authorizationClient.authorizeServer(scopes);
  if (r == null) {
    throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
  }
  return r.serverAuthCode;
}
