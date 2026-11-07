import 'dart:convert';

import '../../data/database.dart';
import '../todo/todo_logic.dart';

/// Сповіщення (етап 19): що й коли показати. Без Android — щоб перевіряти тестами.

/// На скільки днів уперед плануємо (далі — після наступного відкриття додатка).
const planDays = 14;

/// Не більше стількох запланованих сповіщень (Android обмежує кількість будильників).
const planLimit = 64;

/// Ідентифікатори «Відкласти» — окремий діапазон, щоб перепланування їх не стирало.
const snoozeIdBase = 100000;

/// Ранкове зведення за замовчуванням — о 9:00.
const defaultDigestMinutes = 9 * 60;

/// Варіанти «Нагадати» у формі справи: хвилин до часу справи.
const remindOptions = <(int, String)>[
  (0, 'Вчасно'),
  (10, 'За 10 хв'),
  (30, 'За 30 хв'),
  (60, 'За 1 год'),
  (AppDatabase.noReminder, 'Не нагадувати'),
];

enum NotificationKind { reminder, digest }

class PlannedNotification {
  const PlannedNotification({
    required this.id,
    required this.kind,
    required this.at,
    required this.title,
    required this.body,
    this.lines = const [],
    this.todoId,
    this.date,
  });

  final int id;
  final NotificationKind kind;
  final DateTime at;
  final String title;
  final String body;

  /// Розгорнутий текст (для зведення — список справ).
  final List<String> lines;

  /// Для нагадування: яка справа і який повтор (для «Виконано»).
  final String? todoId;
  final DateTime? date;

  String get payload =>
      encodePayload(todoId: todoId, date: date, title: title, body: body);

  @override
  String toString() => '$kind ${at.toIso8601String()} $title — $body';
}

String encodePayload({
  String? todoId,
  DateTime? date,
  String? title,
  String? body,
}) => jsonEncode({
  'todo': ?todoId,
  if (date != null) 'date': date.toIso8601String().substring(0, 10),
  'title': ?title,
  'body': ?body,
});

/// Розбір payload; null — щось чуже або зіпсоване.
({String? todoId, DateTime? date, String title, String body})? decodePayload(
  String? payload,
) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final j = jsonDecode(payload) as Map;
    final d = j['date'] as String?;
    return (
      todoId: j['todo'] as String?,
      date: d == null ? null : DateTime.parse(d),
      title: (j['title'] as String?) ?? '',
      body: (j['body'] as String?) ?? '',
    );
  } catch (_) {
    return null;
  }
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);

/// «справа / справи / справ».
String tasksWord(int n) => plural(n, 'справа', 'справи', 'справ');

String _reminderBody(Todo t) {
  final time = minutesLabel(t.dueMinutes!);
  final before = t.remindBefore;
  final lead = switch (before) {
    0 => 'Зараз · $time',
    60 => 'Через 1 год · о $time',
    _ => 'Через $before хв · о $time',
  };
  return t.note == null ? lead : '$lead · ${t.note}';
}

/// Усі сповіщення від [now] на [planDays] днів: нагадування про справи з часом
/// і ранкові зведення (о [digestMinutes]; null — без зведення).
List<PlannedNotification> planNotifications({
  required Iterable<Todo> todos,
  Iterable<TodoCompletion> completions = const [],
  required DateTime now,
  int? digestMinutes = defaultDigestMinutes,
  int days = planDays,
}) {
  final today = _day(now);
  final last = _addDays(today, days - 1);
  final doneOcc = {
    for (final c in completions)
      if (!c.deleted) AppDatabase.completionId(c.todoId, c.date),
  };
  final out = <PlannedNotification>[];

  // 1. Нагадування про справи з часом.
  for (final t in todos) {
    if (t.deleted || isKeyDate(t) || t.dueDate == null) continue;
    if (t.dueMinutes == null || t.remindBefore < 0) continue;
    final dates = isRepeating(t)
        ? occurrencesBetween(t, today, last)
        : (t.done || t.failed ? const <DateTime>[] : [_day(t.dueDate!)]);
    for (final d in dates) {
      if (d.isAfter(last) || d.isBefore(today)) continue;
      if (isRepeating(t) &&
          doneOcc.contains(AppDatabase.completionId(t.id, d))) {
        continue;
      }
      final at = DateTime(
        d.year,
        d.month,
        d.day,
      ).add(Duration(minutes: t.dueMinutes! - t.remindBefore));
      if (!at.isAfter(now)) continue;
      out.add(
        PlannedNotification(
          id: 0,
          kind: NotificationKind.reminder,
          at: at,
          title: t.title,
          body: _reminderBody(t),
          todoId: t.id,
          date: d,
        ),
      );
    }
  }

  // 2. Ранкові зведення: справи дня, прострочені, ключові дати.
  if (digestMinutes != null && digestMinutes >= 0) {
    for (var i = 0; i < days; i++) {
      final d = _addDays(today, i);
      final at = d.add(Duration(minutes: digestMinutes));
      if (!at.isAfter(now)) continue;
      final digest = _digestFor(todos, completions, at);
      if (digest != null) out.add(digest);
    }
  }

  out.sort((a, b) => a.at.compareTo(b.at));
  final limited = out.take(planLimit).toList();
  return [
    for (var i = 0; i < limited.length; i++)
      PlannedNotification(
        id: i + 1,
        kind: limited[i].kind,
        at: limited[i].at,
        title: limited[i].title,
        body: limited[i].body,
        lines: limited[i].lines,
        todoId: limited[i].todoId,
        date: limited[i].date,
      ),
  ];
}

PlannedNotification? _digestFor(
  Iterable<Todo> todos,
  Iterable<TodoCompletion> completions,
  DateTime at,
) {
  final g = groupTodos(todos, at, completions: completions);
  final count = g.today.length + g.overdue.length;
  if (count == 0 && g.keyDates.isEmpty) return null;

  final lines = <String>[
    if (g.overdue.isNotEmpty) 'Прострочено: ${g.overdue.length}',
    for (final t in g.today.take(5))
      t.todo.dueMinutes == null
          ? '• ${t.todo.title}'
          : '• ${minutesLabel(t.todo.dueMinutes!)} ${t.todo.title}',
    if (g.today.length > 5) '…і ще ${g.today.length - 5}',
    for (final k in g.keyDates)
      [
        '${k.todo.title} — ${k.daysLeft == 0 ? 'сьогодні!' : daysLeftText(k.daysLeft)}',
        if (yearsText(k).isNotEmpty) '(${yearsText(k)})',
      ].join(' '),
  ];
  final summary = <String>[
    if (count > 0)
      g.overdue.isEmpty
          ? '$count ${tasksWord(count)}'
          : '$count ${tasksWord(count)} (${g.overdue.length} прострочено)',
    for (final k in g.keyDates)
      '${k.todo.title} ${k.daysLeft == 0 ? 'сьогодні' : daysLeftText(k.daysLeft)}',
  ];
  return PlannedNotification(
    id: 0,
    kind: NotificationKind.digest,
    at: at,
    title: count > 0 ? 'Сьогодні: $count ${tasksWord(count)}' : 'Ключові дати',
    body: summary.join(' · '),
    lines: lines,
  );
}
