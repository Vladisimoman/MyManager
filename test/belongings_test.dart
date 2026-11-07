import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/ledger.dart';
import 'package:my_manager/features/finance/period.dart';
import 'package:my_manager/features/finance/stats.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 9: пасиви — речі, якими володієш.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('uk'));

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const cash = AppDatabase.mainWalletId;
  final day = DateTime(2026, 10, 10);

  Future<List<MoneyEntry>> live() async =>
      (await db.watchAllEntries().first).where((e) => !e.deleted).toList();

  Future<int> eurBalance() async {
    final m = buildMovements(
      entries: await db.watchAllEntries().first,
      walletCurrencies: await db.watchWalletCurrencies().first,
    );
    return walletBalances(m)[cash]?['EUR'] ?? 0;
  }

  Future<String> phone({bool expense = true}) => db.saveBelonging(
        name: ' Телефон ',
        icon: 'phone',
        priceCents: 50000,
        currency: 'EUR',
        purchaseDate: day,
        walletId: cash,
        categoryId: 'exp-other',
        recordExpense: expense,
      );

  setUp(() async => db.setWalletCurrency(cash, 'EUR', 100000));

  test('купівля речі — витрата з гаманця', () async {
    final id = await phone();
    final b = (await db.watchBelongings().first).single;
    expect(b.name, 'Телефон');
    final e = (await live()).single;
    expect(e.id, AppDatabase.belongingBuyEntryId(id));
    expect(e.type, EntryType.expense);
    expect(e.amountCents, 50000);
    expect(e.belongingId, id);
    expect(e.note, 'Телефон');
    expect(await eurBalance(), 50000);
  });

  test('річ, куплена раніше, — без витрати; перемикач додає витрату', () async {
    final id = await phone(expense: false);
    expect(await live(), isEmpty);
    expect(await eurBalance(), 100000);
    await db.saveBelonging(id: id, name: 'Телефон', icon: 'phone', priceCents: 50000,
        currency: 'EUR', purchaseDate: day, walletId: cash, categoryId: 'exp-other');
    expect((await live()).single.amountCents, 50000);
    // І назад: витрата зникає.
    await db.saveBelonging(id: id, name: 'Телефон', icon: 'phone', priceCents: 50000,
        currency: 'EUR', purchaseDate: day, walletId: cash, categoryId: 'exp-other',
        recordExpense: false);
    expect(await live(), isEmpty);
  });

  test('редагування ціни змінює витрату, а не створює нову', () async {
    final id = await phone();
    await db.saveBelonging(id: id, name: 'Телефон', icon: 'phone', priceCents: 45000,
        currency: 'EUR', purchaseDate: day, walletId: cash, categoryId: 'exp-fun');
    final e = (await live()).single;
    expect(e.amountCents, 45000);
    expect(e.categoryId, 'exp-fun');
  });

  test('продаж — уся сума в надходження «Продаж речей»; скасування продажу', () async {
    final id = await phone();
    await db.sellBelonging(id, saleCents: 30000, currency: 'EUR', walletId: cash,
        date: DateTime(2026, 10, 20));
    final b = (await db.watchBelongings().first).single;
    expect(b.saleCents, 30000);
    final sale = (await live()).firstWhere((e) => e.type == EntryType.income);
    expect(sale.id, AppDatabase.belongingSaleEntryId(id));
    expect(sale.categoryId, 'inc-sale');
    expect(sale.amountCents, 30000);
    expect(await eurBalance(), 100000 - 50000 + 30000);

    final stats = computeStatsFromMovements(
      movements: buildMovements(entries: await db.watchAllEntries().first),
      period: Period.of(PeriodKind.month, day),
      rates: const {},
    );
    expect(stats.expenseCents, 50000);
    expect(stats.incomeCents, 30000);

    await db.cancelBelongingSale(id);
    expect((await live()).length, 1);
    expect((await db.watchBelongings().first).single.saleCents, isNull);
  });

  test('видалення речі прибирає її записи, відновлення — повертає', () async {
    final id = await phone();
    await db.sellBelonging(id, saleCents: 30000, currency: 'EUR', walletId: cash, date: day);
    await db.setBelongingDeleted(id, true);
    expect(await db.watchBelongings().first, isEmpty);
    expect(await live(), isEmpty);
    expect(await eurBalance(), 100000);
    await db.setBelongingDeleted(id, false);
    expect((await live()).length, 2);
  });

  test('синхронізація: річ і її записи на іншому пристрої без дублів', () async {
    final id = await phone();
    await db.sellBelonging(id, saleCents: 30000, currency: 'EUR', walletId: cash, date: day);
    final text = (await db.exportSnapshot()).encode();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.mergeSnapshot(FinanceSnapshot.decode(text));
    await other.mergeSnapshot(FinanceSnapshot.decode(text)); // повторно — без змін
    final b = (await other.watchBelongings().first).single;
    expect(b.name, 'Телефон');
    expect(b.saleCents, 30000);
    expect(b.recordExpense, isTrue);
    final entries = await other.watchAllEntries().first;
    expect(entries.length, 2);
    expect(entries.every((e) => e.belongingId == id), isTrue);
  });

  test('оновлення з версії 4 (етап 8): пасиви й «Продаж речей» з\'являються', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v4.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
        categoryId: 'exp-groceries', date: day);
    await old.customStatement('DROP TABLE belongings');
    await old.customStatement('ALTER TABLE transactions DROP COLUMN belonging_id');
    await old.customStatement("DELETE FROM categories WHERE id = 'inc-sale'");
    await old.customStatement('PRAGMA user_version = 4');
    await old.close();

    final db5 = AppDatabase(NativeDatabase(file));
    expect((await db5.watchAllEntries().first).single.amountCents, 4590);
    expect(await db5.watchBelongings().first, isEmpty);
    expect((await db5.watchCategories(EntryType.income).first).map((c) => c.id),
        contains('inc-sale'));
    await db5.close();
    await dir.delete(recursive: true);
  });

  test('видалення всіх даних прибирає й речі', () async {
    await phone();
    await db.wipeAllData(resetId: 'x');
    expect(await db.watchBelongings().first, isEmpty);
  });
}
