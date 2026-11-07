import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/finance_providers.dart';
import 'package:my_manager/features/finance/capital.dart';
import 'package:my_manager/features/finance/ledger.dart';
import 'package:my_manager/features/finance/period.dart';
import 'package:my_manager/features/finance/stats.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 8: активи (крипта, акції) — купівля, продаж, переказ, витрата активом.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  setUpAll(() => initializeDateFormatting('uk'));
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  const cash = AppDatabase.mainWalletId;
  final day = DateTime(2026, 10, 10);

  Future<({List<MoneyEntry> entries, List<AssetTrade> trades, List<WalletCurrency> wc})>
      load() async => (
            entries: await db.watchAllEntries().first,
            trades: await db.watchTrades().first,
            wc: await db.watchWalletCurrencies().first,
          );

  Future<Map<String, AssetPosition>> positions() async {
    final d = await load();
    return assetPositions(trades: d.trades, entries: d.entries);
  }

  Future<Map<String, int>> fiat(String wallet) async {
    final d = await load();
    return walletBalances(buildMovements(
      entries: d.entries,
      walletCurrencies: d.wc,
      trades: d.trades,
    ))[wallet] ?? const {};
  }

  /// Гаманець «Біржа» з USD 1000 і актив BTC (облік у USD).
  Future<({String exchange, String btc})> setup() async {
    final exchange = await db.addWallet(name: 'Біржа', icon: 'crypto', color: 1);
    await db.setWalletCurrency(exchange, 'USD', 100000);
    final btc = await db.addAsset(
        code: 'btc', name: 'Bitcoin', kind: AssetKind.crypto, basisCurrency: 'USD');
    return (exchange: exchange, btc: btc);
  }

  test('кількість: розбір і формат з 8 знаками', () {
    expect(parseUnits('0,001'), 100000);
    expect(parseUnits('1.5'), 150000000);
    expect(parseUnits('0,123456789'), isNull); // 9 знаків — забагато
    expect(parseUnits('abc'), isNull);
    expect(unitsToInput(100000), '0,001');
    expect(unitsToInput(2 * unitsScale), '2');
    expect(formatUnits(150000000, 'BTC').replaceAll(' ', ' '), '1,5 BTC');
    expect(formatUnits(1000000, 'BTC', sign: -1), '− 0,01 BTC');
  });

  test('купівля: гроші йдуть з гаманця, не витрата; актив з\'являється', () async {
    final s = await setup();
    expect(await db.watchAssets().first.then((l) => l.single.code), 'BTC');

    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: 10000000, // 0,1 BTC
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);

    expect((await fiat(s.exchange))['USD'], 100000 - 10000);
    final p = (await positions())[s.btc]!;
    expect(p.units, 10000000);
    expect(p.basisCents, 10000);
    expect(p.unitsIn(s.exchange), 10000000);
    expect(p.avgPriceCents, 100000); // 1000 $ за 1 BTC

    // У статистиці купівля — не витрата.
    final d = await load();
    final stats = computeStatsFromMovements(
      movements: buildMovements(entries: d.entries, walletCurrencies: d.wc, trades: d.trades),
      period: Period.of(PeriodKind.month, day),
      rates: const {},
    );
    expect(stats.expenseCents, 0);
  });

  test('кілька купівель підсумовуються, середня ціна', () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 30000, basisCents: 30000, date: day);
    final p = (await positions())[s.btc]!;
    expect(p.units, 2 * unitsScale);
    expect(p.basisCents, 40000);
    expect(p.costOf(unitsScale ~/ 2), 10000); // 0,5 за середньою 200 $
  });

  test('витрата активом: куртка за 0,01 BTC → витрата 10 \$, BTC списано, долари на місці',
      () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: 10000000,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);
    final pos = (await positions())[s.btc]!;
    final cost = pos.costOf(1000000);
    expect(cost, 1000);

    await db.addEntry(type: EntryType.expense, amountCents: cost, currency: 'USD',
        categoryId: 'exp-clothes', date: day, walletId: s.exchange,
        assetId: s.btc, assetUnits: 1000000);

    expect((await fiat(s.exchange))['USD'], 90000); // долари не чіпаємо
    final p = (await positions())[s.btc]!;
    expect(p.units, 9000000);
    expect(p.basisCents, 9000);

    final d = await load();
    final stats = computeStatsFromMovements(
      movements: buildMovements(entries: d.entries, walletCurrencies: d.wc, trades: d.trades),
      period: Period.of(PeriodKind.month, day),
      rates: const {},
      onlyCurrency: 'USD',
    );
    expect(stats.expenseCents, 1000);
  });

  test('продаж з прибутком: різниця йде в надходження, баланс — сума продажу', () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: 10000000,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);
    // Продаємо половину (собівартість 50 $) за 80 $ → прибуток 30 $.
    final tradeId = await db.saveTrade(type: TradeType.sell, assetId: s.btc, units: 5000000,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 8000, basisCents: 5000, pnlCents: 3000, date: day, pnlNote: 'Продаж BTC');

    expect((await fiat(s.exchange))['USD'], 100000 - 10000 + 8000);
    final linked = (await db.watchAllEntries().first).single;
    expect(linked.type, EntryType.income);
    expect(linked.categoryId, 'inc-invest');
    expect(linked.amountCents, 3000);
    expect(linked.tradeId, tradeId);
    final p = (await positions())[s.btc]!;
    expect(p.units, 5000000);
    expect(p.basisCents, 5000);

    // Редагування продажу на збиток: той самий запис стає витратою.
    await db.saveTrade(id: tradeId, type: TradeType.sell, assetId: s.btc, units: 5000000,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 4000, basisCents: 5000, pnlCents: -1000, date: day);
    final e = (await db.watchAllEntries().first).single;
    expect(e.type, EntryType.expense);
    expect(e.categoryId, 'exp-invest');
    expect(e.amountCents, 1000);

    // Без різниці — записів прибутку / збитку немає.
    await db.saveTrade(id: tradeId, type: TradeType.sell, assetId: s.btc, units: 5000000,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 5000, basisCents: 5000, date: day);
    expect(await db.watchAllEntries().first, isEmpty);

    // Видалення продажу повертає актив і прибирає гроші.
    await db.setTradeDeleted(tradeId, true);
    expect((await positions())[s.btc]!.units, 10000000);
    expect((await fiat(s.exchange))['USD'], 90000);
  });

  test('видалення продажу ховає й пов\'язаний прибуток, відновлення — повертає', () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);
    final id = await db.saveTrade(type: TradeType.sell, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 15000, basisCents: 10000, pnlCents: 5000, date: day);
    expect((await db.watchAllEntries().first).length, 1);
    await db.setTradeDeleted(id, true);
    expect(await db.watchAllEntries().first, isEmpty);
    await db.setTradeDeleted(id, false);
    expect((await db.watchAllEntries().first).single.amountCents, 5000);
  });

  test('переказ активу між гаманцями не змінює кількість і собівартість', () async {
    final s = await setup();
    final cold = await db.addWallet(name: 'Холодний', icon: 'crypto', color: 2);
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);
    await db.saveTrade(type: TradeType.move, assetId: s.btc, units: unitsScale ~/ 4,
        walletId: s.exchange, toWalletId: cold, date: day);
    final p = (await positions())[s.btc]!;
    expect(p.units, unitsScale);
    expect(p.basisCents, 10000);
    expect(assetsInWallet(await positions(), cold), {s.btc: unitsScale ~/ 4});
    expect(assetsInWallet(await positions(), s.exchange), {s.btc: unitsScale * 3 ~/ 4});
    expect((await fiat(cold)), isEmpty); // жодних грошей
  });

  test('крипта не входить у загальний баланс', () async {
    final s = await setup();
    await db.setWalletCurrency(cash, 'EUR', 0);
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 100000, basisCents: 100000, date: day);
    final d = await load();
    final b = computeBalance(
      buildMovements(entries: d.entries, walletCurrencies: d.wc, trades: d.trades),
      const {},
    );
    expect(b.cents, 0); // USD 1000 витрачено на BTC, BTC у баланс не йде
  });

  test('синхронізація: активи й операції переходять на інший пристрій', () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day, note: 'перша');
    await db.addEntry(type: EntryType.expense, amountCents: 1000, currency: 'USD',
        categoryId: 'exp-clothes', date: day, walletId: s.exchange,
        assetId: s.btc, assetUnits: 10000000);

    final json = (await db.exportSnapshot()).encode();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.mergeSnapshot(FinanceSnapshot.decode(json));

    final a = (await other.watchAssets().first).single;
    expect(a.code, 'BTC');
    expect(a.kind, AssetKind.crypto);
    final t = (await other.watchTrades().first).single;
    expect(t.note, 'перша');
    expect(t.basisCents, 10000);
    final e = (await other.watchAllEntries().first).single;
    expect(e.assetId, s.btc);
    expect(e.assetUnits, 10000000);
    final p = assetPositions(
      trades: await other.watchTrades().first,
      entries: await other.watchAllEntries().first,
    )[s.btc]!;
    expect(p.units, 90000000);
  });

  test('оновлення з версії 3 (етап 7): з\'являються активи, записи на місці', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v3.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
        categoryId: 'exp-groceries', date: day);
    await old.customStatement('DROP TABLE assets');
    await old.customStatement('DROP TABLE asset_trades');
    await old.customStatement('DROP TABLE belongings');
    await old.customStatement('ALTER TABLE transactions DROP COLUMN belonging_id');
    await old.customStatement("DELETE FROM categories WHERE id = 'inc-sale'");
    await old.customStatement('ALTER TABLE transactions DROP COLUMN asset_id');
    await old.customStatement('ALTER TABLE transactions DROP COLUMN asset_units');
    await old.customStatement('ALTER TABLE transactions DROP COLUMN trade_id');
    await old.customStatement("DELETE FROM categories WHERE id LIKE '%-invest'");
    await old.customStatement('PRAGMA user_version = 3');
    await old.close();

    final db3 = AppDatabase(NativeDatabase(file));
    expect((await db3.watchAllEntries().first).single.amountCents, 4590);
    expect(await db3.watchAssets().first, isEmpty);
    final ids = (await db3.select(db3.categories).get()).map((c) => c.id).toSet();
    expect(ids, containsAll(['inc-invest', 'exp-invest']));
    // Службові категорії приховані — не показуються під час додавання записів.
    expect((await db3.watchCategories(EntryType.income).first).map((c) => c.id),
        isNot(contains('inc-invest')));
    await db3.close();
    await dir.delete(recursive: true);
  });

  test('актив, що вже був: гроші не списуються, прибуток при продажі — від ціни купівлі', () async {
    final s = await setup();
    // 0,1 BTC куплено колись за 100 $ — без гаманця грошей.
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: 10000000,
        walletId: s.exchange, fiatCurrency: 'USD', fiatCents: 10000, basisCents: 10000, date: day);
    expect((await fiat(s.exchange))['USD'], 100000); // баланс без змін
    final p = (await positions())[s.btc]!;
    expect(p.units, 10000000);
    expect(p.basisCents, 10000);

    await db.saveTrade(type: TradeType.sell, assetId: s.btc, units: 10000000,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 25000, basisCents: 10000, pnlCents: 15000, date: day);
    expect((await fiat(s.exchange))['USD'], 125000);
    expect((await db.watchAllEntries().first).single.amountCents, 15000);
    expect(await db.isWalletUsed(s.exchange), isTrue);
  });

  test('капітал: гроші + активи + непродані речі за ціною купівлі', () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatCurrency: 'USD', fiatCents: 12500, basisCents: 12500, date: day);
    await db.saveBelonging(name: 'Телефон', icon: 'phone', priceCents: 50000, currency: 'EUR',
        purchaseDate: day, walletId: cash, categoryId: 'exp-other', recordExpense: false);
    final tv = await db.saveBelonging(name: 'ТВ', icon: 'tv', priceCents: 70000, currency: 'EUR',
        purchaseDate: day, walletId: cash, categoryId: 'exp-other', recordExpense: false);
    await db.sellBelonging(tv, saleCents: 1, currency: 'EUR', walletId: cash, date: day);
    final rates = {
      'USD': ExchangeRate(currency: 'USD', perEur: 1.25, rateDate: '2026-10-28',
          source: 'ECB', fetchedAt: DateTime(2026, 10, 28)),
    };
    final c = computeCapital(
      positions: await positions(),
      assets: {for (final a in await db.watchAssets().first) a.id: a},
      belongings: await db.watchBelongings().first,
      rates: rates,
    );
    expect(c.assetsCents, 10000); // 125 $ / 1,25
    expect(c.belongingsCents, 50000); // продані не враховуються
    expect(c.missing, isEmpty);
    expect(computeCapital(positions: await positions(),
        assets: {for (final a in await db.watchAssets().first) a.id: a},
        belongings: const [], rates: const {}).missing, {'USD'});
  });

  test('видалення всіх даних прибирає й активи', () async {
    final s = await setup();
    await db.saveTrade(type: TradeType.buy, assetId: s.btc, units: unitsScale,
        walletId: s.exchange, fiatWalletId: s.exchange, fiatCurrency: 'USD',
        fiatCents: 10000, basisCents: 10000, date: day);
    await db.wipeAllData(resetId: 'x');
    expect(await db.watchAssets().first, isEmpty);
    expect(await db.watchTrades().first, isEmpty);
  });
}
