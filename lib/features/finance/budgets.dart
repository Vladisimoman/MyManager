import '../../data/database.dart';
import '../../data/rate_history.dart';
import 'period.dart';

/// Бюджети (етап 11): скільки витрачено за місяць у валюті бюджету.

/// Стан бюджету: зелений, жовтий (від 80 %), червоний (перевищено).
enum BudgetLevel { ok, warning, over }

const budgetWarningShare = 0.8;

class BudgetUsage {
  const BudgetUsage({
    required this.budget,
    required this.spentCents,
    required this.skipped,
  });

  final Budget budget;

  /// Витрачено в місяці, у валюті бюджету.
  final int spentCents;

  /// Записи без курсу — не враховані.
  final int skipped;

  int get limitCents => budget.limitCents;
  int get leftCents => limitCents - spentCents;
  double get share => limitCents <= 0 ? 0 : spentCents / limitCents;

  BudgetLevel get level => levelFor(spentCents, limitCents);

  static BudgetLevel levelFor(int spent, int limit) {
    if (spent > limit) return BudgetLevel.over;
    if (limit > 0 && spent >= limit * budgetWarningShare) {
      return BudgetLevel.warning;
    }
    return BudgetLevel.ok;
  }
}

/// Чи рахується запис у бюджет: витрата, не видалена, у місяці й (для бюджету
/// категорії) у цій категорії. Загальний бюджет — усі витрати.
bool countsFor(Budget b, MoneyEntry e, Period month) =>
    !e.deleted &&
    e.type == EntryType.expense &&
    month.contains(e.date) &&
    (b.categoryId == null || e.categoryId == b.categoryId);

/// Витрати місяця для бюджету. [excludeEntryId] — запис, який зараз редагується.
BudgetUsage budgetUsage({
  required Budget budget,
  required Iterable<MoneyEntry> entries,
  required Period month,
  required Map<String, ExchangeRate> rates,
  RateHistory? history,
  String? excludeEntryId,
}) {
  var spent = 0, skipped = 0;
  for (final e in entries) {
    if (e.id == excludeEntryId || !countsFor(budget, e, month)) continue;
    final v = convertCentsOn(
      e.amountCents,
      e.currency,
      budget.currency,
      e.date,
      rates,
      history,
    );
    if (v == null) {
      skipped++;
    } else {
      spent += v;
    }
  }
  return BudgetUsage(budget: budget, spentCents: spent, skipped: skipped);
}

/// Порядок на екрані: спершу загальний, далі категорії — найбільш заповнені зверху.
List<BudgetUsage> sortedUsages(List<BudgetUsage> list) {
  final total = list.where((u) => u.budget.categoryId == null);
  final cats = list.where((u) => u.budget.categoryId != null).toList()
    ..sort((a, b) => b.share.compareTo(a.share));
  return [...total, ...cats];
}

/// Що буде з бюджетами, якщо додати витрату (для попередження у формі).
class BudgetPreview {
  const BudgetPreview(this.budget, this.beforeCents, this.afterCents);
  final Budget budget;
  final int beforeCents;
  final int afterCents;

  BudgetLevel get level => BudgetUsage.levelFor(afterCents, budget.limitCents);
  int get overCents => afterCents - budget.limitCents;
}

/// Попередження для нової / зміненої витрати: бюджети, які стануть жовтими чи червоними.
List<BudgetPreview> previewExpense({
  required List<Budget> budgets,
  required Iterable<MoneyEntry> entries,
  required String categoryId,
  required int amountCents,
  required String currency,
  required DateTime date,
  required Map<String, ExchangeRate> rates,
  RateHistory? history,
  String? excludeEntryId,
}) {
  final month = Period.of(PeriodKind.month, date);
  final out = <BudgetPreview>[];
  for (final b in budgets) {
    if (b.deleted || (b.categoryId != null && b.categoryId != categoryId)) {
      continue;
    }
    final add = convertCentsOn(
      amountCents,
      currency,
      b.currency,
      date,
      rates,
      history,
    );
    if (add == null) continue;
    final u = budgetUsage(
      budget: b,
      entries: entries,
      month: month,
      rates: rates,
      history: history,
      excludeEntryId: excludeEntryId,
    );
    final p = BudgetPreview(b, u.spentCents, u.spentCents + add);
    if (p.level != BudgetLevel.ok) out.add(p);
  }
  // Спершу бюджет категорії — він конкретніший.
  out.sort(
    (a, b) =>
        (a.budget.categoryId == null ? 1 : 0) -
        (b.budget.categoryId == null ? 1 : 0),
  );
  return out;
}
