import 'dart:convert';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import 'cloud_store.dart';

/// Доступ лише до прихованої папки додатку на Drive.
const driveAppDataScope = 'https://www.googleapis.com/auth/drive.appdata';

/// Email акаунта за токеном доступу (потрібен дозвіл `email`; браузер, етап 23).
Future<String> fetchGoogleEmail(http.Client client, String accessToken) async {
  final res = await client.get(
    Uri.parse('https://www.googleapis.com/oauth2/v3/userinfo'),
    headers: {'Authorization': 'Bearer $accessToken'},
  );
  if (res.statusCode != 200) {
    throw CloudException(
      'Google не дав email акаунта (код ${res.statusCode})',
      statusCode: res.statusCode,
    );
  }
  final email = (jsonDecode(res.body) as Map<String, dynamic>)['email'];
  if (email is! String || email.isEmpty) {
    throw const CloudException('Google не дав email акаунта');
  }
  return email;
}

/// Вхід і токени. Абстракція потрібна, щоб у тестах не викликати справжній Google.
abstract class SyncAuth {
  bool get isConfigured;

  /// Інтерактивний вхід. Повертає email акаунта.
  Future<String> signIn();

  Future<void> signOut();

  /// Токен доступу без показу вікон (null — потрібен повторний вхід).
  Future<String?> accessToken({String? invalidToken});

  /// Показує вікно Google для повторного підтвердження доступу до Drive
  /// (у режимі Testing Google просить це приблизно раз на 7 днів).
  Future<void> authorizeInteractive();
}

/// Телефон: вхід через Google на Android.
class GoogleSyncAuth implements SyncAuth {
  final GoogleSignIn _gsi = GoogleSignIn.instance;
  Future<void>? _init;

  @override
  bool get isConfigured => googleWebClientId.isNotEmpty;

  Future<void> _ensureInit() => _init ??= _gsi.initialize(serverClientId: googleWebClientId);

  @override
  Future<String> signIn() async {
    await _ensureInit();
    final account = await _gsi.authenticate(scopeHint: const [driveAppDataScope]);
    // Окремо просимо доступ до Drive — Android покаже екран згоди один раз.
    await account.authorizationClient.authorizeScopes(const [driveAppDataScope]);
    return account.email;
  }

  @override
  Future<void> signOut() async {
    await _ensureInit();
    await _gsi.signOut();
  }

  @override
  Future<void> authorizeInteractive() async {
    await _ensureInit();
    await _gsi.authorizationClient.authorizeScopes(const [driveAppDataScope]);
  }

  @override
  Future<String?> accessToken({String? invalidToken}) async {
    await _ensureInit();
    final client = _gsi.authorizationClient;
    if (invalidToken != null) {
      await client.clearAuthorizationToken(accessToken: invalidToken);
    }
    final authz = await client.authorizationForScopes(const [driveAppDataScope]);
    return authz?.accessToken;
  }
}
