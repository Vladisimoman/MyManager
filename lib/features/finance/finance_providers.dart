import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../../data/rate_history.dart';
import '../../data/rates_service.dart';
import 'ledger.dart';
import 'period.dart';
import 'stats.dart';

/// Єдиний екземпляр бази на весь додаток. У тестах підміняється базою в пам'яті.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final categoriesProvider = StreamProvider.family<List<Category>, EntryType>(
  (ref, type) => ref.watch(databaseProvider).watchCategories(type),
);

final categoryMapProvider = StreamProvider<Map<String, Category>>(
  (ref) => ref.watch(databaseProvider).watchCategoryMap(),
);

final entriesProvider = StreamProvider.family<List<MoneyEntry>, EntryType>(
  (ref, type) => ref.watch(databaseProvider).watchEntries(type),
);

final allEntriesProvider = StreamProvider<List<MoneyEntry>>(
  (ref) => ref.watch(databaseProvider).watchAllEntries(),
);

final ratesServiceProvider = Provider<RatesService>(
  (ref) => RatesService(ref.watch(databaseProvider)),
);

/// Збережені курси: валюта → скільки її за 1 EUR.
final ratesProvider = StreamProvider<Map<String, ExchangeRate>>(
  (ref) => ref.watch(databaseProvider).watchRates(),
);

/// Курси за минулі дні (етап 10): записи перераховуються за курсом своєї дати.
final rateHistoryProvider = StreamProvider<RateHistory>(
  (ref) => ref.watch(databaseProvider).watchRateHistory().map(RateHistory.new),
);

// ---------- Гаманці (етап 7) ----------

/// Усі гаманці, включно з архівними (не видалені).
final walletsProvider = StreamProvider<List<Wallet>>(
  (ref) => ref.watch(databaseProvider).watchWallets(),
);

final walletMapProvider = Provider<Map<String, Wallet>>((ref) {
  final list = ref.watch(walletsProvider).value ?? const [];
  return {for (final w in list) w.id: w};
});

final walletCurrenciesProvider = StreamProvider<List<WalletCurrency>>(
  (ref) => ref.watch(databaseProvider).watchWalletCurrencies(),
);

final transfersProvider = StreamProvider<List<Transfer>>(
  (ref) => ref.watch(databaseProvider).watchTransfers(),
);

// ---------- Активи (етап 8) ----------

final assetsProvider = StreamProvider<List<Asset>>(
  (ref) => ref.watch(databaseProvider).watchAssets(),
);

final assetMapProvider = Provider<Map<String, Asset>>((ref) {
  final list = ref.watch(assetsProvider).value ?? const [];
  return {for (final a in list) a.id: a};
});

final tradesProvider = StreamProvider<List<AssetTrade>>(
  (ref) => ref.watch(databaseProvider).watchTrades(),
);

/// Позиції активів: кількість, ціна купівлі, розподіл по гаманцях.
final assetPositionsProvider = Provider<Map<String, AssetPosition>>((ref) {
  return assetPositions(
    trades: ref.watch(tradesProvider).value ?? const [],
    entries: ref.watch(allEntriesProvider).value ?? const [],
  );
});

/// Усі зміни балансів (початкові баланси, записи, перекази, гроші в операціях з активами).
final movementsProvider = Provider<AsyncValue<List<Movement>>>((ref) {
  final entries = ref.watch(allEntriesProvider);
  final transfers = ref.watch(transfersProvider);
  final currencies = ref.watch(walletCurrenciesProvider);
  final trades = ref.watch(tradesProvider);
  for (final v in [entries, transfers, currencies, trades]) {
    if (v.hasError) return AsyncValue.error(v.error!, v.stackTrace!);
  }
  if (!entries.hasValue || !transfers.hasValue || !currencies.hasValue || !trades.hasValue) {
    return const AsyncValue.loading();
  }
  return AsyncValue.data(
    buildMovements(
      entries: entries.requireValue,
      transfers: transfers.requireValue,
      walletCurrencies: currencies.requireValue,
      trades: trades.requireValue,
    ),
  );
});

/// Баланси: гаманець → валюта → центи. Валюти гаманця з нульовим балансом теж є.
final walletBalancesProvider = Provider<Map<String, Map<String, int>>>((ref) {
  final balances = walletBalances(
    ref.watch(movementsProvider).value ?? const [],
  );
  for (final c
      in ref.watch(walletCurrenciesProvider).value ??
          const <WalletCurrency>[]) {
    (balances[c.walletId] ??= {}).putIfAbsent(c.currency, () => 0);
  }
  return balances;
});

/// Фільтр за гаманцем у списках і статистиці: null — усі гаманці.
class WalletFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? walletId) => state = walletId;
}

final walletFilterProvider = NotifierProvider<WalletFilterNotifier, String?>(
  WalletFilterNotifier.new,
);

// ---------- Загальний баланс ----------

/// Загальний баланс у EUR: лише фіатні гроші всіх гаманців.
/// Валюти без курсу рахуються окремо як пропущені.
class BalanceSummary {
  const BalanceSummary({required this.cents, required this.skippedByCurrency});

  final int cents;
  final Map<String, int> skippedByCurrency;

  int get skippedCount => skippedByCurrency.values.fold(0, (a, b) => a + b);
}

BalanceSummary computeBalance(
  List<Movement> movements,
  Map<String, ExchangeRate> rates,
) {
  final byCurrency = <String, int>{};
  for (final m in movements) {
    if (!m.affectsBalance) continue;
    byCurrency[m.currency] = (byCurrency[m.currency] ?? 0) + m.cents;
  }
  final sum = sumToEur(byCurrency, rates);
  return BalanceSummary(cents: sum.cents, skippedByCurrency: sum.skipped);
}

final balanceProvider = Provider<AsyncValue<BalanceSummary>>((ref) {
  final movements = ref.watch(movementsProvider);
  final rates = ref.watch(ratesProvider);
  for (final v in [movements, rates]) {
    if (v.hasError) return AsyncValue.error(v.error!, v.stackTrace!);
  }
  if (!movements.hasValue || !rates.hasValue) return const AsyncValue.loading();
  return AsyncValue.data(
    computeBalance(movements.requireValue, rates.requireValue),
  );
});

// ---------- Період і статистика (етап 4) ----------

/// Вибраний період — спільний для статистики й списків записів.
class PeriodNotifier extends Notifier<Period> {
  @override
  Period build() => Period.of(PeriodKind.month, DateTime.now());

  void setKind(PeriodKind kind) => state = Period.of(kind, DateTime.now());
  void shift(int step) => state = state.shift(step);
  void setCustom(DateTime first, DateTime last) =>
      state = Period.custom(first, last);
}

final periodProvider = NotifierProvider<PeriodNotifier, Period>(
  PeriodNotifier.new,
);

/// Фільтр валюти в статистиці: null — усі валюти разом (у EUR).
class StatsCurrencyNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? currency) => state = currency;
}

final statsCurrencyProvider = NotifierProvider<StatsCurrencyNotifier, String?>(
  StatsCurrencyNotifier.new,
);

final statsProvider = Provider<AsyncValue<PeriodStats>>((ref) {
  final movements = ref.watch(movementsProvider);
  final rates = ref.watch(ratesProvider);
  for (final v in [movements, rates]) {
    if (v.hasError) return AsyncValue.error(v.error!, v.stackTrace!);
  }
  if (!movements.hasValue || !rates.hasValue) return const AsyncValue.loading();
  return AsyncValue.data(
    computeStatsFromMovements(
      movements: movements.requireValue,
      period: ref.watch(periodProvider),
      rates: rates.requireValue,
      history: ref.watch(rateHistoryProvider).value,
      onlyCurrency: ref.watch(statsCurrencyProvider),
      walletId: ref.watch(walletFilterProvider),
    ),
  );
});
