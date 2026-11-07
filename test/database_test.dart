import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/finance_providers.dart';
import 'package:my_manager/features/finance/ledger.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('стартові категорії: 12 витрат і 6 надходжень', () async {
    expect((await db.watchCategories(EntryType.expense).first).length, 12);
    expect((await db.watchCategories(EntryType.income).first).length, 6);
  });

  test('баланс: надходження мінус витрати, лише EUR', () async {
    await db.addEntry(type: EntryType.income, amountCents: 200000, currency: 'EUR',
        categoryId: 'inc-salary', date: DateTime(2026, 10, 1));
    await db.addEntry(type: EntryType.expense, amountCents: 4550, currency: 'EUR',
        categoryId: 'exp-groceries', date: DateTime(2026, 10, 2));
    await db.addEntry(type: EntryType.expense, amountCents: 30000, currency: 'UAH',
        categoryId: 'exp-transport', date: DateTime(2026, 10, 3));
    await db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 10000);
    await db.setWalletCurrency(AppDatabase.mainWalletId, 'UAH', 0);

    final b = computeBalance(
      buildMovements(
        entries: await db.watchAllEntries().first,
        walletCurrencies: await db.watchWalletCurrencies().first,
      ),
      const {},
    );

    expect(b.cents, 10000 + 200000 - 4550);
    expect(b.skippedByCurrency, {'UAH': 1});
  });

  test('редагування й м\'яке видалення з відновленням', () async {
    final id = await db.addEntry(type: EntryType.expense, amountCents: 1000,
        currency: 'EUR', categoryId: 'exp-fun', date: DateTime(2026, 10, 5), note: '  кіно ');
    var list = await db.watchEntries(EntryType.expense).first;
    expect(list.single.note, 'кіно');

    await db.updateEntry(id, amountCents: 1500, currency: 'EUR',
        categoryId: 'exp-fun', date: DateTime(2026, 10, 6), note: '');
    list = await db.watchEntries(EntryType.expense).first;
    expect(list.single.amountCents, 1500);
    expect(list.single.note, isNull);
    expect(list.single.updatedAt.isAfter(list.single.createdAt) ||
        list.single.updatedAt == list.single.createdAt, isTrue);

    await db.setEntryDeleted(id, true);
    expect(await db.watchEntries(EntryType.expense).first, isEmpty);

    await db.setEntryDeleted(id, false);
    expect((await db.watchEntries(EntryType.expense).first).length, 1);
  });

  test('записи відсортовані: новіші дати зверху', () async {
    await db.addEntry(type: EntryType.expense, amountCents: 1, currency: 'EUR',
        categoryId: 'exp-other', date: DateTime(2026, 10, 1));
    await db.addEntry(type: EntryType.expense, amountCents: 2, currency: 'EUR',
        categoryId: 'exp-other', date: DateTime(2026, 10, 9));
    final list = await db.watchEntries(EntryType.expense).first;
    expect(list.map((e) => e.amountCents), [2, 1]);
  });

  test('дані зберігаються після перезапуску (файл бази)', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/test.sqlite');

    final first = AppDatabase(NativeDatabase(file));
    await first.addEntry(type: EntryType.income, amountCents: 777, currency: 'EUR',
        categoryId: 'inc-other', date: DateTime(2026, 10, 1));
    await first.close();

    final second = AppDatabase(NativeDatabase(file));
    final list = await second.watchEntries(EntryType.income).first;
    expect(list.single.amountCents, 777);
    // Категорії не дублюються при повторному відкритті.
    expect((await second.watchCategories(EntryType.income).first).length, 6);
    await second.close();
    await dir.delete(recursive: true);
  });

  test('оновлення бази з версії 1 (етап 2) не втрачає записів', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v1.sqlite');

    // Імітуємо базу, яку створила версія етапу 2: без таблиці курсів, user_version = 1.
    final old = AppDatabase(NativeDatabase(file));
    await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
        categoryId: 'exp-groceries', date: DateTime(2026, 10, 20));
    await _downgradeToV2(old);
    await old.customStatement('DROP TABLE exchange_rates');
    await old.customStatement('PRAGMA user_version = 1');
    await old.close();

    final upgraded = AppDatabase(NativeDatabase(file));
    expect((await upgraded.watchEntries(EntryType.expense).first).single.amountCents, 4590);
    expect(await upgraded.watchRates().first, isEmpty); // таблиця курсів створена
    await upgraded.close();
    await dir.delete(recursive: true);
  });

  test('оновлення з версії 2 (етап 6): записи й баланс переходять у «Готівку»', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v2.sqlite');

    final old = AppDatabase(NativeDatabase(file));
    await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
        categoryId: 'exp-groceries', date: DateTime(2026, 10, 20));
    await old.addEntry(type: EntryType.expense, amountCents: 30000, currency: 'UAH',
        categoryId: 'exp-transport', date: DateTime(2026, 10, 21));
    await _downgradeToV2(old);
    await old.setSetting(SettingKeys.legacyInitialBalanceCents, '150000');
    await old.close();

    final db2 = AppDatabase(NativeDatabase(file));
    final entries = await db2.watchAllEntries().first;
    expect(entries.length, 2);
    expect(entries.every((e) => e.walletId == AppDatabase.mainWalletId), isTrue);
    final wallets = await db2.watchWallets().first;
    expect(wallets.single.name, 'Готівка');
    expect(await db2.getInitialCents(AppDatabase.mainWalletId, 'EUR'), 150000);
    final codes = (await db2.watchWalletCurrencies().first).map((c) => c.currency).toSet();
    expect(codes, {'EUR', 'UAH'});
    await db2.close();
    await dir.delete(recursive: true);
  });

  test('видалення всіх даних повертає стартовий стан', () async {
    await db.addEntry(type: EntryType.expense, amountCents: 1, currency: 'EUR',
        categoryId: 'exp-other', date: DateTime(2026, 10, 1));
    final w = await db.addWallet(name: 'Картка', icon: 'card', color: 1);
    await db.addTransfer(fromWalletId: AppDatabase.mainWalletId, fromCurrency: 'EUR',
        fromAmountCents: 100, toWalletId: w, toCurrency: 'EUR', toAmountCents: 100,
        date: DateTime(2026, 10, 2));
    await db.addCategory(type: EntryType.expense, name: 'Кава', icon: 'coffee', color: 1);
    await db.setSetting('local.google_email', 'me@example.com');
    await db.setSetting('local.onboarding_done', '1');

    await db.wipeAllData(resetId: 'r1');

    expect(await db.countEntries(), 0);
    expect(await db.watchTransfers().first, isEmpty);
    expect((await db.watchWallets().first).map((w) => w.id), [AppDatabase.mainWalletId]);
    expect((await db.watchCategories(EntryType.expense).first).length, 12);
    expect(await db.getSetting('local.google_email'), 'me@example.com'); // вхід зберігається
    expect(await db.getSetting('local.onboarding_done'), isNull); // вітання знову
    expect(await db.getSetting(SettingKeys.dataResetId), 'r1');
  });
}

/// Перетворює свіжу базу на базу версії 2 (до гаманців і активів): прибирає нові таблиці й колонки.
Future<void> _downgradeToV2(AppDatabase db) async {
  await db.customStatement('DROP TABLE wallets');
  await db.customStatement('DROP TABLE wallet_currencies');
  await db.customStatement('DROP TABLE transfers');
  await db.customStatement('DROP TABLE assets');
  await db.customStatement('DROP TABLE asset_trades');
  await db.customStatement('DROP TABLE belongings');
  await db.customStatement('ALTER TABLE transactions DROP COLUMN belonging_id');
  await db.customStatement("DELETE FROM categories WHERE id = 'inc-sale'");
  await db.customStatement('ALTER TABLE transactions DROP COLUMN wallet_id');
  await db.customStatement('ALTER TABLE transactions DROP COLUMN asset_id');
  await db.customStatement('ALTER TABLE transactions DROP COLUMN asset_units');
  await db.customStatement('ALTER TABLE transactions DROP COLUMN trade_id');
  await db.customStatement("DELETE FROM categories WHERE id LIKE '%-invest'");
  await db.customStatement('PRAGMA user_version = 2');
}
