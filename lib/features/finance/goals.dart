import '../../data/database.dart';

/// Цілі накопичення (1.15): скільки зібрано й скільки відкладати на місяць.

class GoalProgress {
  const GoalProgress(this.goal, this.savedCents);

  final Goal goal;

  /// Сума внесків (у валюті цілі).
  final int savedCents;

  int get leftCents =>
      (goal.targetCents - savedCents).clamp(0, goal.targetCents);
  double get share => goal.targetCents <= 0 ? 0 : savedCents / goal.targetCents;
  bool get reached => savedCents >= goal.targetCents;

  /// Скільки повних і неповних місяців до терміну (мінімум 1). null — терміну немає
  /// або він минув.
  int? monthsLeft(DateTime today) {
    final d = goal.deadline;
    if (d == null) return null;
    final t = DateTime(today.year, today.month, today.day);
    if (d.isBefore(t)) return null;
    var months = (d.year - t.year) * 12 + d.month - t.month;
    if (d.day > t.day) months++;
    return months < 1 ? 1 : months;
  }

  bool overdue(DateTime today) {
    final d = goal.deadline;
    return d != null &&
        !reached &&
        d.isBefore(DateTime(today.year, today.month, today.day));
  }

  /// Скільки відкладати щомісяця, щоб встигнути (округлено вгору до цента).
  int? perMonthCents(DateTime today) {
    final m = monthsLeft(today);
    if (m == null || reached) return null;
    return (leftCents + m - 1) ~/ m;
  }
}

/// Прогрес кожної цілі.
Map<String, GoalProgress> goalProgress(
  Iterable<Goal> goals,
  Iterable<GoalContribution> contributions,
) {
  final saved = <String, int>{};
  for (final c in contributions) {
    if (c.deleted) continue;
    saved[c.goalId] = (saved[c.goalId] ?? 0) + c.amountCents;
  }
  return {
    for (final g in goals)
      if (!g.deleted) g.id: GoalProgress(g, saved[g.id] ?? 0),
  };
}
