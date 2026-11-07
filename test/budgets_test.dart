import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/data/rate_history.dart';
import 'package:my_manager/features/finance/budgets.dart';
import 'package:my_manager/features/finance/period.dart';
import 'package:my_manager/sync/snapshot.dart';

ExchangeRate _rate(String c, double v) => ExchangeRate(
    currency: c, perEur: v, rateDate: '2026-10-27', source: 'NBU', fetchedAt: DateTime(2026, 10, 27));

/// Етап 11: бюджети.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  final oct = Period.of(PeriodKind.month, DateTime(2026, 10, 15));
  final rates = {'UAH': _rate('UAH', 50), 'USD': _rate('USD', 1.25)};

  Future<void> spend(int cents, String currency, String cat, DateTime date) => db.addEntry(
      type: EntryType.expense, amountCents: cents, currency: currency, categoryId: cat, date: date);

  Future<Budget> budget(String id) async =>
      (await db.watchBudgets().first).firstWhere((b) => b.id == id);

  test('бюджет категорії: лише ця категорія й цей місяць, інші валюти перераховуються', () async {
    await db.setBudget(categoryId: 'exp-restaurant', limitCents: 20000, currency: 'EUR');
    await spend(5000, 'EUR', 'exp-restaurant', DateTime(2026, 10, 2));
    await spend(250000, 'UAH', 'exp-restaurant', DateTime(2026, 10, 5)); // 50 €
    await spend(9999, 'EUR', 'exp-groceries', DateTime(2026, 10, 5)); // інша категорія
    await spend(7777, 'EUR', 'exp-restaurant', DateTime(2026, 9, 30)); // інший місяць
    await db.addEntry(type: EntryType.income, amountCents: 100000, currency: 'EUR',
        categoryId: 'inc-salary', date: DateTime(2026, 10, 1));

    final u = budgetUsage(
      budget: await budget('exp-restaurant'),
      entries: await db.watchAllEntries().first,
      month: oct,
      rates: rates,
    );
    expect(u.spentCents, 10000);
    expect(u.leftCents, 10000);
    expect(u.level, BudgetLevel.ok);
  });

  test('ліміт у гривнях: витрати в євро й доларах перераховуються в гривні', () async {
    await db.setBudget(limitCents: 1000000, currency: 'UAH'); // загальний, 10 000 ₴
    await spend(10000, 'EUR', 'exp-fun', DateTime(2026, 10, 3)); // 5 000 ₴
    await spend(5000, 'USD', 'exp-groceries', DateTime(2026, 10, 3)); // 40 € → 2 000 ₴
    final u = budgetUsage(
      budget: await budget(AppDatabase.totalBudgetId),
      entries: await db.watchAllEntries().first,
      month: oct,
      rates: rates,
    );
    expect(u.spentCents, 700000);
    expect(u.level, BudgetLevel.ok);
  });

  test('курс дати запису важливіший за поточний', () async {
    await db.setBudget(categoryId: 'exp-fun', limitCents: 10000, currency: 'EUR');
    await spend(440000, 'UAH', 'exp-fun', DateTime(2026, 10, 5));
    final history = RateHistory([
      HistoricalRate(currency: 'UAH', day: '2026-10-05', perEur: 44, source: 'NBU'),
    ]);
    final u = budgetUsage(
      budget: await budget('exp-fun'),
      entries: await db.watchAllEntries().first,
      month: oct,
      rates: rates,
      history: history,
    );
    expect(u.spentCents, 10000); // 4 400 ₴ / 44 = 100 €
    expect(u.level, BudgetLevel.warning); // рівно 100 % — ще не перевищено
  });

  test('рівні: до 80 % зелений, від 80 % жовтий, понад ліміт червоний', () {
    expect(BudgetUsage.levelFor(7999, 10000), BudgetLevel.ok);
    expect(BudgetUsage.levelFor(8000, 10000), BudgetLevel.warning);
    expect(BudgetUsage.levelFor(10000, 10000), BudgetLevel.warning);
    expect(BudgetUsage.levelFor(10001, 10000), BudgetLevel.over);
  });

  test('попередження у формі: нова витрата перевищить бюджет; редагування не рахує себе двічі', () async {
    await db.setBudget(categoryId: 'exp-restaurant', limitCents: 20000, currency: 'EUR');
    await db.setBudget(limitCents: 100000, currency: 'EUR');
    await spend(15000, 'EUR', 'exp-restaurant', DateTime(2026, 10, 2));
    final entries = await db.watchAllEntries().first;
    final budgets = await db.watchBudgets().first;

    var p = previewExpense(budgets: budgets, entries: entries, categoryId: 'exp-restaurant',
        amountCents: 8000, currency: 'EUR', date: DateTime(2026, 10, 20), rates: rates);
    expect(p.length, 1); // загальний ще далеко
    expect(p.single.budget.categoryId, 'exp-restaurant');
    expect(p.single.afterCents, 23000);
    expect(p.single.overCents, 3000);
    expect(p.single.level, BudgetLevel.over);

    // Інша категорія — бюджет кафе не зачіпає.
    p = previewExpense(budgets: budgets, entries: entries, categoryId: 'exp-groceries',
        amountCents: 8000, currency: 'EUR', date: DateTime(2026, 10, 20), rates: rates);
    expect(p, isEmpty);

    // Редагування того самого запису 150 → 160 €: 160 / 200, ще жовтий, не червоний.
    p = previewExpense(budgets: budgets, entries: entries, categoryId: 'exp-restaurant',
        amountCents: 16000, currency: 'EUR', date: DateTime(2026, 10, 2), rates: rates,
        excludeEntryId: entries.single.id);
    expect(p.single.afterCents, 16000);
    expect(p.single.level, BudgetLevel.warning);
  });

  test('зміна й видалення бюджету; один бюджет на категорію', () async {
    await db.setBudget(categoryId: 'exp-fun', limitCents: 100, currency: 'EUR');
    await db.setBudget(categoryId: 'exp-fun', limitCents: 200, currency: 'PLN');
    final list = await db.watchBudgets().first;
    expect(list.single.limitCents, 200);
    expect(list.single.currency, 'PLN');
    await db.deleteBudget('exp-fun');
    expect(await db.watchBudgets().first, isEmpty);
    // Повторне створення після видалення.
    await db.setBudget(categoryId: 'exp-fun', limitCents: 300, currency: 'EUR');
    expect((await db.watchBudgets().first).single.limitCents, 300);
  });

  test('синхронізація бюджетів; очищення даних', () async {
    await db.setBudget(categoryId: 'exp-fun', limitCents: 15000, currency: 'UAH');
    await db.setBudget(limitCents: 99900, currency: 'EUR');
    final text = (await db.exportSnapshot()).encode();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.mergeSnapshot(FinanceSnapshot.decode(text));
    final b = await other.watchBudgets().first;
    expect(b.length, 2);
    expect(b.firstWhere((x) => x.categoryId == null).limitCents, 99900);
    expect(b.firstWhere((x) => x.categoryId == 'exp-fun').currency, 'UAH');

    await db.wipeAllData(resetId: 'x');
    expect(await db.watchBudgets().first, isEmpty);
  });

  test('оновлення з версії 6 (етап 10): таблиця бюджетів з\'являється', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v6.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
        categoryId: 'exp-groceries', date: DateTime(2026, 10, 1));
    await old.customStatement('DROP TABLE budgets');
    await old.customStatement('PRAGMA user_version = 6');
    await old.close();

    final db7 = AppDatabase(NativeDatabase(file));
    expect((await db7.watchAllEntries().first).single.amountCents, 4590);
    expect(await db7.watchBudgets().first, isEmpty);
    await db7.close();
    await dir.delete(recursive: true);
  });
}
