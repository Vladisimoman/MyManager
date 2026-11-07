import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/rates_service.dart';

/// Звідки взялась зміна балансу.
enum MovementKind { initial, income, expense, transferIn, transferOut }

/// Одна зміна балансу: гаманець, валюта, сума зі знаком.
class Movement {
  const Movement({
    required this.date,
    required this.walletId,
    required this.currency,
    required this.cents,
    required this.kind,
    this.categoryId,
    this.affectsBalance = true,
  });

  /// Для початкового балансу — [initialDate] (раніше за будь-який запис).
  final DateTime date;
  final String walletId;
  final String currency;
  final int cents; // + надходить, − списується
  final MovementKind kind;
  final String? categoryId;

  /// false — запис лише для статистики, гроші в гаманці не змінюються:
  /// витрата активом (списується актив, а не валюта) і прибуток / збиток
  /// від продажу (гроші вже враховано в сумі продажу).
  final bool affectsBalance;

  static final initialDate = DateTime(1900);

  bool get isTransfer =>
      kind == MovementKind.transferIn || kind == MovementKind.transferOut;
}

/// Усі зміни балансів: початкові баланси валют гаманців, записи, обидві сторони
/// переказів і грошова сторона операцій з активами.
List<Movement> buildMovements({
  required List<MoneyEntry> entries,
  List<Transfer> transfers = const [],
  List<WalletCurrency> walletCurrencies = const [],
  List<AssetTrade> trades = const [],
}) {
  return [
    for (final c in walletCurrencies)
      if (!c.deleted && c.initialCents != 0)
        Movement(
          date: Movement.initialDate,
          walletId: c.walletId,
          currency: c.currency,
          cents: c.initialCents,
          kind: MovementKind.initial,
        ),
    for (final e in entries)
      if (!e.deleted)
        Movement(
          date: e.date,
          walletId: e.walletId,
          currency: e.currency,
          cents: e.type == EntryType.income ? e.amountCents : -e.amountCents,
          kind: e.type == EntryType.income ? MovementKind.income : MovementKind.expense,
          categoryId: e.categoryId,
          affectsBalance: e.assetId == null && e.tradeId == null,
        ),
    for (final t in transfers)
      if (!t.deleted) ...[
        Movement(
          date: t.date,
          walletId: t.fromWalletId,
          currency: t.fromCurrency,
          cents: -t.fromAmountCents,
          kind: MovementKind.transferOut,
        ),
        Movement(
          date: t.date,
          walletId: t.toWalletId,
          currency: t.toCurrency,
          cents: t.toAmountCents,
          kind: MovementKind.transferIn,
        ),
      ],
    // Купівля активу — гроші йдуть з гаманця; продаж — приходять. Це не витрата
    // й не надходження, а переказ «гроші ↔ актив».
    for (final t in trades)
      if (!t.deleted &&
          t.type != TradeType.move &&
          t.fiatWalletId != null &&
          t.fiatCurrency != null &&
          t.fiatCents != null)
        Movement(
          date: t.date,
          walletId: t.fiatWalletId!,
          currency: t.fiatCurrency!,
          cents: t.type == TradeType.buy ? -t.fiatCents! : t.fiatCents!,
          kind: t.type == TradeType.buy ? MovementKind.transferOut : MovementKind.transferIn,
        ),
  ];
}

/// Баланси: гаманець → валюта → центи.
Map<String, Map<String, int>> walletBalances(Iterable<Movement> movements) {
  final out = <String, Map<String, int>>{};
  for (final m in movements) {
    if (!m.affectsBalance) continue;
    final w = out[m.walletId] ??= {};
    w[m.currency] = (w[m.currency] ?? 0) + m.cents;
  }
  return out;
}

/// Сума балансів у EUR; валюти без курсу рахуються окремо ([skipped]).
({int cents, Map<String, int> skipped}) sumToEur(
  Map<String, int> byCurrency,
  Map<String, ExchangeRate> rates,
) {
  var cents = 0;
  final skipped = <String, int>{};
  for (final e in byCurrency.entries) {
    if (e.value == 0 || !isFiat(e.key)) continue;
    final eur = toEurCents(e.value, e.key, rates);
    if (eur == null) {
      skipped[e.key] = (skipped[e.key] ?? 0) + 1;
    } else {
      cents += eur;
    }
  }
  return (cents: cents, skipped: skipped);
}

/// Перерахунок суми між валютами через EUR за поточним курсом. null — немає курсу.
int? convertCents(int cents, String from, String to, Map<String, ExchangeRate> rates) {
  if (from == to) return cents;
  final eur = toEurCents(cents, from, rates);
  if (eur == null) return null;
  if (to == baseCurrency) return eur;
  final r = rates[to];
  if (r == null || r.perEur <= 0) return null;
  return (eur * r.perEur).round();
}

// ---------------- Активи (етап 8) ----------------

/// Позиція в активі: скільки є, скільки за це сплачено (ціна купівлі), де лежить.
class AssetPosition {
  AssetPosition(this.assetId);

  final String assetId;
  int units = 0; // × 10^8
  int basisCents = 0; // в обліковій валюті активу
  final unitsByWallet = <String, int>{};

  /// Середня ціна купівлі за 1 одиницю (у центах облікової валюти).
  double get avgPriceCents => units <= 0 ? 0 : basisCents * unitsScale / units;

  /// Ціна купівлі для [qtyUnits] за середньою ціною.
  int costOf(int qtyUnits) =>
      units <= 0 ? 0 : (basisCents.toDouble() * qtyUnits / units).round();

  int unitsIn(String walletId) => unitsByWallet[walletId] ?? 0;
}

/// Позиції всіх активів з операцій і витрат активом.
/// Значення витрат і продажів «заморожені» при записі, тому порядок не важливий.
Map<String, AssetPosition> assetPositions({
  required List<AssetTrade> trades,
  required List<MoneyEntry> entries,
}) {
  final out = <String, AssetPosition>{};
  AssetPosition pos(String id) => out[id] ??= AssetPosition(id);
  void addTo(AssetPosition p, String wallet, int u) =>
      p.unitsByWallet[wallet] = (p.unitsByWallet[wallet] ?? 0) + u;

  for (final t in trades) {
    if (t.deleted) continue;
    final p = pos(t.assetId);
    switch (t.type) {
      case TradeType.buy:
        p.units += t.units;
        p.basisCents += t.basisCents;
        addTo(p, t.walletId, t.units);
      case TradeType.sell:
        p.units -= t.units;
        p.basisCents -= t.basisCents;
        addTo(p, t.walletId, -t.units);
      case TradeType.move:
        addTo(p, t.walletId, -t.units);
        if (t.toWalletId != null) addTo(p, t.toWalletId!, t.units);
    }
  }
  for (final e in entries) {
    if (e.deleted || e.assetId == null || e.assetUnits == null) continue;
    final p = pos(e.assetId!);
    p.units -= e.assetUnits!;
    p.basisCents -= e.amountCents;
    addTo(p, e.walletId, -e.assetUnits!);
  }
  return out;
}

/// Активи в гаманці: assetId → кількість (лише ненульові).
Map<String, int> assetsInWallet(Map<String, AssetPosition> positions, String walletId) => {
      for (final p in positions.values)
        if (p.unitsIn(walletId) != 0) p.assetId: p.unitsIn(walletId),
    };

// ---------------- Кількість активу ----------------

/// «0,001» → 100000 (8 знаків після коми). null — некоректне.
int? parseUnits(String input) {
  final s = input.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{0,8})?$').hasMatch(s)) return null;
  final parts = s.split('.');
  final frac = (parts.length > 1 ? parts[1] : '').padRight(8, '0');
  return int.parse(parts[0]) * unitsScale + int.parse(frac);
}

/// 100000 → «0,001» (без зайвих нулів).
String unitsToInput(int units) {
  final neg = units < 0;
  final u = units.abs();
  final whole = u ~/ unitsScale;
  var frac = (u % unitsScale).toString().padLeft(8, '0').replaceFirst(RegExp(r'0+$'), '');
  final s = frac.isEmpty ? '$whole' : '$whole,$frac';
  return neg ? '-$s' : s;
}

/// «0,001 BTC», «1 250,5 USDT».
String formatUnits(int units, String code, {int sign = 0}) {
  final u = units.abs();
  final whole = NumberFormat.decimalPattern('uk').format(u ~/ unitsScale);
  final frac = (u % unitsScale).toString().padLeft(8, '0').replaceFirst(RegExp(r'0+$'), '');
  final body = '${frac.isEmpty ? whole : '$whole,$frac'} $code';
  if (sign > 0) return '+ $body';
  if (sign < 0 || units < 0) return '− $body';
  return body;
}

/// Ціна за одиницю: «98 500,00 $ за 1 BTC».
String formatUnitPrice(double priceCents, String currency) =>
    formatMoney(priceCents.round(), currency);
