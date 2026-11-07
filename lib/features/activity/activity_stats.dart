import 'package:intl/intl.dart';

import '../../data/database.dart';
import 'activity_logic.dart';

/// Статистика Activity (етап 15): скільки часу на що й наскільки продуктивно.

enum ActivityPeriodKind { day, week, month, custom }

/// Проміжок [start, end) у локальних днях.
class ActivityPeriod {
  const ActivityPeriod._(this.kind, this.start, this.end);

  final ActivityPeriodKind kind;
  final DateTime start;
  final DateTime end;

  factory ActivityPeriod.of(ActivityPeriodKind kind, DateTime anchor) {
    final d = dayStart(anchor);
    switch (kind) {
      case ActivityPeriodKind.day:
      case ActivityPeriodKind.custom:
        return ActivityPeriod._(kind, d, nextDay(d));
      case ActivityPeriodKind.week:
        final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
        return ActivityPeriod._(
          kind,
          monday,
          DateTime(monday.year, monday.month, monday.day + 7),
        );
      case ActivityPeriodKind.month:
        return ActivityPeriod._(
          kind,
          DateTime(d.year, d.month),
          DateTime(d.year, d.month + 1),
        );
    }
  }

  /// Свій проміжок: обидві дати включно.
  factory ActivityPeriod.custom(DateTime first, DateTime last) =>
      ActivityPeriod._(
        ActivityPeriodKind.custom,
        dayStart(first),
        nextDay(last),
      );

  int get days => _daysBetween(start, end);

  /// Попередній (-1) / наступний (+1) період того ж типу (свій — на ту саму довжину).
  ActivityPeriod shift(int step) => switch (kind) {
    ActivityPeriodKind.day => ActivityPeriod.of(
      kind,
      DateTime(start.year, start.month, start.day + step),
    ),
    ActivityPeriodKind.week => ActivityPeriod.of(
      kind,
      DateTime(start.year, start.month, start.day + 7 * step),
    ),
    ActivityPeriodKind.month => ActivityPeriod.of(
      kind,
      DateTime(start.year, start.month + step),
    ),
    ActivityPeriodKind.custom => ActivityPeriod._(
      kind,
      DateTime(start.year, start.month, start.day + days * step),
      DateTime(end.year, end.month, end.day + days * step),
    ),
  };

  String get label {
    final last = DateTime(end.year, end.month, end.day - 1);
    switch (kind) {
      case ActivityPeriodKind.day:
        return DateFormat('EEEE, d MMMM', 'uk').format(start);
      case ActivityPeriodKind.month:
        final s = DateFormat('LLLL y', 'uk').format(start);
        return s[0].toUpperCase() + s.substring(1);
      case ActivityPeriodKind.week:
      case ActivityPeriodKind.custom:
        if (start == last) return DateFormat('d MMMM y', 'uk').format(start);
        final sameYear = start.year == last.year;
        return '${DateFormat(sameYear ? 'd MMM' : 'd MMM y', 'uk').format(start)} – '
            '${DateFormat('d MMM y', 'uk').format(last)}';
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ActivityPeriod &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Скільки часу категорія зайняла за період.
class CategoryTime {
  const CategoryTime(this.categoryId, this.duration, this.count);
  final String categoryId;
  final Duration duration;

  /// Скільки записів (активностей) за період.
  final int count;
}

class DayTime {
  const DayTime(this.day, this.byKind);
  final DateTime day;
  final Map<ActivityKind, Duration> byKind;

  Duration get total => byKind.values.fold(Duration.zero, (a, b) => a + b);
}

class ActivityStats {
  const ActivityStats({
    required this.period,
    required this.byCategory,
    required this.byKind,
    required this.days,
    required this.elapsedDays,
  });

  final ActivityPeriod period;

  /// Від найбільшого.
  final List<CategoryTime> byCategory;
  final Map<ActivityKind, Duration> byKind;

  /// По днях періоду (для стовпчиків).
  final List<DayTime> days;

  /// Скільки днів періоду вже минуло (для середнього; сьогодні — враховано).
  final int elapsedDays;

  Duration get total =>
      byCategory.fold(Duration.zero, (a, c) => a + c.duration);

  Duration timeOf(String categoryId) {
    for (final c in byCategory) {
      if (c.categoryId == categoryId) return c.duration;
    }
    return Duration.zero;
  }

  Duration averagePerDay(Duration d) => elapsedDays <= 0
      ? Duration.zero
      : Duration(seconds: d.inSeconds ~/ elapsedDays);

  /// Частка корисного серед усього записаного (0…1).
  double share(ActivityKind k) => total.inSeconds == 0
      ? 0
      : (byKind[k] ?? Duration.zero).inSeconds / total.inSeconds;
}

/// Рахує статистику: активності обрізаються межами періоду й «зараз»
/// (сон через північ ділиться між днями), таймер — до [now].
ActivityStats computeActivityStats({
  required Iterable<Activity> activities,
  required Map<String, ActivityCategory> categories,
  required ActivityPeriod period,
  required DateTime now,
}) {
  final limit = now.isBefore(period.end) ? now : period.end;
  final byCat = <String, Duration>{};
  final counts = <String, int>{};
  final byKind = <ActivityKind, Duration>{};
  final dayCount = period.days;
  final perDay = List.generate(dayCount, (_) => <ActivityKind, Duration>{});

  for (final a in activities) {
    if (a.deleted) continue;
    var s = a.start;
    var e = a.end ?? now;
    if (s.isBefore(period.start)) s = period.start;
    if (e.isAfter(limit)) e = limit;
    if (!e.isAfter(s)) continue;
    final kind = categories[a.categoryId]?.kind ?? ActivityKind.neutral;
    byCat[a.categoryId] =
        (byCat[a.categoryId] ?? Duration.zero) + e.difference(s);
    counts[a.categoryId] = (counts[a.categoryId] ?? 0) + 1;
    byKind[kind] = (byKind[kind] ?? Duration.zero) + e.difference(s);
    // По днях: ріжемо на опівночах.
    var cur = s;
    while (cur.isBefore(e)) {
      final dayEnd = nextDay(cur);
      final segEnd = dayEnd.isBefore(e) ? dayEnd : e;
      final i = _daysBetween(period.start, cur);
      if (i >= 0 && i < dayCount) {
        perDay[i][kind] =
            (perDay[i][kind] ?? Duration.zero) + segEnd.difference(cur);
      }
      cur = segEnd;
    }
  }

  final list = [
    for (final e in byCat.entries)
      CategoryTime(e.key, e.value, counts[e.key] ?? 0),
  ]..sort((a, b) => b.duration.compareTo(a.duration));

  final today = dayStart(now);
  final elapsed = today.isBefore(period.start)
      ? 0
      : (today.isBefore(period.end)
            ? _daysBetween(period.start, today) + 1
            : dayCount);

  return ActivityStats(
    period: period,
    byCategory: list,
    byKind: byKind,
    days: [
      for (var i = 0; i < dayCount; i++)
        DayTime(
          DateTime(period.start.year, period.start.month, period.start.day + i),
          perDay[i],
        ),
    ],
    elapsedDays: elapsed,
  );
}

/// «+1 год 20 хв» / «−35 хв» / «без змін».
String formatDelta(Duration d) {
  if (d.inMinutes.abs() < 1) return 'без змін';
  return '${d.isNegative ? '−' : '+'}${formatDuration(d.abs())}';
}

/// Частка у відсотках: «41 %».
String percent(double share) => '${(share * 100).round()} %';
