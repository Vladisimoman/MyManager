import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_manager/sync/cloud_store.dart';
import 'package:my_manager/sync/google_auth.dart';

/// Етап 22: у браузері email акаунта береться з профілю Google за токеном.
void main() {
  test('email з профілю Google', () async {
    late http.Request seen;
    final client = MockClient((req) async {
      seen = req;
      return http.Response('{"sub":"1","email":"me@example.com"}', 200);
    });
    expect(await fetchGoogleEmail(client, 'tok'), 'me@example.com');
    expect(seen.headers['Authorization'], 'Bearer tok');
    expect(seen.url.host, 'www.googleapis.com');
  });

  test('токен відхилено — помилка доступу', () async {
    final client = MockClient((_) async => http.Response('{}', 401));
    await expectLater(
      fetchGoogleEmail(client, 'tok'),
      throwsA(isA<CloudException>().having((e) => e.isAuth, 'isAuth', true)),
    );
  });

  test('без email у відповіді — зрозуміла помилка', () async {
    final client = MockClient((_) async => http.Response('{"sub":"1"}', 200));
    await expectLater(
      fetchGoogleEmail(client, 'tok'),
      throwsA(isA<CloudException>()),
    );
  });
}
