import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_manager/sync/cloud_store.dart';
import 'package:my_manager/sync/worker_auth.dart';

/// Етап 23: браузер отримує доступ до Drive через наш Cloudflare Worker.
void main() {
  late List<http.Request> calls;
  late http.Response Function(http.Request) worker;
  late DateTime now;

  WorkerSyncAuth auth() => WorkerSyncAuth(
    base: Uri.parse('https://mm.example.workers.dev/'),
    clock: () => now,
    requestCode: (scopes) async {
      expect(scopes, workerScopes);
      return 'code-1';
    },
    client: MockClient((req) async {
      calls.add(req);
      if (req.url.host == 'www.googleapis.com') {
        return http.Response('{"email":"me@example.com"}', 200);
      }
      return worker(req);
    }),
  );

  http.Response token(String t, [int seconds = 3599]) => http.Response(
    jsonEncode({'access_token': t, 'expires_in': seconds}),
    200,
  );

  List<String> paths() => calls.map((r) => r.url.path).toList();

  setUp(() {
    calls = [];
    now = DateTime.utc(2026, 11, 3, 12);
    worker = (_) => token('at-1');
  });

  test('вхід: код → Worker → email; токен потім береться з пам\'яті', () async {
    final a = auth();
    expect(await a.signIn(), 'me@example.com');
    expect(paths(), ['/api/auth/exchange', '/oauth2/v3/userinfo']);
    expect(jsonDecode(calls.first.body), {'code': 'code-1'});
    expect(calls[1].headers['Authorization'], 'Bearer at-1');

    expect(await a.accessToken(), 'at-1');
    expect(calls, hasLength(2)); // без зайвих запитів
  });

  test('через годину Worker сам дає свіжий доступ — без вікон', () async {
    final a = auth();
    await a.signIn();
    now = now.add(const Duration(minutes: 59));
    worker = (_) => token('at-2');
    expect(await a.accessToken(), 'at-2');
    expect(paths().last, '/api/auth/token');
  });

  test('після перезавантаження сторінки — одразу з Worker', () async {
    final a = auth(); // нічого в пам'яті
    expect(await a.accessToken(), 'at-1');
    expect(paths(), ['/api/auth/token']);
  });

  test('Drive відхилив токен — береться новий', () async {
    final a = auth();
    await a.signIn();
    worker = (_) => token('at-2');
    expect(await a.accessToken(invalidToken: 'at-1'), 'at-2');
  });

  test('ключ більше не діє — null (тоді потрібен клік)', () async {
    worker = (_) => http.Response('{"error":"session_expired"}', 401);
    expect(await auth().accessToken(), isNull);
  });

  test('Worker недоступний — помилка, а не «вийти»', () async {
    worker = (_) => http.Response('{"error":"google_unavailable"}', 502);
    await expectLater(auth().accessToken(), throwsA(isA<CloudException>()));
  });

  test('Google не видав ключ — підказка, що робити', () async {
    worker = (_) => http.Response(
      '{"error":"no_refresh_token","access_token":"x","expires_in":3599}',
      409,
    );
    await expectLater(
      auth().signIn(),
      throwsA(
        isA<CloudException>().having(
          (e) => e.message,
          'message',
          contains('myaccount.google.com/permissions'),
        ),
      ),
    );
  });

  test('повторне підтвердження — той самий вхід', () async {
    final a = auth();
    await a.authorizeInteractive();
    expect(paths().first, '/api/auth/exchange');
    expect(await a.accessToken(), 'at-1');
  });

  test('вихід: Worker відкликає ключ, пам\'ять очищено', () async {
    final a = auth();
    await a.signIn();
    worker = (req) => req.url.path == '/api/auth/signout'
        ? http.Response('{"ok":true}', 200)
        : http.Response('{"error":"no_session"}', 401);
    await a.signOut();
    expect(paths().last, '/api/auth/signout');
    expect(await a.accessToken(), isNull);
  });
}
