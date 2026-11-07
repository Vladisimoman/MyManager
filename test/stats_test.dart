import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/data/rates_service.dart';
import 'package:my_manager/features/finance/period.dart';
import 'package:my_manager/features/finance/stats.dart';

import 'helpers/fake_net.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('uk'));

  group('Period', () {
    test('тиждень з понеділка до неділі', () {
      final p = Period.of(PeriodKind.week, DateTime(2026, 10, 29)); // четвер
      expect(p.start, DateTime(2026, 10, 26));
      expect(p.lastDay, DateTime(2026, 11, 1));
      expect(p.days, 7);
      expect(p.label, '26 жовт. – 1 лист. 2026');
    });

    test('тиждень через перехід на зимовий час (25.10.2026) має 7 днів', () {
      final p = Period.of(PeriodKind.week, DateTime(2026, 10, 22));
      expect(p.start, DateTime(2026, 10, 19));
      expect(p.end, DateTime(2026, 10, 26));
      expect(p.days, 7);
    });

    test('місяць, рік і зсув через межу року', () {
      final m = Period.of(PeriodKind.month, DateTime(2026, 12, 15));
      expect(m.label, 'Грудень 2026');
      expect(m.shift(1).start, DateTime(2027, 1, 1));
      expect(m.shift(-12).label, 'Грудень 2025');
      final y = Period.of(PeriodKind.year, DateTime(2026, 5, 1));
      expect(y.days, 365);
      expect(y.label, '2026');
    });

    test('свій діапазон включає обидві дати', () {
      final p = Period.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 15));
      expect(p.contains(DateTime(2026, 10, 15)), isTrue);
      expect(p.contains(DateTime(2026, 10, 16)), isFalse);
      expect(p.days, 15);
      expect(p.label, '1–15 жовтня 2026');
      expect(p.canShift, isFalse);
    });
  });

  group('computeStats', () {
    late AppDatabase db;
    late Map<String, ExchangeRate> rates;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await RatesService(db, client: fakeNet()).refresh();
      rates = await db.watchRates().first;

      Future<void> add(EntryType t, int cents, String cur, String cat, DateTime d) =>
          db.addEntry(type: t, amountCents: cents, currency: cur, categoryId: cat, date: d);

      // До періоду: впливає лише на баланс на початок.
      await add(EntryType.income, 50000, 'EUR', 'inc-other', DateTime(2026, 9, 20));
      // Жовтень 2026.
      await add(EntryType.income, 200000, 'EUR', 'inc-salary', DateTime(2026, 10, 1));
      await add(EntryType.expense, 30000, 'EUR', 'exp-home', DateTime(2026, 10, 3));
      await add(EntryType.expense, 10000, 'EUR', 'exp-groceries', DateTime(2026, 10, 10));
      await add(EntryType.expense, 50577, 'UAH', 'exp-groceries', DateTime(2026, 10, 27)); // 10 €
      await add(EntryType.expense, 999, 'GBP', 'exp-fun', DateTime(2026, 10, 28)); // курсу немає
      // Після періоду — не враховується.
      await add(EntryType.expense, 7000, 'EUR', 'exp-fun', DateTime(2026, 11, 2));
    });
    tearDown(() => db.close());

    Future<PeriodStats> statsFor(Period p) async => computeStats(
          entries: await db.watchAllEntries().first,
          period: p,
          rates: rates,
          initialBalanceCents: 10000,
        );

    test('підсумки місяця й категорії', () async {
      final s = await statsFor(Period.of(PeriodKind.month, DateTime(2026, 10, 1)));
      expect(s.incomeCents, 200000);
      expect(s.expenseCents, 30000 + 10000 + 1000);
      expect(s.netCents, 200000 - 41000);
      expect(s.skippedCount, 1);

      expect(s.expenseByCategory.map((c) => c.categoryId), ['exp-home', 'exp-groceries']);
      expect(s.expenseByCategory.first.cents, 30000);
      expect(s.expenseByCategory.last.cents, 11000);
      expect(s.expenseByCategory.first.share, closeTo(30000 / 41000, 1e-9));
      expect(s.incomeByCategory.single.share, 1.0);
    });

    test('місяць ділиться на тижні; баланс накопичується від початкового', () async {
      final s = await statsFor(Period.of(PeriodKind.month, DateTime(2026, 10, 1)));
      expect(s.bucketSize, BucketSize.week);
      // 1–4, 5–11, 12–18, 19–25, 26–31 жовтня.
      expect(s.buckets.map((b) => b.start.day), [1, 5, 12, 19, 26]);
      expect(s.buckets.last.end, DateTime(2026, 11, 1));
      final startBalance = 10000 + 50000;
      expect(s.buckets[0].balanceAtEndCents, startBalance + 200000 - 30000);
      expect(s.buckets[1].balanceAtEndCents, startBalance + 200000 - 40000);
      expect(s.buckets.last.balanceAtEndCents, startBalance + 200000 - 41000);
      expect(s.buckets.fold<int>(0, (a, b) => a + b.expenseCents), s.expenseCents);
    });

    test('тиждень — по днях, рік — по місяцях', () async {
      final w = await statsFor(Period.of(PeriodKind.week, DateTime(2026, 10, 27)));
      expect(w.bucketSize, BucketSize.day);
      expect(w.buckets.length, 7);
      expect(w.buckets[1].expenseCents, 1000); // вівторок 27.10

      final y = await statsFor(Period.of(PeriodKind.year, DateTime(2026, 1, 1)));
      expect(y.bucketSize, BucketSize.month);
      expect(y.buckets.length, 12);
      expect(y.buckets[9].label, 'Жовт');
      expect(y.buckets[10].expenseCents, 7000); // листопад
    });

    test('лише записи в UAH: без перерахунку, без початкового балансу', () async {
      final s = computeStats(
        entries: await db.watchAllEntries().first,
        period: Period.of(PeriodKind.month, DateTime(2026, 10, 1)),
        rates: rates,
        initialBalanceCents: 10000,
        onlyCurrency: 'UAH',
      );
      expect(s.onlyCurrency, isTrue);
      expect(s.currency, 'UAH');
      expect(s.expenseCents, 50577);
      expect(s.incomeCents, 0);
      expect(s.skippedCount, 0);
      expect(s.expenseByCategory.single.categoryId, 'exp-groceries');
      expect(s.buckets.last.balanceAtEndCents, -50577);
    });

    test('лише EUR: записи в гривнях не входять', () async {
      final s = computeStats(
        entries: await db.watchAllEntries().first,
        period: Period.of(PeriodKind.month, DateTime(2026, 10, 1)),
        rates: rates,
        onlyCurrency: 'EUR',
      );
      expect(s.expenseCents, 40000);
      expect(s.incomeCents, 200000);
    });

    test('порожній період', () async {
      final s = await statsFor(Period.of(PeriodKind.month, DateTime(2025, 1, 1)));
      expect(s.incomeCents, 0);
      expect(s.expenseCents, 0);
      expect(s.expenseByCategory, isEmpty);
      expect(s.buckets.last.balanceAtEndCents, 10000);
    });
  });
}
