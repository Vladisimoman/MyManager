import '../../data/database.dart';

/// Activity (етап 14): стрічка дня, прогалини, перетини, тривалість.

/// Запис «від кінця попередньої» не тягнемо з давнини: якщо остання активність
/// закінчилась давніше — просимо вказати початок самому.
const maxAutoStartGap = Duration(hours: 24);

/// Прогалини коротші за це не показуємо (секунди, що «загубились» між записами).
const minGap = Duration(minutes: 1);

DateTime dayStart(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime nextDay(DateTime d) => DateTime(d.year, d.month, d.day + 1);

/// Таймер, що триває зараз (не більше одного).
Activity? runningActivity(Iterable<Activity> list) {
  for (final a in list) {
    if (!a.deleted && a.end == null) return a;
  }
  return null;
}

/// Звідки починати нову активність: кінець останньої завершеної (не пізніше [now]).
/// null — нічого немає або остання була давно ([maxAutoStartGap]).
DateTime? suggestedStart(Iterable<Activity> list, DateTime now) {
  DateTime? last;
  for (final a in list) {
    final e = a.end;
    if (a.deleted || e == null || e.isAfter(now)) continue;
    if (last == null || e.isAfter(last)) last = e;
  }
  if (last == null || now.difference(last) > maxAutoStartGap) return null;
  return last;
}

/// Активності, що перетинаються з [start, end) (крім [exceptId]). Таймер — до [now].
List<Activity> overlapping(
  Iterable<Activity> list,
  DateTime start,
  DateTime end, {
  String? exceptId,
  DateTime? now,
}) {
  return [
    for (final a in list)
      if (!a.deleted &&
          a.id != exceptId &&
          a.start.isBefore(end) &&
          (a.end ?? now ?? DateTime.now()).isAfter(start))
        a,
  ];
}

/// Рядок стрічки дня: активність (обрізана межами дня) або прогалина.
class TimelineItem {
  const TimelineItem.activity(this.activity, this.from, this.to)
    : isGap = false;
  const TimelineItem.gap(this.from, this.to) : activity = null, isGap = true;

  final Activity? activity;
  final DateTime from;
  final DateTime to;
  final bool isGap;

  Duration get duration => to.difference(from);

  /// Активність почалась учора / закінчиться завтра.
  bool get startsBefore => activity != null && activity!.start.isBefore(from);
  bool get endsAfter => activity?.end != null && activity!.end!.isAfter(to);
}

/// Стрічка дня [day] від ранку до вечора: активності + прогалини між ними.
/// Прогалина на початку дня — лише якщо щось записано раніше (облік уже йде);
/// у кінці — до «зараз» (для сьогодні).
List<TimelineItem> dayTimeline(
  Iterable<Activity> list,
  DateTime day,
  DateTime now,
) {
  final from = dayStart(day);
  final to = nextDay(day);
  final limit = now.isBefore(to) ? now : to;
  final items = <TimelineItem>[];
  final inDay = [
    for (final a in list)
      if (!a.deleted && a.start.isBefore(to) && (a.end ?? now).isAfter(from)) a,
  ]..sort((a, b) => a.start.compareTo(b.start));
  final trackedBefore = list.any(
    (a) => !a.deleted && a.end != null && !a.end!.isAfter(from),
  );

  DateTime? cursor = trackedBefore ? from : null;
  for (final a in inDay) {
    final s = a.start.isBefore(from) ? from : a.start;
    final rawEnd = a.end ?? now;
    final e = rawEnd.isAfter(to) ? to : rawEnd;
    if (cursor != null && s.difference(cursor) >= minGap) {
      items.add(TimelineItem.gap(cursor, s));
    }
    items.add(TimelineItem.activity(a, s, e));
    if (cursor == null || e.isAfter(cursor)) cursor = e;
  }
  if (cursor != null &&
      limit.isAfter(cursor) &&
      limit.difference(cursor) >= minGap) {
    // Хвіст: якщо триває таймер, прогалини немає (вона вже «зайнята» таймером).
    if (runningActivity(inDay) == null) {
      items.add(TimelineItem.gap(cursor, limit));
    }
  }
  return items;
}

/// Скільки записано за день [day] (без прогалин; перетини не подвоюються).
Duration trackedOn(Iterable<Activity> list, DateTime day, DateTime now) {
  var total = Duration.zero;
  DateTime? cursor;
  for (final i in dayTimeline(list, day, now)) {
    if (i.isGap) continue;
    final s = cursor != null && i.from.isBefore(cursor) ? cursor : i.from;
    if (i.to.isAfter(s)) total += i.to.difference(s);
    if (cursor == null || i.to.isAfter(cursor)) cursor = i.to;
  }
  return total;
}

/// «1 год 20 хв», «45 хв», «8 год».
String formatDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return '< 1 хв';
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '$r хв';
  if (r == 0) return '$h год';
  return '$h год $r хв';
}

/// Таймер: «1:05:09».
String formatClock(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '$h:${two(m)}:${two(sec)}';
}

String kindLabel(ActivityKind k) => switch (k) {
  ActivityKind.useful => 'Корисне',
  ActivityKind.neutral => 'Нейтральне',
  ActivityKind.waste => 'Марнування часу',
};
