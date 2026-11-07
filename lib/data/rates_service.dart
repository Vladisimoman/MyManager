import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;

import '../core/money.dart';
import 'database.dart';
import 'rate_history.dart';

/// Результат оновлення курсів.
enum RatesRefreshResult { updated, notNeeded, failed }

/// Завантажує курси валют і зберігає їх у локальну базу.
///
/// Джерела (безкоштовні, без ключа):
/// - Frankfurter (курси ЄЦБ) — основне джерело, база EUR;
/// - НБУ — для валют, яких немає в ЄЦБ (зокрема UAH), і як запасний варіант.
class RatesService {
  RatesService(this._db, {http.Client? client, DateTime Function()? clock})
    : _client = client ?? http.Client(),
      _now = clock ?? DateTime.now;

  final AppDatabase _db;
  final http.Client _client;
  final DateTime Function() _now;

  /// Як часто оновлювати курси автоматично. Банки публікують їх раз на робочий день.
  static const maxAge = Duration(hours: 6);
  static const _timeout = Duration(seconds: 10);

  static final frankfurterUrl = Uri.parse(
    'https://api.frankfurter.dev/v1/latest',
  );
  static final nbuUrl = Uri.parse(
    'https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange?json',
  );

  /// Валюти, які показуються під балансом і в рядку курсів на екрані Finance.
  static const displayCurrencies = ['UAH', 'USD'];

  /// Валюти, для яких потрібен курс: [displayCurrencies] + усі валюти гаманців (крім EUR).
  Future<List<String>> neededCurrencies() async {
    final inWallets = (await _db.watchWalletCurrencies().first).map(
      (c) => c.currency,
    );
    return {
      ...displayCurrencies,
      ...inWallets,
    }.where((c) => c != baseCurrency && isFiat(c)).toList()..sort();
  }

  /// Оновлює курси, якщо вони відсутні або старші за [maxAge].
  Future<RatesRefreshResult> refreshIfStale() async {
    final last = await _db.lastRatesFetch();
    final rates = await _db.watchRates().first;
    final complete = (await neededCurrencies()).every(rates.containsKey);
    if (complete && last != null && _now().toUtc().difference(last) < maxAge) {
      return RatesRefreshResult.notNeeded;
    }
    return refresh();
  }

  /// Примусове оновлення. Якщо мережі немає — у базі лишаються старі курси.
  Future<RatesRefreshResult> refresh() async {
    final fetchedAt = _now().toUtc();
    final found = <String, ExchangeRatesCompanion>{};
    final needed = await neededCurrencies();

    try {
      final ecb = await _fetchEcb(needed);
      for (final e in ecb.entries) {
        found[e.key] = e.value.toCompanion(e.key, 'ECB', fetchedAt);
      }
    } catch (_) {
      // Немає мережі або сервіс недоступний — спробуємо НБУ.
    }

    final missing = needed.where((c) => !found.containsKey(c)).toList();
    if (missing.isNotEmpty) {
      try {
        final nbu = await _fetchNbu(missing);
        for (final e in nbu.entries) {
          found[e.key] = e.value.toCompanion(e.key, 'NBU', fetchedAt);
        }
      } catch (_) {
        // Обидва джерела недоступні.
      }
    }

    if (found.isEmpty) return RatesRefreshResult.failed;
    await _db.saveRates(found.values.toList());
    return needed.every(found.containsKey)
        ? RatesRefreshResult.updated
        : RatesRefreshResult.failed;
  }

  // ---------- Курси на дату запису (етап 10) ----------

  static const ecbHistoryBase = 'https://api.frankfurter.dev/v1/';
  static const nbuDayUrl =
      'https://bank.gov.ua/NBUStatService/v1/statdirectory/exchange';

  /// Скільки днів НБУ запитувати за один раз (кожен день — окремий запит).
  static const maxNbuDaysPerRun = 40;

  /// Дні, яким курс на дату ще не потрібен: поточний курс майже той самий.
  static const recentDays = 3;

  /// Валюта → дні, для яких потрібен курс на дату (записи, перекази, операції з активами).
  Future<Map<String, Set<DateTime>>> neededHistory() async {
    final out = <String, Set<DateTime>>{};
    void add(String? currency, DateTime date) {
      if (currency == null || currency == baseCurrency || !isFiat(currency)) return;
      (out[currency] ??= {}).add(DateTime(date.year, date.month, date.day));
    }

    for (final e in await _db.watchAllEntries().first) {
      if (!e.deleted) add(e.currency, e.date);
    }
    for (final t in await _db.watchTransfers().first) {
      if (t.deleted) continue;
      add(t.fromCurrency, t.date);
      add(t.toCurrency, t.date);
    }
    for (final t in await _db.watchTrades().first) {
      if (!t.deleted) add(t.fiatCurrency, t.date);
    }
    return out;
  }

  /// Довантажує курси на дати записів, яких ще немає в кеші.
  /// true — усе потрібне є (або нічого не потрібно).
  Future<bool> fillHistory() async {
    final now = _now();
    final recent = DateTime(now.year, now.month, now.day - recentDays);
    final needed = await neededHistory();

    Future<Map<String, List<DateTime>>> missing() async {
      final history = RateHistory(await _db.getRateHistory());
      final out = <String, List<DateTime>>{};
      for (final e in needed.entries) {
        final days = e.value
            .where((d) => d.isBefore(recent) && !history.covers(e.key, d))
            .toList()
          ..sort();
        if (days.isNotEmpty) out[e.key] = days;
      }
      return out;
    }

    var todo = await missing();
    if (todo.isEmpty) return true;

    // 1. ЄЦБ: один запит за весь період для всіх валют.
    final all = todo.values.expand((d) => d).toList()..sort();
    try {
      final rows = await _fetchEcbSeries(
        all.first.subtract(const Duration(days: RateHistory.maxGapDays)),
        all.last,
        todo.keys.toList()..sort(),
      );
      if (rows.isNotEmpty) await _db.saveRateHistory(rows);
    } catch (_) {
      // Немає мережі чи сервіс недоступний — спробуємо НБУ.
    }

    // 2. НБУ: гривня й валюти, яких немає в ЄЦБ, — по одному дню.
    todo = await missing();
    final days = todo.values.expand((d) => d).toSet().toList()
      ..sort((a, b) => b.compareTo(a)); // новіші спершу
    for (final day in days.take(maxNbuDaysPerRun)) {
      final wanted = [
        for (final e in todo.entries)
          if (e.value.contains(day)) e.key,
      ];
      try {
        final rows = await _fetchNbuDay(day, wanted);
        if (rows.isNotEmpty) await _db.saveRateHistory(rows);
      } catch (_) {
        break; // мережа пропала — продовжимо наступного разу
      }
    }
    return (await missing()).isEmpty;
  }

  Future<List<HistoricalRatesCompanion>> _fetchEcbSeries(
    DateTime from,
    DateTime to,
    List<String> symbols,
  ) async {
    final url = Uri.parse('$ecbHistoryBase${isoDay(from)}..${isoDay(to)}').replace(
      queryParameters: {'base': baseCurrency, 'symbols': symbols.join(',')},
    );
    final res = await _client.get(url).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', url);
    }
    return parseFrankfurterSeries(res.body);
  }

  Future<List<HistoricalRatesCompanion>> _fetchNbuDay(
    DateTime day,
    List<String> symbols,
  ) async {
    final d = isoDay(day).replaceAll('-', '');
    final url = Uri.parse('$nbuDayUrl?date=$d&json');
    final res = await _client.get(url).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', url);
    }
    final all = parseNbu(res.body);
    return [
      for (final c in symbols)
        if (all.containsKey(c))
          HistoricalRatesCompanion(
            currency: Value(c),
            day: Value(isoDay(day)),
            perEur: Value(all[c]!.perEur),
            source: const Value('NBU'),
          ),
    ];
  }

  /// `{"base":"EUR","start_date":"…","end_date":"…","rates":{"2026-01-02":{"USD":1.03},…}}`
  static List<HistoricalRatesCompanion> parseFrankfurterSeries(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final rates = json['rates'] as Map<String, dynamic>;
    return [
      for (final day in rates.entries)
        if (day.value is Map)
          for (final r in (day.value as Map<String, dynamic>).entries)
            if (r.value is num && (r.value as num) > 0)
              HistoricalRatesCompanion(
                currency: Value(r.key),
                day: Value(day.key),
                perEur: Value((r.value as num).toDouble()),
                source: const Value('ECB'),
              ),
    ];
  }

  Future<Map<String, ParsedRate>> _fetchEcb(List<String> symbols) async {
    final url = frankfurterUrl.replace(
      queryParameters: {'base': baseCurrency, 'symbols': symbols.join(',')},
    );
    final res = await _client.get(url).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', url);
    }
    return parseFrankfurter(res.body);
  }

  Future<Map<String, ParsedRate>> _fetchNbu(List<String> symbols) async {
    final res = await _client.get(nbuUrl).timeout(_timeout);
    if (res.statusCode != 200) {
      throw http.ClientException('HTTP ${res.statusCode}', nbuUrl);
    }
    final all = parseNbu(res.body);
    return {
      for (final c in symbols)
        if (all.containsKey(c)) c: all[c]!,
    };
  }

  /// `{"base":"EUR","date":"2026-10-23","rates":{"USD":1.1193}}`
  static Map<String, ParsedRate> parseFrankfurter(String body) {
    final json = jsonDecode(body) as Map<String, dynamic>;
    final date = json['date'] as String;
    final rates = (json['rates'] as Map<String, dynamic>);
    return {
      for (final e in rates.entries)
        e.key: ParsedRate((e.value as num).toDouble(), date),
    };
  }

  /// НБУ дає гривні за одиницю валюти: `[{"cc":"EUR","rate":50.5766,"exchangedate":"26.10.2026"}, …]`.
  /// Перераховуємо в «одиниць валюти за 1 EUR».
  static Map<String, ParsedRate> parseNbu(String body) {
    final list = (jsonDecode(body) as List).cast<Map<String, dynamic>>();
    final uahPer = <String, double>{};
    String? date;
    for (final row in list) {
      final cc = row['cc'] as String?;
      final rate = row['rate'];
      if (cc == null || rate is! num || rate <= 0) continue;
      uahPer[cc] = rate.toDouble();
      if (cc == baseCurrency) {
        date = _nbuDateToIso(row['exchangedate'] as String?);
      }
    }
    final uahPerEur = uahPer[baseCurrency];
    if (uahPerEur == null || date == null) {
      throw const FormatException('У відповіді НБУ немає курсу EUR');
    }
    return {
      'UAH': ParsedRate(uahPerEur, date),
      for (final e in uahPer.entries)
        if (e.key != baseCurrency) e.key: ParsedRate(uahPerEur / e.value, date),
    };
  }

  static String? _nbuDateToIso(String? d) {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(d ?? '');
    return m == null ? null : '${m[3]}-${m[2]}-${m[1]}';
  }
}

class ParsedRate {
  const ParsedRate(this.perEur, this.date);
  final double perEur;
  final String date;

  ExchangeRatesCompanion toCompanion(
    String currency,
    String source,
    DateTime fetchedAt,
  ) => ExchangeRatesCompanion(
    currency: Value(currency),
    perEur: Value(perEur),
    rateDate: Value(date),
    source: Value(source),
    fetchedAt: Value(fetchedAt),
  );
}

/// Сума у валюті → центи EUR за курсом. null, якщо курсу немає.
int? toEurCents(
  int amountCents,
  String currency,
  Map<String, ExchangeRate> rates,
) {
  if (currency == baseCurrency) return amountCents;
  final r = rates[currency];
  if (r == null || r.perEur <= 0) return null;
  return (amountCents / r.perEur).round();
}
