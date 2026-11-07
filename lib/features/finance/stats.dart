import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../../data/rate_history.dart';
import 'ledger.dart';
import 'period.dart';

/// Сума категорії за період у EUR.
class CategoryTotal {
  const CategoryTotal(this.categoryId, this.cents, this.share);
  final String categoryId;
  final int cents;
  final double share; // 0..1
}

/// Один стовпчик / точка графіка.
class Bucket {
  const Bucket({
    required this.start,
    required this.end,
    required this.label,
    required this.incomeCents,
    required this.expenseCents,
    required this.balanceAtEndCents,
  });

  final DateTime start;
  final DateTime end; // не включно
  final String label;
  final int incomeCents;
  final int expenseCents;
  final int balanceAtEndCents;
}

enum BucketSize { day, week, month }

class PeriodStats {
  const PeriodStats({
    required this.period,
    required this.incomeCents,
    required this.expenseCents,
    required this.expenseByCategory,
    required this.incomeByCategory,
    required this.buckets,
    required this.bucketSize,
    required this.skippedCount,
    this.currency = baseCurrency,
    this.onlyCurrency = false,
  });

  final Period period;

  /// Валюта всіх сум у статистиці.
  final String currency;

  /// true — враховано лише записи в [currency], без перерахунку;
  /// false — усі записи, перераховані в EUR.
  final bool onlyCurrency;
  final int incomeCents;
  final int expenseCents;
  final List<CategoryTotal> expenseByCategory;
  final List<CategoryTotal> incomeByCategory;
  final List<Bucket> buckets;
  final BucketSize bucketSize;

  /// Записи без курсу валюти — не враховані.
  final int skippedCount;

  int get netCents => incomeCents - expenseCents;
}

/// Розмір стовпчика залежить від довжини періоду, щоб графік лишався читабельним.
BucketSize bucketSizeFor(Period p) {
  if (p.days <= 14) return BucketSize.day;
  if (p.days <= 92) return BucketSize.week;
  return BucketSize.month;
}

/// Рахує статистику за записами (без гаманців і переказів) — зручно для тестів.
/// [initialBalanceCents] — початковий баланс у EUR.
PeriodStats computeStats({
  required List<MoneyEntry> entries,
  required Period period,
  required Map<String, ExchangeRate> rates,
  RateHistory? history,
  int initialBalanceCents = 0,
  String? onlyCurrency,
  List<Transfer> transfers = const [],
  List<WalletCurrency> walletCurrencies = const [],
  String? walletId,
}) {
  return computeStatsFromMovements(
    movements: [
      if (initialBalanceCents != 0)
        Movement(
          date: Movement.initialDate,
          walletId: AppDatabase.mainWalletId,
          currency: baseCurrency,
          cents: initialBalanceCents,
          kind: MovementKind.initial,
        ),
      ...buildMovements(
        entries: entries,
        transfers: transfers,
        walletCurrencies: walletCurrencies,
      ),
    ],
    period: period,
    rates: rates,
    history: history,
    onlyCurrency: onlyCurrency,
    walletId: walletId,
  );
}

/// Рахує все для екрана статистики.
///
/// [onlyCurrency] == null — усі записи, перераховані в EUR за курсом дати запису
/// ([history]; якщо його немає — за поточним).
/// Інакше — лише рухи в цій валюті, без перерахунку.
/// [walletId] — лише один гаманець.
/// Надходження й витрати — лише записи; перекази впливають тільки на лінію балансу.
PeriodStats computeStatsFromMovements({
  required List<Movement> movements,
  required Period period,
  required Map<String, ExchangeRate> rates,
  RateHistory? history,
  String? onlyCurrency,
  String? walletId,
}) {
  final size = bucketSizeFor(period);
  final ranges = _bucketRanges(period, size);
  final income = List<int>.filled(ranges.length, 0);
  final expense = List<int>.filled(ranges.length, 0);
  final other = List<int>.filled(ranges.length, 0); // перекази
  final statOnly = List<int>.filled(ranges.length, 0);
  final expByCat = <String, int>{};
  final incByCat = <String, int>{};
  var before = 0; // баланс на початок періоду
  var skipped = 0;
  var totalIncome = 0, totalExpense = 0;

  for (final m in movements) {
    if (walletId != null && m.walletId != walletId) continue;
    if (onlyCurrency != null && m.currency != onlyCurrency) continue;
    if (onlyCurrency == null && !isFiat(m.currency)) continue;
    final v = onlyCurrency != null
        ? m.cents
        : toEurCentsOn(m.cents, m.currency, m.date, rates, history);
    if (v == null) {
      if (period.contains(m.date) &&
          !m.isTransfer &&
          m.kind != MovementKind.initial) {
        skipped++;
      }
      continue;
    }
    if (m.date.isBefore(period.start)) {
      if (m.affectsBalance) before += v;
      continue;
    }
    if (!period.contains(m.date)) continue;

    final i = _indexOf(ranges, m.date);
    // Витрата активом / прибуток від продажу — у статистиці, але не в лінії балансу.
    if (!m.affectsBalance) statOnly[i] += v;
    switch (m.kind) {
      case MovementKind.income:
        income[i] += v;
        totalIncome += v;
        incByCat[m.categoryId!] = (incByCat[m.categoryId!] ?? 0) + v;
      case MovementKind.expense:
        expense[i] -= v;
        totalExpense -= v;
        expByCat[m.categoryId!] = (expByCat[m.categoryId!] ?? 0) - v;
      case MovementKind.initial:
      case MovementKind.transferIn:
      case MovementKind.transferOut:
        other[i] += v;
    }
  }

  var running = before;
  final buckets = <Bucket>[];
  for (var i = 0; i < ranges.length; i++) {
    running += income[i] - expense[i] + other[i] - statOnly[i];
    buckets.add(
      Bucket(
        start: ranges[i].$1,
        end: ranges[i].$2,
        label: _bucketLabel(ranges[i].$1, ranges[i].$2, size),
        incomeCents: income[i],
        expenseCents: expense[i],
        balanceAtEndCents: running,
      ),
    );
  }

  return PeriodStats(
    period: period,
    incomeCents: totalIncome,
    expenseCents: totalExpense,
    expenseByCategory: _sorted(expByCat, totalExpense),
    incomeByCategory: _sorted(incByCat, totalIncome),
    buckets: buckets,
    bucketSize: size,
    skippedCount: skipped,
    currency: onlyCurrency ?? baseCurrency,
    onlyCurrency: onlyCurrency != null,
  );
}

List<CategoryTotal> _sorted(Map<String, int> byCat, int total) {
  final list = [
    for (final e in byCat.entries)
      CategoryTotal(e.key, e.value, total == 0 ? 0 : e.value / total),
  ]..sort((a, b) => b.cents.compareTo(a.cents));
  return list;
}

List<(DateTime, DateTime)> _bucketRanges(Period p, BucketSize size) {
  final out = <(DateTime, DateTime)>[];
  var cur = p.start;
  while (cur.isBefore(p.end)) {
    final DateTime next;
    switch (size) {
      case BucketSize.day:
        next = addDays(cur, 1);
      case BucketSize.week:
        // До наступного понеділка (перший і останній тижні можуть бути неповні).
        next = addDays(cur, 8 - cur.weekday);
      case BucketSize.month:
        next = DateTime(cur.year, cur.month + 1);
    }
    out.add((cur, next.isAfter(p.end) ? p.end : next));
    cur = next;
  }
  return out;
}

int _indexOf(List<(DateTime, DateTime)> ranges, DateTime d) {
  for (var i = 0; i < ranges.length; i++) {
    if (!d.isBefore(ranges[i].$1) && d.isBefore(ranges[i].$2)) return i;
  }
  return ranges.length - 1;
}

String _bucketLabel(DateTime start, DateTime end, BucketSize size) {
  switch (size) {
    case BucketSize.day:
      return DateFormat('d.MM', 'uk').format(start);
    case BucketSize.week:
      return DateFormat('d.MM', 'uk').format(start);
    case BucketSize.month:
      final m = DateFormat('LLL', 'uk').format(start).replaceAll('.', '');
      return m[0].toUpperCase() + m.substring(1);
  }
}
