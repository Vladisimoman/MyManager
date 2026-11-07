import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/data/rates_service.dart';
import 'package:my_manager/features/finance/finance_providers.dart';
import 'package:my_manager/features/finance/ledger.dart';

import 'helpers/fake_net.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('розбір відповідей', () {
    test('Frankfurter', () {
      final r = RatesService.parseFrankfurter(ecbBody);
      expect(r['USD']!.perEur, 1.1193);
      expect(r['USD']!.date, '2026-10-23');
    });

    test('НБУ перераховується в «за 1 EUR»', () {
      final r = RatesService.parseNbu(nbuBody);
      expect(r['UAH']!.perEur, 50.5766);
      expect(r['UAH']!.date, '2026-10-26');
      expect(r['USD']!.perEur, closeTo(50.5766 / 45.2021, 1e-9)); // ≈ 1.1189
    });

    test('НБУ без EUR — помилка формату', () {
      expect(() => RatesService.parseNbu('[]'), throwsFormatException);
    });
  });

  group('сервіс курсів', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('USD з ЄЦБ, UAH з НБУ', () async {
      final s = RatesService(db, client: fakeNet());
      expect(await s.refresh(), RatesRefreshResult.updated);
      final rates = await db.watchRates().first;
      expect(rates['USD']!.source, 'ECB');
      expect(rates['UAH']!.source, 'NBU');
      expect(rates['UAH']!.perEur, 50.5766);
    });

    test('ЄЦБ недоступний — обидві валюти з НБУ', () async {
      final s = RatesService(db, client: fakeNet(ecb: false));
      expect(await s.refresh(), RatesRefreshResult.updated);
      final rates = await db.watchRates().first;
      expect(rates['USD']!.source, 'NBU');
      expect(rates['UAH']!.source, 'NBU');
    });

    test('без інтернету старі курси лишаються', () async {
      await RatesService(db, client: fakeNet()).refresh();
      final offline = RatesService(db, client: fakeNet(ecb: false, nbu: false));
      expect(await offline.refresh(), RatesRefreshResult.failed);
      expect((await db.watchRates().first)['UAH']!.perEur, 50.5766);
    });

    test('свіжі курси не перезавантажуються, старі — так', () async {
      var now = DateTime.utc(2026, 10, 26, 10);
      final log = <String>[];
      final s = RatesService(db, client: fakeNet(log: log), clock: () => now);

      expect(await s.refreshIfStale(), RatesRefreshResult.updated);
      final calls = log.length;

      now = now.add(const Duration(hours: 2));
      expect(await s.refreshIfStale(), RatesRefreshResult.notNeeded);
      expect(log.length, calls);

      now = now.add(const Duration(hours: 5));
      expect(await s.refreshIfStale(), RatesRefreshResult.updated);
      expect(log.length, greaterThan(calls));
    });
  });

  group('перерахунок у EUR', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('toEurCents', () async {
      await RatesService(db, client: fakeNet()).refresh();
      final rates = await db.watchRates().first;
      expect(toEurCents(1000, 'EUR', rates), 1000);
      expect(toEurCents(50577, 'UAH', rates), 1000); // 505,77 ₴ ≈ 10,00 €
      expect(toEurCents(11193, 'USD', rates), 10000); // 111,93 $ = 100,00 €
      expect(toEurCents(100, 'GBP', rates), isNull);
    });

    test('баланс враховує всі валюти за курсом', () async {
      await RatesService(db, client: fakeNet()).refresh();
      await db.addEntry(type: EntryType.income, amountCents: 100000, currency: 'EUR',
          categoryId: 'inc-salary', date: DateTime(2026, 10, 1));
      await db.addEntry(type: EntryType.expense, amountCents: 50577, currency: 'UAH',
          categoryId: 'exp-phone', date: DateTime(2026, 10, 2));
      await db.addEntry(type: EntryType.expense, amountCents: 11193, currency: 'USD',
          categoryId: 'exp-subscriptions', date: DateTime(2026, 10, 3));

      final b = computeBalance(
        buildMovements(entries: await db.watchAllEntries().first),
        await db.watchRates().first,
      );
      expect(b.cents, 100000 - 1000 - 10000);
      expect(b.skippedCount, 0);
    });

    test('без курсу запис пропускається й рахується окремо', () async {
      await db.addEntry(type: EntryType.expense, amountCents: 30000, currency: 'UAH',
          categoryId: 'exp-phone', date: DateTime(2026, 10, 2));
      final b = computeBalance(buildMovements(entries: await db.watchAllEntries().first), const {});
      expect(b.cents, 0);
      expect(b.skippedByCurrency, {'UAH': 1});
    });
  });
}
