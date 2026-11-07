import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/data/rates_service.dart';
import 'package:my_manager/features/finance/finance_providers.dart';
import 'package:my_manager/features/finance/ledger.dart';
import 'package:my_manager/features/finance/period.dart';
import 'package:my_manager/features/finance/stats.dart';
import 'package:my_manager/sync/snapshot.dart';
import 'package:my_manager/sync/sync_service.dart';

import 'helpers/fake_net.dart';
import 'helpers/memory_cloud.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('uk'));

  final dbs = <AppDatabase>[];
  AppDatabase device() {
    final db = AppDatabase(NativeDatabase.memory());
    dbs.add(db);
    return db;
  }

  tearDown(() async {
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
  });

  const cash = AppDatabase.mainWalletId;
  final oct = DateTime(2026, 10, 10);

  Future<List<Movement>> movementsOf(AppDatabase db) async => buildMovements(
        entries: await db.watchAllEntries().first,
        transfers: await db.watchTransfers().first,
        walletCurrencies: await db.watchWalletCurrencies().first,
      );

  group('гаманці й баланси', () {
    test('свіжа база: «Готівка» з EUR', () async {
      final db = device();
      final w = await db.watchWallets().first;
      expect(w.single.id, cash);
      expect(w.single.name, 'Готівка');
      expect((await db.watchWalletCurrencies().first).single.currency, 'EUR');
    });

    test('кілька валют, початкові баланси, записи', () async {
      final db = device();
      await db.setWalletCurrency(cash, 'EUR', 20000);
      await db.setWalletCurrency(cash, 'UAH', 300000);
      final card = await db.addWallet(name: 'Картка', icon: 'card', color: 1, currencies: {'EUR': 50000});
      await db.addEntry(type: EntryType.expense, amountCents: 1500, currency: 'EUR',
          categoryId: 'exp-groceries', date: oct, walletId: card);
      await db.addEntry(type: EntryType.income, amountCents: 10000, currency: 'UAH',
          categoryId: 'inc-other', date: oct);

      final b = walletBalances(await movementsOf(db));
      expect(b[cash], {'EUR': 20000, 'UAH': 310000});
      expect(b[card], {'EUR': 48500});
    });

    test('переказ у тій самій валюті не змінює загальний баланс', () async {
      final db = device();
      await db.setWalletCurrency(cash, 'EUR', 20000);
      final card = await db.addWallet(name: 'Картка', icon: 'card', color: 1);
      await db.addTransfer(fromWalletId: cash, fromCurrency: 'EUR', fromAmountCents: 5000,
          toWalletId: card, toCurrency: 'EUR', toAmountCents: 5000, date: oct);

      final m = await movementsOf(db);
      expect(walletBalances(m)[cash]!['EUR'], 15000);
      expect(walletBalances(m)[card]!['EUR'], 5000);
      expect(computeBalance(m, const {}).cents, 20000);
    });

    test('обмін валют: гаманець змінює валюту, загальний — на різницю курсу', () async {
      final db = device();
      await RatesService(db, client: fakeNet()).refresh(); // 1 € = 50,5766 ₴
      final rates = await db.watchRates().first;
      await db.setWalletCurrency(cash, 'EUR', 10000);
      await db.setWalletCurrency(cash, 'UAH', 0);
      // Обмінник: 100 € → 5 000 ₴ (дешевше за курс НБУ)
      await db.addTransfer(fromWalletId: cash, fromCurrency: 'EUR', fromAmountCents: 10000,
          toWalletId: cash, toCurrency: 'UAH', toAmountCents: 500000, date: oct);

      final m = await movementsOf(db);
      expect(walletBalances(m)[cash], {'EUR': 0, 'UAH': 500000});
      // 5000 ₴ / 50,5766 ≈ 98,86 €
      expect(computeBalance(m, rates).cents, 9886);
    });

    test('від\'ємний баланс дозволено (овердрафт)', () async {
      final db = device();
      await db.addEntry(type: EntryType.expense, amountCents: 700, currency: 'EUR',
          categoryId: 'exp-other', date: oct);
      expect(walletBalances(await movementsOf(db))[cash]!['EUR'], -700);
    });

    test('гаманець з записами не можна видалити; валюту з записами — прибрати', () async {
      final db = device();
      final card = await db.addWallet(name: 'Картка', icon: 'card', color: 1,
          currencies: {'EUR': 0, 'USD': 0});
      expect(await db.isWalletUsed(card), isFalse);
      await db.addEntry(type: EntryType.expense, amountCents: 1, currency: 'USD',
          categoryId: 'exp-other', date: oct, walletId: card);
      expect(await db.isWalletUsed(card), isTrue);
      expect(await db.isWalletUsed(card, currency: 'USD'), isTrue);
      expect(await db.isWalletUsed(card, currency: 'EUR'), isFalse);
    });
  });

  group('статистика з гаманцями', () {
    test('перекази не входять у надходження й витрати; фільтр гаманця', () async {
      final db = device();
      await db.setWalletCurrency(cash, 'EUR', 10000);
      final card = await db.addWallet(name: 'Картка', icon: 'card', color: 1);
      await db.addEntry(type: EntryType.income, amountCents: 200000, currency: 'EUR',
          categoryId: 'inc-salary', date: oct, walletId: card);
      await db.addTransfer(fromWalletId: card, fromCurrency: 'EUR', fromAmountCents: 30000,
          toWalletId: cash, toCurrency: 'EUR', toAmountCents: 30000, date: oct);
      await db.addEntry(type: EntryType.expense, amountCents: 5000, currency: 'EUR',
          categoryId: 'exp-groceries', date: oct);

      final m = await movementsOf(db);
      final period = Period.of(PeriodKind.month, oct);

      final all = computeStatsFromMovements(movements: m, period: period, rates: const {});
      expect(all.incomeCents, 200000);
      expect(all.expenseCents, 5000);
      expect(all.buckets.last.balanceAtEndCents, 10000 + 200000 - 5000);

      final onlyCash = computeStatsFromMovements(
          movements: m, period: period, rates: const {}, walletId: cash);
      expect(onlyCash.incomeCents, 0);
      expect(onlyCash.expenseCents, 5000);
      expect(onlyCash.buckets.last.balanceAtEndCents, 10000 + 30000 - 5000);

      final onlyCard = computeStatsFromMovements(
          movements: m, period: period, rates: const {}, walletId: card);
      expect(onlyCard.incomeCents, 200000);
      expect(onlyCard.buckets.last.balanceAtEndCents, 200000 - 30000);
    });
  });

  group('синхронізація', () {
    late MemoryCloudStore cloud;
    setUp(() => cloud = MemoryCloudStore());

    test('гаманці, валюти й перекази доходять на інший пристрій', () async {
      final a = device(), b = device();
      final card = await a.addWallet(name: 'Картка', icon: 'card', color: 1,
          currencies: {'EUR': 1000, 'PLN': 0});
      await a.addTransfer(fromWalletId: cash, fromCurrency: 'EUR', fromAmountCents: 100,
          toWalletId: card, toCurrency: 'PLN', toAmountCents: 425, date: oct, note: 'обмін');
      await a.addEntry(type: EntryType.expense, amountCents: 300, currency: 'PLN',
          categoryId: 'exp-fun', date: oct, walletId: card);
      await SyncService(a, cloud).sync();
      await SyncService(b, cloud).sync();

      expect((await b.watchWallets().first).map((w) => w.name), ['Готівка', 'Картка']);
      expect(walletBalances(await movementsOf(b))[card], {'EUR': 1000, 'PLN': 125});
      expect((await b.watchTransfers().first).single.note, 'обмін');
      expect((await b.watchAllEntries().first).single.walletId, card);
    });

    test('файл старого формату (v1) читається: записи йдуть у «Готівку»', () async {
      const v1 = '{"format":"mymanager-finance","version":1,'
          '"transactions":[{"id":"t1","type":"expense","amountCents":500,"currency":"EUR",'
          '"categoryId":"exp-fun","date":"2026-10-01","note":null,'
          '"createdAt":"2026-10-01T10:00:00.000Z","updatedAt":"2026-10-01T10:00:00.000Z",'
          '"deleted":false}],"categories":[],"settings":[]}';
      final snap = FinanceSnapshot.decode(v1);
      expect(snap.transactions.single.walletId, cash);
      expect(snap.wallets, isEmpty);
    });

    test('видалення на одному пристрої очищує інший і не повертає старі дані', () async {
      final a = device(), b = device();
      await a.addEntry(type: EntryType.expense, amountCents: 111, currency: 'EUR',
          categoryId: 'exp-fun', date: oct);
      await SyncService(a, cloud).sync();
      await SyncService(b, cloud).sync();
      expect(await b.countEntries(), 1);
      final beforeWipe = cloud.files['finance.json'];

      // A видаляє все, поки офлайн, потім синхронізується.
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      await a.wipeAllData(resetId: 'reset-1');
      await a.addEntry(type: EntryType.income, amountCents: 999, currency: 'EUR',
          categoryId: 'inc-other', date: oct);
      await SyncService(a, cloud).sync();
      expect(await a.countEntries(), 1); // старий запис з Drive не повернувся
      expect(cloud.files['finance.backup.json'], beforeWipe); // резервна копія

      // B (зі старими даними) синхронізується — очищується й отримує нові.
      final r = await SyncService(b, cloud).sync();
      expect(r.resetApplied, isTrue);
      final left = await b.watchAllEntries().first;
      expect(left.single.amountCents, 999);

      // І старі дані B не потрапили назад на Drive.
      final c = device();
      await SyncService(c, cloud).sync();
      expect(await c.countEntries(), 1);
    });
  });
}
