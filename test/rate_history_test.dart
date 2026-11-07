import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/data/rate_history.dart';
import 'package:my_manager/data/rates_service.dart';
import 'package:my_manager/features/finance/ledger.dart';
import 'package:my_manager/features/finance/period.dart';
import 'package:my_manager/features/finance/stats.dart';

HistoricalRate _r(String c, String day, double v) =>
    HistoricalRate(currency: c, day: day, perEur: v, source: 'ECB');

/// Етап 10: курс на дату запису.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('uk'));

  group('RateHistory', () {
    final h = RateHistory([
      _r('USD', '2026-01-02', 1.03),
      _r('USD', '2026-01-09', 1.05), // п'ятниця
      _r('USD', '2026-03-02', 1.10),
    ]);

    test('точна дата, вихідні — попередній робочий день', () {
      expect(h.perEurAt('USD', DateTime(2026, 1, 2)), 1.03);
      expect(h.perEurAt('USD', DateTime(2026, 1, 11)), 1.05); // неділя
    });

    test('прогалина понад тиждень і дата до першого курсу — немає даних', () {
      expect(h.perEurAt('USD', DateTime(2026, 2, 1)), isNull);
      expect(h.perEurAt('USD', DateTime(2025, 12, 31)), isNull);
      expect(h.perEurAt('PLN', DateTime(2026, 1, 2)), isNull);
    });

    test('toEurCentsOn: курс дати, інакше поточний', () {
      final current = {
        'USD': ExchangeRate(currency: 'USD', perEur: 1.2, rateDate: '2026-10-27',
            source: 'ECB', fetchedAt: DateTime(2026, 10, 27)),
      };
      expect(toEurCentsOn(10300, 'USD', DateTime(2026, 1, 2), current, h), 10000);
      expect(toEurCentsOn(12000, 'USD', DateTime(2026, 6, 1), current, h), 10000);
      expect(toEurCentsOn(500, 'EUR', DateTime(2026, 6, 1), const {}, h), 500);
      expect(toEurCentsOn(500, 'PLN', DateTime(2026, 6, 1), const {}, h), isNull);
    });
  });

  group('завантаження курсів на дату', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    /// ЄЦБ знає USD, але не UAH; НБУ віддає курс на конкретний день.
    MockClient net(List<Uri> log, {bool online = true}) => MockClient((req) async {
          log.add(req.url);
          if (!online) throw http.ClientException('no network');
          if (req.url.host == 'api.frankfurter.dev') {
            return http.Response(
              jsonEncode({
                'base': 'EUR',
                'start_date': '2026-01-02',
                'end_date': '2026-03-10',
                'rates': {
                  '2026-01-02': {'USD': 1.03},
                  '2026-03-10': {'USD': 1.10},
                },
              }),
              200,
            );
          }
          if (req.url.host == 'bank.gov.ua') {
            final d = req.url.queryParameters['date']!; // YYYYMMDD
            final rate = d == '20260115' ? 44.0 : 48.0;
            return http.Response.bytes(
              utf8.encode(jsonEncode([
                {'cc': 'EUR', 'rate': rate, 'exchangedate': '${d.substring(6)}.${d.substring(4, 6)}.${d.substring(0, 4)}'},
                {'cc': 'USD', 'rate': 40.0, 'exchangedate': '${d.substring(6)}.${d.substring(4, 6)}.${d.substring(0, 4)}'},
              ])),
              200,
            );
          }
          return http.Response('?', 404);
        });

    test('ЄЦБ одним запитом, гривня — НБУ по днях; повторно нічого не качає', () async {
      await db.addEntry(type: EntryType.expense, amountCents: 1030, currency: 'USD',
          categoryId: 'exp-other', date: DateTime(2026, 1, 3));
      await db.addEntry(type: EntryType.expense, amountCents: 44000, currency: 'UAH',
          categoryId: 'exp-other', date: DateTime(2026, 1, 15));
      await db.addEntry(type: EntryType.expense, amountCents: 48000, currency: 'UAH',
          categoryId: 'exp-other', date: DateTime(2026, 3, 10));
      // Свіжий запис (сьогодні) — курс на дату не потрібен.
      await db.addEntry(type: EntryType.expense, amountCents: 100, currency: 'UAH',
          categoryId: 'exp-other', date: DateTime(2026, 10, 27));
      final log = <Uri>[];
      final service = RatesService(db, client: net(log), clock: () => DateTime(2026, 10, 27, 12));

      expect(await service.fillHistory(), isTrue);
      expect(log.where((u) => u.host == 'api.frankfurter.dev').length, 1);
      expect(log.first.path, '/v1/2025-12-27..2026-03-10');
      final nbuDays = log.where((u) => u.host == 'bank.gov.ua').map((u) => u.queryParameters['date']).toSet();
      expect(nbuDays, {'20260115', '20260310'});

      final h = RateHistory(await db.getRateHistory());
      expect(h.perEurAt('USD', DateTime(2026, 1, 3)), 1.03);
      expect(h.perEurAt('UAH', DateTime(2026, 1, 15)), 44.0);
      expect(h.perEurAt('UAH', DateTime(2026, 3, 10)), 48.0);

      log.clear();
      expect(await service.fillHistory(), isTrue);
      expect(log, isEmpty);
    });

    test('без інтернету — тихо false, старі дані на місці', () async {
      await db.addEntry(type: EntryType.expense, amountCents: 100, currency: 'UAH',
          categoryId: 'exp-other', date: DateTime(2026, 1, 15));
      final service = RatesService(db, client: net([], online: false), clock: () => DateTime(2026, 10, 27));
      expect(await service.fillHistory(), isFalse);
      expect(await db.getRateHistory(), isEmpty);
    });

    test('статистика за минулий місяць — за курсом дати запису', () async {
      await db.addEntry(type: EntryType.expense, amountCents: 44000, currency: 'UAH',
          categoryId: 'exp-other', date: DateTime(2026, 1, 15));
      await db.saveRates([
        ExchangeRatesCompanion.insert(currency: 'UAH', perEur: 50.0, rateDate: '2026-10-27',
            source: 'NBU', fetchedAt: DateTime(2026, 10, 27)),
      ]);
      final rates = await db.watchRates().first;
      final movements = buildMovements(entries: await db.watchAllEntries().first);
      final jan = Period.of(PeriodKind.month, DateTime(2026, 1, 15));

      // Ще без курсу на дату — за поточним (440 / 50 = 8,80 €).
      var stats = computeStatsFromMovements(movements: movements, period: jan, rates: rates);
      expect(stats.expenseCents, 880);

      await RatesService(db, client: net([]), clock: () => DateTime(2026, 10, 27)).fillHistory();
      final h = RateHistory(await db.getRateHistory());
      // За курсом 15 січня: 440 / 44 = 10,00 €.
      stats = computeStatsFromMovements(movements: movements, period: jan, rates: rates, history: h);
      expect(stats.expenseCents, 1000);
    });

    test('оновлення з версії 5 (етап 9): таблиця курсів на дату з\'являється', () async {
      final dir = await Directory.systemTemp.createTemp('mymanager');
      final file = File('${dir.path}/v5.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'UAH',
          categoryId: 'exp-groceries', date: DateTime(2026, 1, 15));
      await old.customStatement('DROP TABLE historical_rates');
      await old.customStatement('PRAGMA user_version = 5');
      await old.close();

      final db6 = AppDatabase(NativeDatabase(file));
      expect((await db6.watchAllEntries().first).single.amountCents, 4590);
      expect(await db6.getRateHistory(), isEmpty);
      await db6.close();
      await dir.delete(recursive: true);
    });
  });
}
