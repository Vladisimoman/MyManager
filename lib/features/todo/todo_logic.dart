import '../../data/database.dart';

/// To-Do (етапи 16–17): розкладка справ по вкладках, повторення, ключові дати.

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime _addDays(DateTime d, int n) => DateTime(d.year, d.month, d.day + n);
int _daysInMonth(int y, int m) => DateTime(y, m + 1, 0).day;
int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

bool isKeyDate(Todo t) => t.keyType != null;
bool isRepeating(Todo t) =>
    t.dueDate != null && (t.repeatUnit != TodoRepeat.none || isKeyDate(t));

List<int> weekdaysOf(Todo t) {
  final raw = t.repeatWeekdays;
  if (raw == null || raw.isEmpty) return [t.dueDate!.weekday];
  return raw.split(',').map(int.parse).toList()..sort();
}

/// Перший повтор, що припадає на [from] або пізніше (null — повтори скінчились).
DateTime? nextOccurrenceFrom(Todo t, DateTime from) {
  final start = t.dueDate;
  if (start == null) return null;
  final f = _day(from);
  final until = t.repeatUntil;
  DateTime? found;
  if (!isRepeating(t)) {
    found = f.isAfter(start) ? null : start;
  } else {
    final every = isKeyDate(t) ? 1 : (t.repeatEvery < 1 ? 1 : t.repeatEvery);
    final unit = isKeyDate(t) ? TodoRepeat.year : t.repeatUnit;
    final base = f.isBefore(start) ? start : f;
    switch (unit) {
      case TodoRepeat.none:
        found = start;
      case TodoRepeat.day:
        final k = (_daysBetween(start, base) + every - 1) ~/ every;
        found = _addDays(start, k * every);
      case TodoRepeat.week:
        final days = weekdaysOf(t);
        final startMonday = _addDays(start, -(start.weekday - 1));
        // Перевіряємо тижні циклу від тижня [base] уперед (максимум два цикли).
        final weekIndex = _daysBetween(startMonday, base) ~/ 7;
        var w = (weekIndex ~/ every) * every;
        for (var tries = 0; tries < 3 && found == null; tries++, w += every) {
          final monday = _addDays(startMonday, w * 7);
          for (final wd in days) {
            final d = _addDays(monday, wd - 1);
            if (!d.isBefore(base) && !d.isBefore(start)) {
              found = d;
              break;
            }
          }
        }
      case TodoRepeat.month:
        var k =
            ((base.year - start.year) * 12 + base.month - start.month) ~/
            every *
            every;
        if (k < 0) k = 0;
        for (var tries = 0; tries < 3 && found == null; tries++, k += every) {
          final m = DateTime(start.year, start.month + k);
          final d = DateTime(
            m.year,
            m.month,
            start.day.clamp(1, _daysInMonth(m.year, m.month)),
          );
          if (!d.isBefore(base)) found = d;
        }
      case TodoRepeat.year:
        var k = (base.year - start.year) ~/ every * every;
        if (k < 0) k = 0;
        for (var tries = 0; tries < 3 && found == null; tries++, k += every) {
          final y = start.year + k;
          final d = DateTime(
            y,
            start.month,
            start.day.clamp(1, _daysInMonth(y, start.month)),
          );
          if (!d.isBefore(base)) found = d;
        }
    }
  }
  if (found != null && until != null && found.isAfter(until)) return null;
  return found;
}

/// Останній повтор у [from, to] включно (для «прострочених»).
DateTime? lastOccurrenceBetween(Todo t, DateTime from, DateTime to) {
  DateTime? last;
  var cur = nextOccurrenceFrom(t, from);
  var guard = 0;
  while (cur != null && !cur.isAfter(to) && guard++ < 1000) {
    last = cur;
    cur = nextOccurrenceFrom(t, _addDays(cur, 1));
  }
  return last;
}

/// Усі повтори в [from, to] (для календаря).
List<DateTime> occurrencesBetween(Todo t, DateTime from, DateTime to) {
  final out = <DateTime>[];
  var cur = nextOccurrenceFrom(t, from);
  var guard = 0;
  while (cur != null && !cur.isAfter(to) && guard++ < 1000) {
    out.add(cur);
    cur = nextOccurrenceFrom(t, _addDays(cur, 1));
  }
  return out;
}

/// Рядок списку: справа (для повторюваної — конкретний повтор [date]).
class TodoItem {
  const TodoItem(
    this.todo,
    this.date, {
    this.done = false,
    this.failed = false,
    this.doneAt,
    this.lateDoneOn,
    this.lateFrom,
    this.auto = false,
  });
  final Todo todo;

  /// Дата справи / повтору; null — без дати.
  final DateTime? date;
  final bool done;

  /// Закрито як «не виконано» (етап 20).
  final bool failed;

  /// Коли виконано / закрито.
  final DateTime? doneAt;

  /// День призначення справи, виконаної пізніше: «не виконано — виконано [lateDoneOn]».
  final DateTime? lateDoneOn;

  /// День виконання із запізненням: «виконано, призначено на [lateFrom]».
  final DateTime? lateFrom;

  /// Етап 24: повтор минув без жодної позначки — «не виконано» автоматично
  /// (у базі запису немає; його можна позначити виконаним пізніше).
  final bool auto;

  /// Серію видалено — запис лише для історії.
  bool get seriesDeleted => todo.deleted;

  bool get repeating => isRepeating(todo);

  /// Не вийшло в свій день: закрито як «не виконано» або виконано пізніше.
  bool get missed => failed || lateDoneOn != null;

  /// Справа ще чекає (не виконана й не закрита).
  bool get open => !done && !missed;

  String get key =>
      '${todo.id}:${date?.toIso8601String() ?? '-'}'
      '${lateDoneOn != null ? ':missed' : ''}${lateFrom != null ? ':late' : ''}';
}

/// Як справа завершилась у певний день (вкладка «Завершені», етап 20).
enum HistoryKind {
  /// Виконано вчасно (або раніше).
  done,

  /// Виконано пізніше, ніж призначено.
  doneLate,

  /// Не виконано в день призначення (закрито так або виконано пізніше).
  missed,
}

class HistoryEntry {
  const HistoryEntry(this.day, this.kind, this.item);
  final DateTime day;
  final HistoryKind kind;
  final TodoItem item;
}

/// Записи історії однієї справи / повтору: виконана пізніше — два записи
/// (день призначення — «не виконано», день виконання — «із запізненням»).
List<HistoryEntry> historyOf(
  Todo t,
  DateTime? due, {
  required bool done,
  required bool failed,
  required DateTime closedAt,
  bool auto = false,
}) {
  final closedDay = _day(closedAt);
  final dueDay = due == null ? null : _day(due);
  if (failed) {
    final day = dueDay != null && !dueDay.isAfter(closedDay)
        ? dueDay
        : closedDay;
    return [
      HistoryEntry(
        day,
        HistoryKind.missed,
        TodoItem(t, due, failed: true, doneAt: closedAt, auto: auto),
      ),
    ];
  }
  if (!done) return const [];
  if (dueDay != null && closedDay.isAfter(dueDay)) {
    return [
      HistoryEntry(
        dueDay,
        HistoryKind.missed,
        TodoItem(t, due, doneAt: closedAt, lateDoneOn: closedDay),
      ),
      HistoryEntry(
        closedDay,
        HistoryKind.doneLate,
        TodoItem(t, due, done: true, doneAt: closedAt, lateFrom: dueDay),
      ),
    ];
  }
  return [
    HistoryEntry(
      closedDay,
      HistoryKind.done,
      TodoItem(t, due, done: true, doneAt: closedAt),
    ),
  ];
}

/// Етап 24: пропущені повтори.

/// Повторювана справа (не ключова дата).
bool _isSeries(Todo t) => isRepeating(t) && !isKeyDate(t);

/// З якого дня рахувати пропуски серії: старт серії, але не раніше створення.
DateTime _seriesStart(Todo t) {
  final created = _day(t.createdAt.toLocal());
  final due = _day(t.dueDate!);
  return due.isAfter(created) ? due : created;
}

/// Останній пропущений повтор, що ще чекає у «Прострочених»: сьогодні повтору
/// немає, а попередній не позначено. Він не рахується «не виконано», поки не
/// настане наступний (null — такого немає).
DateTime? _openOverdue(Todo t, DateTime today, bool Function(DateTime) closed) {
  if (t.deleted || nextOccurrenceFrom(t, today) == today) return null;
  final last = lastOccurrenceBetween(t, t.dueDate!, _addDays(today, -1));
  return last != null && !closed(last) ? last : null;
}

/// Повтори в [from, to], що минули без позначки, — «не виконано» в день
/// призначення. Рахуються з дня створення і, для видаленої серії, лише до
/// дня видалення; [keep] — той, що ще у «Прострочених».
List<HistoryEntry> autoMissed(
  Todo t,
  DateTime from,
  DateTime to,
  bool Function(DateTime) closed, {
  DateTime? keep,
}) {
  if (!_isSeries(t)) return const [];
  final seriesStart = _seriesStart(t);
  final start = seriesStart.isAfter(_day(from)) ? seriesStart : _day(from);
  var end = _day(to);
  if (t.deleted) {
    final lastLive = _addDays(_day(t.updatedAt.toLocal()), -1);
    if (lastLive.isBefore(end)) end = lastLive;
  }
  if (end.isBefore(start)) return const [];
  return [
    for (final d in occurrencesBetween(t, start, end))
      if (d != keep && !closed(d))
        HistoryEntry(
          d,
          HistoryKind.missed,
          TodoItem(t, d, failed: true, auto: true),
        ),
  ];
}

/// Етап 25: які минулі повтори записати в базу як «не виконано».
/// [closed] — є позначка (виконано / не виконано); [hasRecord] — є будь-який
/// запис, навіть «відкрито знову» (такі не перезаписуємо).
List<DateTime> missesToRecord(
  Todo t,
  DateTime now, {
  required bool Function(DateTime) closed,
  required bool Function(DateTime) hasRecord,
}) {
  if (!_isSeries(t)) return const [];
  final today = _day(now);
  final keep = _openOverdue(t, today, closed);
  return [
    for (final h in autoMissed(
      t,
      DateTime(1970),
      _addDays(today, -1),
      hasRecord,
      keep: keep,
    ))
      h.day,
  ];
}

/// Ключова дата, що наближається.
class KeyDateItem {
  const KeyDateItem(this.todo, this.date, this.daysLeft);
  final Todo todo;
  final DateTime date;
  final int daysLeft;

  /// «виповнюється 55» / «10 років» — скільки років на цю дату (якщо рахуємо).
  int? get years => todo.countYears ? date.year - todo.dueDate!.year : null;
}

class TodoGroups {
  const TodoGroups({
    required this.overdue,
    required this.today,
    required this.planned,
    required this.noDate,
    required this.history,
    required this.keyDates,
  });

  final List<TodoItem> overdue;
  final List<TodoItem> today;
  final List<TodoItem> planned;
  final List<TodoItem> noDate;

  /// Завершені за останні [doneHistoryDays] днів: від найновішого дня.
  final List<HistoryEntry> history;

  /// Ключові дати сьогодні й ті, про які час нагадати (за [Todo.remindDays]).
  final List<KeyDateItem> keyDates;
}

int _byTime(TodoItem a, TodoItem b) {
  final c = a.date!.compareTo(b.date!);
  if (c != 0) return c;
  final ma = a.todo.dueMinutes ?? 24 * 60, mb = b.todo.dueMinutes ?? 24 * 60;
  if (ma != mb) return ma.compareTo(mb);
  return a.todo.createdAt.compareTo(b.todo.createdAt);
}

/// Етап 26: спершу важливіші, усередині — як було.
int _byPriority(TodoItem a, TodoItem b) =>
    a.todo.priority.compareTo(b.todo.priority);

int _byPriorityThenTime(TodoItem a, TodoItem b) {
  final p = _byPriority(a, b);
  return p != 0 ? p : _byTime(a, b);
}

/// «Далі»: по днях, а в межах дня — за важливістю.
int _byDayThenPriority(TodoItem a, TodoItem b) {
  final c = a.date!.compareTo(b.date!);
  return c != 0 ? c : _byPriorityThenTime(a, b);
}

/// Скільки днів показувати у «Завершених».
const doneHistoryDays = 30;

TodoGroups groupTodos(
  Iterable<Todo> list,
  DateTime now, {
  Iterable<TodoCompletion> completions = const [],
}) {
  final today = _day(now);
  final doneOcc = <String, TodoCompletion>{
    for (final c in completions)
      if (!c.deleted) AppDatabase.completionId(c.todoId, c.date): c,
  };
  bool isDone(Todo t, DateTime d) =>
      doneOcc.containsKey(AppDatabase.completionId(t.id, d));

  final overdue = <TodoItem>[], todayL = <TodoItem>[], planned = <TodoItem>[];
  final noDate = <TodoItem>[], history = <HistoryEntry>[];
  final keyDates = <KeyDateItem>[];

  // Пропуски — за той самий період, що й «Завершені».
  final missFrom = _addDays(today, -doneHistoryDays);
  final yesterday = _addDays(today, -1);

  for (final t in list) {
    if (t.deleted) {
      // Видалена серія: минулі пропуски лишаються в історії (етап 24).
      history.addAll(autoMissed(t, missFrom, yesterday, (d) => isDone(t, d)));
      continue;
    }
    if (isKeyDate(t)) {
      final next = nextOccurrenceFrom(t, today);
      if (next == null) continue;
      final left = _daysBetween(today, next);
      if (left <= t.remindDays) keyDates.add(KeyDateItem(t, next, left));
      continue;
    }
    if (!isRepeating(t)) {
      final item = TodoItem(t, t.dueDate);
      if (t.done || t.failed) {
        history.addAll(
          historyOf(
            t,
            t.dueDate,
            done: t.done,
            failed: t.failed,
            closedAt: t.doneAt ?? t.updatedAt.toLocal(),
          ),
        );
      } else if (t.dueDate == null) {
        noDate.add(item);
      } else if (t.dueDate!.isBefore(today)) {
        overdue.add(item);
      } else if (t.dueDate == today) {
        todayL.add(item);
      } else {
        planned.add(item);
      }
      continue;
    }
    // Повторювана: сьогоднішній повтор; якщо його немає — останній пропущений
    // (поки не настав наступний); далі — найближчий майбутній.
    final todayOcc = nextOccurrenceFrom(t, today);
    if (todayOcc == today && !isDone(t, today)) {
      todayL.add(TodoItem(t, today));
    }
    final openLast = _openOverdue(t, today, (d) => isDone(t, d));
    if (openLast != null) overdue.add(TodoItem(t, openLast));
    // Решта минулих повторів без позначки — «не виконано» (етап 24).
    history.addAll(
      autoMissed(t, missFrom, yesterday, (d) => isDone(t, d), keep: openLast),
    );
    final next = nextOccurrenceFrom(t, _addDays(today, 1));
    if (next != null) planned.add(TodoItem(t, next));
  }

  // Завершені повтори.
  final byId = {for (final t in list) t.id: t};
  for (final c in doneOcc.values) {
    final t = byId[c.todoId];
    // Видалена серія лишає свою історію (етап 24), видалена разова — ні.
    if (t == null || (t.deleted && !_isSeries(t))) continue;
    history.addAll(
      historyOf(
        t,
        c.date,
        done: !c.failed,
        failed: c.failed,
        closedAt: c.doneAt,
        auto: c.isAuto,
      ),
    );
  }
  // Лише останні [doneHistoryDays] днів, від найновішого.
  history
    ..removeWhere(
      (h) =>
          _daysBetween(h.day, today) > doneHistoryDays || h.day.isAfter(today),
    )
    ..sort((a, b) {
      final c = b.day.compareTo(a.day);
      if (c != 0) return c;
      return (b.item.doneAt ?? b.day).compareTo(a.item.doneAt ?? a.day);
    });

  overdue.sort(_byPriorityThenTime);
  todayL.sort(_byPriorityThenTime);
  planned.sort(_byDayThenPriority);
  noDate.sort((a, b) {
    final p = _byPriority(a, b);
    return p != 0 ? p : a.todo.createdAt.compareTo(b.todo.createdAt);
  });
  keyDates.sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
  return TodoGroups(
    overdue: overdue,
    today: todayL,
    planned: planned,
    noDate: noDate,
    history: history,
    keyDates: keyDates,
  );
}

/// Ключові дати, відсортовані за найближчою датою.
List<KeyDateItem> upcomingKeyDates(Iterable<Todo> list, DateTime now) {
  final today = _day(now);
  return [
    for (final t in list)
      if (!t.deleted && isKeyDate(t))
        if (nextOccurrenceFrom(t, today) case final d?)
          KeyDateItem(t, d, _daysBetween(today, d)),
  ]..sort((a, b) => a.daysLeft.compareTo(b.daysLeft));
}

/// «09:30» з хвилин від півночі.
String minutesLabel(int m) =>
    '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

/// Скільки справ «на сьогодні» лишилось (з простроченими) — для кнопки на головному.
int todayLeft(
  Iterable<Todo> list,
  DateTime now, {
  Iterable<TodoCompletion> completions = const [],
}) {
  final g = groupTodos(list, now, completions: completions);
  return g.overdue.length + g.today.length;
}

const _weekdayShort = ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'нд'];

String weekdayShort(int wd) => _weekdayShort[wd - 1];

/// Українська множина: 1 день, 2 дні, 5 днів.
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

/// «щодня», «кожні 3 дні», «щотижня: пн, ср, пт», «кожні 2 тижні: сб», «щомісяця», «щороку».
String repeatText(Todo t) {
  if (!isRepeating(t) || isKeyDate(t)) return '';
  final n = t.repeatEvery;

  final base = switch (t.repeatUnit) {
    TodoRepeat.none => '',
    TodoRepeat.day =>
      n == 1 ? 'щодня' : 'кожні $n ${plural(n, 'день', 'дні', 'днів')}',
    TodoRepeat.week =>
      n == 1
          ? 'щотижня'
          : 'кожні $n ${plural(n, 'тиждень', 'тижні', 'тижнів')}',
    TodoRepeat.month =>
      n == 1
          ? 'щомісяця'
          : 'кожні $n ${plural(n, 'місяць', 'місяці', 'місяців')}',
    TodoRepeat.year =>
      n == 1 ? 'щороку' : 'кожні $n ${plural(n, 'рік', 'роки', 'років')}',
  };
  if (t.repeatUnit == TodoRepeat.week) {
    return '$base: ${weekdaysOf(t).map(weekdayShort).join(', ')}';
  }
  return base;
}

/// Типи ключових дат.
const keyDateTypes = {
  'birthday': 'День народження',
  'anniversary': 'Річниця',
  'holiday': 'Свято',
  'other': 'Інше',
};

/// «виповнюється 55» / «55 років» / «».
String yearsText(KeyDateItem k) {
  final y = k.years;
  if (y == null || y <= 0) return '';
  String plural(int n) {
    final m10 = n % 10, m100 = n % 100;
    if (m10 == 1 && m100 != 11) return 'рік';
    if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'роки';
    return 'років';
  }

  if (k.todo.keyType == 'birthday') {
    return k.daysLeft < 0 ? 'виповнилося $y' : 'виповнюється $y';
  }
  return '$y ${plural(y)}';
}

/// «сьогодні» / «завтра» / «через 5 днів».
String daysLeftText(int d) {
  if (d == 0) return 'сьогодні';
  if (d == 1) return 'завтра';
  final m10 = d % 10, m100 = d % 100;
  final w = m10 == 1 && m100 != 11
      ? 'день'
      : (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14) ? 'дні' : 'днів');
  return 'через $d $w';
}

// ---------------- Календар (етап 18) ----------------

/// Що припадає на один день.
class DayAgenda {
  final todos = <TodoItem>[];
  final keyDates = <KeyDateItem>[];

  bool get isEmpty => todos.isEmpty && keyDates.isEmpty;

  /// Скільки справ цього дня ще чекають.
  int get openCount => todos.where((t) => t.open).length;

  /// Скільки справ цього дня не вийшло (закрито «не виконано» чи виконано пізніше).
  int get missedCount => todos.where((t) => t.missed).length;
}

/// Справи (з усіма повторами) і ключові дати по днях у [from, to] включно.
Map<DateTime, DayAgenda> agendaBetween(
  Iterable<Todo> list,
  DateTime from,
  DateTime to,
  DateTime now, {
  Iterable<TodoCompletion> completions = const [],
}) {
  final start = _day(from), end = _day(to), today = _day(now);
  final doneOcc = <String, TodoCompletion>{
    for (final c in completions)
      if (!c.deleted) AppDatabase.completionId(c.todoId, c.date): c,
  };
  final out = <DateTime, DayAgenda>{};
  DayAgenda at(DateTime d) => out[d] ??= DayAgenda();

  bool inRange(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
  // Завершене — у дні з історії (виконана пізніше — і в день призначення,
  // і в день виконання).
  void addHistory(Iterable<HistoryEntry> entries) {
    for (final h in entries) {
      if (inRange(h.day)) at(h.day).todos.add(h.item);
    }
  }

  bool closed(Todo t, DateTime d) =>
      doneOcc.containsKey(AppDatabase.completionId(t.id, d));
  final yesterday = _addDays(today, -1);
  final byId = <String, Todo>{};
  for (final t in list) {
    if (t.dueDate == null) continue;
    if (t.deleted) {
      // Видалена серія: лише минуле — виконання й пропуски до дня видалення.
      if (_isSeries(t)) {
        byId[t.id] = t;
        addHistory(autoMissed(t, start, yesterday, (d) => closed(t, d)));
      }
      continue;
    }
    byId[t.id] = t;
    if (isKeyDate(t)) {
      for (final d in occurrencesBetween(t, start, end)) {
        at(d).keyDates.add(KeyDateItem(t, d, _daysBetween(today, d)));
      }
    } else if (!isRepeating(t)) {
      if (t.done || t.failed) {
        addHistory(
          historyOf(
            t,
            t.dueDate,
            done: t.done,
            failed: t.failed,
            closedAt: t.doneAt ?? t.updatedAt.toLocal(),
          ),
        );
      } else if (inRange(_day(t.dueDate!))) {
        at(_day(t.dueDate!)).todos.add(TodoItem(t, _day(t.dueDate!)));
      }
    } else {
      // Минулі без позначки — «не виконано» (етап 24); з сьогодні — ще чекають.
      final openLast = _openOverdue(t, today, (d) => closed(t, d));
      for (final d in occurrencesBetween(t, start, end)) {
        if (!d.isBefore(today) || d == openLast) {
          if (!closed(t, d)) at(d).todos.add(TodoItem(t, d));
        }
      }
      addHistory(
        autoMissed(
          t,
          start,
          end.isBefore(yesterday) ? end : yesterday,
          (d) => closed(t, d),
          keep: openLast,
        ),
      );
    }
  }
  for (final c in doneOcc.values) {
    final t = byId[c.todoId];
    if (t == null || !isRepeating(t) || isKeyDate(t)) continue;
    addHistory(
      historyOf(
        t,
        c.date,
        done: !c.failed,
        failed: c.failed,
        closedAt: c.doneAt,
        auto: c.isAuto,
      ),
    );
  }
  int rank(TodoItem x) => x.open ? 0 : (x.missed ? 1 : 2);
  for (final a in out.values) {
    // Спершу ті, що чекають, далі «не виконано», потім виконані;
    // усередині — за важливістю (етап 26), потім за часом.
    a.todos.sort((x, y) {
      final r = rank(x).compareTo(rank(y));
      if (r != 0) return r;
      return _byPriorityThenTime(x, y);
    });
  }
  return out;
}

/// Дні сітки місяця: з понеділка першого тижня до неділі останнього.
List<DateTime> monthGrid(DateTime month) {
  final first = DateTime(month.year, month.month);
  final start = _addDays(first, -(first.weekday - 1));
  final last = DateTime(
    month.year,
    month.month,
    _daysInMonth(month.year, month.month),
  );
  final end = _addDays(last, 7 - last.weekday);
  final n = _daysBetween(start, end) + 1;
  return [for (var i = 0; i < n; i++) _addDays(start, i)];
}
