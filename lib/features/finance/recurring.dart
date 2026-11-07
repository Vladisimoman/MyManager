import '../../data/database.dart';
import '../../data/rate_history.dart';

/// Регулярні платежі (етап 12): дати повторів і платежі, що чекають підтвердження.

/// Сталий id запису платежу: однаковий на всіх пристроях, тож підтвердження
/// на двох телефонах не створить дубль.
String occurrenceId(String templateId, DateTime date) =>
    'rec:$templateId:${isoDay(date)}';

/// Скільки найстаріших пропущених платежів одного шаблону показувати максимум.
const maxPendingPerTemplate = 12;

int _daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// [i]-й платіж (0 — перший) від [start].
/// Щомісяця 31-го → у коротких місяцях останній день (30-те, 28/29 лютого).
DateTime occurrenceAt(RepeatKind repeat, DateTime start, int i) {
  switch (repeat) {
    case RepeatKind.none:
      return start;
    case RepeatKind.weekly:
      return DateTime(start.year, start.month, start.day + 7 * i);
    case RepeatKind.monthly:
      final m = DateTime(start.year, start.month + i);
      final d = start.day.clamp(1, _daysInMonth(m.year, m.month));
      return DateTime(m.year, m.month, d);
    case RepeatKind.yearly:
      final y = start.year + i;
      final d = start.day.clamp(1, _daysInMonth(y, start.month));
      return DateTime(y, start.month, d);
  }
}

bool isRecurring(EntryTemplate t) =>
    t.repeat != RepeatKind.none && t.startDate != null;

/// Усі платежі від першого до [until] включно.
List<DateTime> occurrencesUntil(EntryTemplate t, DateTime until) {
  if (!isRecurring(t)) return const [];
  final end = DateTime(until.year, until.month, until.day);
  final out = <DateTime>[];
  for (var i = 0; i < 100000; i++) {
    final d = occurrenceAt(t.repeat, t.startDate!, i);
    if (d.isAfter(end)) break;
    out.add(d);
  }
  return out;
}

/// Наступний ще не оброблений платіж (сьогодні або пізніше — або найстаріший пропущений).
DateTime? nextOccurrence(EntryTemplate t, Set<String> handled, DateTime today) {
  if (!isRecurring(t)) return null;
  for (var i = 0; i < 100000; i++) {
    final d = occurrenceAt(t.repeat, t.startDate!, i);
    if (!handled.contains(occurrenceId(t.id, d))) return d;
  }
  return null;
}

class PendingPayment {
  const PendingPayment(this.template, this.date);
  final EntryTemplate template;
  final DateTime date;

  String get id => occurrenceId(template.id, date);
}

/// Платежі, день яких настав, але їх ще не записано й не пропущено. Старіші — зверху.
List<PendingPayment> pendingPayments(
  Iterable<EntryTemplate> templates,
  Set<String> handled,
  DateTime today,
) {
  final out = <PendingPayment>[];
  for (final t in templates) {
    if (t.deleted || !isRecurring(t)) continue;
    final due = [
      for (final d in occurrencesUntil(t, today))
        if (!handled.contains(occurrenceId(t.id, d))) d,
    ];
    final recent = due.length > maxPendingPerTemplate
        ? due.sublist(due.length - maxPendingPerTemplate)
        : due;
    out.addAll(recent.map((d) => PendingPayment(t, d)));
  }
  out.sort((a, b) {
    final c = a.date.compareTo(b.date);
    return c != 0 ? c : a.template.name.compareTo(b.template.name);
  });
  return out;
}

String repeatLabel(RepeatKind r) => switch (r) {
  RepeatKind.none => 'Без повтору',
  RepeatKind.weekly => 'Щотижня',
  RepeatKind.monthly => 'Щомісяця',
  RepeatKind.yearly => 'Щороку',
};
