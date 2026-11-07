import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Відповіді у форматі справжніх API (Frankfurter і НБУ, 26.10.2026).
const ecbBody = '{"amount":1.0,"base":"EUR","date":"2026-10-23","rates":{"USD":1.1193}}';
final nbuBody = jsonEncode([
  {'r030': 978, 'txt': 'Євро', 'rate': 50.5766, 'cc': 'EUR', 'exchangedate': '26.10.2026'},
  {'r030': 840, 'txt': 'Долар США', 'rate': 45.2021, 'cc': 'USD', 'exchangedate': '26.10.2026'},
]);

/// Фейковий інтернет: можна вимкнути кожне джерело окремо.
MockClient fakeNet({bool ecb = true, bool nbu = true, List<String>? log}) {
  return MockClient((req) async {
    log?.add(req.url.host);
    if (req.url.host == 'api.frankfurter.dev') {
      return ecb ? http.Response(ecbBody, 200) : http.Response('down', 503);
    }
    if (req.url.host == 'bank.gov.ua') {
      return nbu
          ? http.Response.bytes(utf8.encode(nbuBody), 200)
          : throw http.ClientException('no network');
    }
    return http.Response('?', 404);
  });
}
