import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart' show databaseProvider;
import '../notifications/notification_plan.dart' show remindOptions;
import 'calendar_screen.dart';
import 'todo_logic.dart';

/// To-Do (етапи 16–18): справи на сьогодні, на дату й без дати,
/// повторювані справи й ключові дати.

final todosProvider = StreamProvider<List<Todo>>(
  (ref) => ref.watch(databaseProvider).watchTodos(),
);

/// Видалені повторювані справи — лише для історії (етап 24).
final deletedSeriesProvider = StreamProvider<List<Todo>>(
  (ref) => ref.watch(databaseProvider).watchDeletedSeries(),
);

final todoCompletionsProvider = StreamProvider<List<TodoCompletion>>(
  (ref) => ref.watch(databaseProvider).watchTodoCompletions(),
);

/// Годинник — щоб у тестах керувати «сьогодні».
final todoClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

String _dateLabel(DateTime d, DateTime now) {
  final t = DateTime(now.year, now.month, now.day);
  final diff = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  if (diff == 0) return 'Сьогодні';
  if (diff == 1) return 'Завтра';
  if (diff == -1) return 'Вчора';
  return DateFormat(
    d.year == t.year ? 'EEEE, d MMMM' : 'd MMMM y',
    'uk',
  ).format(d);
}

String _shortDate(DateTime d, DateTime now) {
  final t = DateTime(now.year, now.month, now.day);
  final diff = DateTime.utc(
    d.year,
    d.month,
    d.day,
  ).difference(DateTime.utc(t.year, t.month, t.day)).inDays;
  if (diff == 0) return 'сьогодні';
  if (diff == 1) return 'завтра';
  if (diff == -1) return 'вчора';
  return DateFormat(d.year == t.year ? 'd MMM' : 'd MMM y', 'uk').format(d);
}

const keyDateIcons = {
  'birthday': Icons.cake_outlined,
  'anniversary': Icons.favorite_border,
  'holiday': Icons.celebration_outlined,
  'other': Icons.star_border,
};

void openTodoForm(BuildContext context, {Todo? todo, DateTime? date}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => todo != null && isKeyDate(todo)
          ? KeyDateFormScreen(todo: todo)
          : TodoFormScreen(todo: todo, presetDate: date),
    ),
  );
}

class TodoScreen extends ConsumerWidget {
  const TodoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(todoClockProvider)();
    final groups = groupTodos(
      [
        ...?ref.watch(todosProvider).value,
        ...?ref.watch(deletedSeriesProvider).value,
      ],
      now,
      completions:
          ref.watch(todoCompletionsProvider).value ?? const <TodoCompletion>[],
    );
    final todayCount = groups.overdue.length + groups.today.length;
    return DefaultTabController(
      length: 4,
      child: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('To-do'),
            actions: [
              IconButton(
                tooltip: 'Календар',
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CalendarScreen()),
                ),
              ),
              IconButton(
                tooltip: 'Ключові дати',
                icon: const Icon(Icons.cake_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const KeyDatesScreen()),
                ),
              ),
            ],
            bottom: TabBar(
              labelPadding: const EdgeInsets.symmetric(horizontal: 2),
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: const TextStyle(fontSize: 13),
              tabs: [
                _CountTab(
                  'Сьогодні',
                  todayCount,
                  key: const ValueKey('tab-today'),
                ),
                _CountTab(
                  'Далі',
                  groups.planned.length,
                  key: const ValueKey('tab-planned'),
                ),
                _CountTab(
                  'Без дати',
                  groups.noDate.length,
                  key: const ValueKey('tab-nodate'),
                ),
                const _CountTab('Завершені', 0, key: ValueKey('tab-done')),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              // Нова справа — на сьогодні з вкладки «Сьогодні», без дати — з «Без дати».
              final tab = DefaultTabController.of(context).index;
              openTodoForm(
                context,
                date: switch (tab) {
                  0 => now,
                  1 => DateTime(now.year, now.month, now.day + 1),
                  _ => null,
                },
              );
            },
            icon: const Icon(Icons.add),
            label: const Text('Справа'),
          ),
          body: TabBarView(
            children: [
              _TodoList(
                header: groups.keyDates.isEmpty
                    ? null
                    : _KeyDatesBanner(items: groups.keyDates),
                sections: [
                  if (groups.overdue.isNotEmpty)
                    ('Прострочені', groups.overdue),
                  ('', groups.today),
                ],
                empty: groups.keyDates.isEmpty
                    ? 'На сьогодні справ немає 🎉\nНатисни «Справа», щоб додати.'
                    : '',
                now: now,
              ),
              _TodoList(
                sections: [
                  for (final e in _byDay(groups.planned).entries)
                    (_dateLabel(e.key, now), e.value),
                ],
                empty: 'Запланованих справ немає',
                groupedByDate: true,
                now: now,
              ),
              _TodoList(
                sections: [('', groups.noDate)],
                empty: 'Справ без дати немає',
                now: now,
              ),
              _HistoryList(entries: groups.history, now: now),
            ],
          ),
        ),
      ),
    );
  }

  static Map<DateTime, List<TodoItem>> _byDay(List<TodoItem> list) {
    final out = <DateTime, List<TodoItem>>{};
    for (final t in list) {
      (out[t.date!] ??= []).add(t);
    }
    return out;
  }
}

/// Вкладка з лічильником (усі 4 вміщаються на екрані телефона).
class _CountTab extends StatelessWidget {
  const _CountTab(this.label, this.count, {super.key});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
            ),
          ),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Ключові дати сьогодні й ті, про які час нагадати — вгорі «Сьогодні».
class _KeyDatesBanner extends StatelessWidget {
  const _KeyDatesBanner({required this.items});
  final List<KeyDateItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: scheme.tertiaryContainer,
      elevation: 0,
      child: Column(
        children: [
          for (final k in items)
            ListTile(
              dense: true,
              leading: Icon(
                keyDateIcons[k.todo.keyType] ?? Icons.star_border,
                color: scheme.onTertiaryContainer,
              ),
              title: Text(
                k.todo.title,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onTertiaryContainer,
                ),
              ),
              subtitle: Text(
                [
                  if (k.daysLeft == 0)
                    'Сьогодні!'
                  else
                    '${daysLeftText(k.daysLeft)} · ${DateFormat('d MMMM', 'uk').format(k.date)}',
                  if (yearsText(k).isNotEmpty) yearsText(k),
                ].join(' · '),
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
              onTap: () => openTodoForm(context, todo: k.todo),
            ),
        ],
      ),
    );
  }
}

class _TodoList extends StatelessWidget {
  const _TodoList({
    required this.sections,
    required this.empty,
    required this.now,
    this.groupedByDate = false,
    this.header,
  });
  final List<(String, List<TodoItem>)> sections;
  final String empty;
  final DateTime now;
  final Widget? header;

  /// Заголовки секцій — дати, тож у рядку дату не повторюємо.
  final bool groupedByDate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (header == null && sections.every((s) => s.$2.isEmpty)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            empty,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        ?header,
        for (final (title, list) in sections)
          if (list.isNotEmpty) ...[
            if (title.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: title == 'Прострочені'
                        ? AppColors.expense
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            for (final t in list)
              TodoTile(item: t, now: now, showDate: !groupedByDate),
          ],
      ],
    );
  }
}

class TodoTile extends ConsumerWidget {
  const TodoTile({
    super.key,
    required this.item,
    required this.now,
    this.showDate = true,
    this.sectionDay,
  });
  final TodoItem item;
  final DateTime now;
  final bool showDate;

  /// День розділу (у «Завершених» і календарі): дату показуємо, лише якщо інша.
  final DateTime? sectionDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final t = item.todo;
    final date = item.date;
    final db = ref.read(databaseProvider);
    final today = DateTime(now.year, now.month, now.day);
    final overdue = item.open && date != null && date.isBefore(today);
    final showDateHere = sectionDay != null
        ? date != null &&
              date != sectionDay &&
              item.lateFrom == null &&
              item.lateDoneOn == null
        : showDate && date != null && (overdue || !item.open || date != today);
    final details = <String>[
      if (item.failed)
        'не виконано'
      else if (item.lateDoneOn != null)
        'не вчасно · виконано ${_shortDate(item.lateDoneOn!, now)}'
      else if (item.lateFrom != null)
        'із запізненням · з ${_shortDate(item.lateFrom!, now)}',
      if (showDateHere) _shortDate(date, now),
      if (t.dueMinutes != null) minutesLabel(t.dueMinutes!),
      if (item.repeating) '↻ ${repeatText(t)}',
      if (item.seriesDeleted) 'серію видалено',
      ?t.note,
    ];

    Future<void> setDone(bool v) => item.repeating
        ? db.setOccurrenceDone(t.id, date!, v)
        : db.setTodoDone(t.id, v);
    Future<void> setFailed(bool v) => item.repeating
        ? db.setOccurrenceFailed(t.id, date!, v)
        : db.setTodoFailed(t.id, v);
    void snack(String text, Future<void> Function() undo) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(text),
            persist: false, // зникає сама, навіть з кнопкою
            action: SnackBarAction(label: 'Скасувати', onPressed: undo),
          ),
        );
    }

    Future<void> toggle(bool done) async {
      await setDone(done);
      if (done && context.mounted) {
        snack('Виконано: ${t.title}', () => setDone(false));
      }
    }

    final failBackground = Container(
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.only(left: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cancel_outlined, color: AppColors.expense),
          const SizedBox(width: 8),
          Text(
            'Не виконано',
            style: TextStyle(
              color: AppColors.expense,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    final deleteBackground = Container(
      color: AppColors.expense,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      child: const Icon(Icons.delete_outline, color: Colors.white),
    );

    return Dismissible(
      key: ValueKey('todo-${item.key}'),
      // Вправо — «не виконано» (лише для тих, що чекають), вліво — видалити.
      // Видалена серія — лише для історії (етап 24).
      direction: item.seriesDeleted
          ? DismissDirection.none
          : (item.open
                ? DismissDirection.horizontal
                : DismissDirection.endToStart),
      background: item.open ? failBackground : deleteBackground,
      secondaryBackground: item.open ? deleteBackground : null,
      confirmDismiss: (dir) async {
        if (dir == DismissDirection.startToEnd) {
          await setFailed(true);
          if (context.mounted) {
            snack('Не виконано: ${t.title}', () => setFailed(false));
          }
          return false; // рядок оновиться сам (перейде в «Завершені»)
        }
        if (!item.repeating) return true;
        // Повторювана справа: видаляється вся серія — питаємо.
        return await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: Text('Видалити «${t.title}»?'),
                content: const Text(
                  'Це повторювана справа — зникнуть усі майбутні повтори. '
                  'Виконані й невиконані дні лишаться в «Завершених».',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Ні'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Видалити'),
                  ),
                ],
              ),
            ) ??
            false;
      },
      onDismissed: (_) async {
        final messenger = ScaffoldMessenger.of(context);
        await db.setTodoDeleted(t.id, true);
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('«${t.title}» видалено'),
              persist: false, // зникає сама, навіть з кнопкою
              action: SnackBarAction(
                label: 'Скасувати',
                onPressed: () => db.setTodoDeleted(t.id, false),
              ),
            ),
          );
      },
      child: PriorityStripe(
        todo: t,
        child: ListTile(
          contentPadding: const EdgeInsets.only(left: 8, right: 20),
          leading: item.missed
              ? IconButton(
                  // «Не виконано» можна відкрити знову; виконану пізніше — ні
                  // (вона відкривається з дня виконання).
                  tooltip: item.auto
                      ? 'Виконано пізніше'
                      : (item.failed ? 'Відкрити знову' : 'Не вчасно'),
                  icon: const Icon(Icons.cancel, color: AppColors.expense),
                  onPressed: item.seriesDeleted
                      ? null
                      : item.auto
                      // Пропуск без позначки (етап 24): виконати із запізненням.
                      ? () {
                          setDone(true);
                          snack(
                            'Виконано із запізненням: ${t.title}',
                            () => setDone(false),
                          );
                        }
                      : item.failed
                      ? () {
                          setFailed(false);
                          snack(
                            'Відкрито знову: ${t.title}',
                            () => setFailed(true),
                          );
                        }
                      : () {},
                )
              : Checkbox(
                  value: item.done,
                  shape: const CircleBorder(),
                  onChanged: item.seriesDeleted
                      ? null
                      : (v) => toggle(v ?? false),
                ),
          title: Text(
            t.title,
            style: item.done
                ? TextStyle(
                    decoration: TextDecoration.lineThrough,
                    color: scheme.onSurfaceVariant,
                  )
                : (item.missed
                      ? TextStyle(color: scheme.onSurfaceVariant)
                      : null),
          ),
          subtitle: details.isEmpty
              ? null
              : Text(
                  details.join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: overdue || item.missed ? AppColors.expense : null,
                  ),
                ),
          onTap: item.seriesDeleted
              ? null
              : () => openTodoForm(context, todo: t),
        ),
      ),
    );
  }
}

/// Етап 26: кольорова смужка важливості зліва.
Color priorityColor(int priority) => switch (priority) {
  TodoPriority.must => AppColors.expense, // обов'язково — червоний
  TodoPriority.should => const Color(0xFFF0A020), // бажано — жовто-помаранчевий
  _ => const Color(0xFFB0B4BA), // як вийде — сірий
};

String priorityLabel(int priority) => switch (priority) {
  TodoPriority.must => "Обов'язково",
  TodoPriority.should => 'Бажано',
  _ => 'Як вийде',
};

class PriorityStripe extends StatelessWidget {
  const PriorityStripe({super.key, required this.todo, required this.child});

  final Todo todo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (isKeyDate(todo)) return child;
    return DecoratedBox(
      key: ValueKey('priority-${todo.id}-${todo.priority}'),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: priorityColor(todo.priority), width: 4),
        ),
      ),
      child: child,
    );
  }
}

/// «Завершені» (етап 20): розгортальні списки по днях, свіжий день — відкритий.
class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries, required this.now});
  final List<HistoryEntry> entries;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Завершених справ ще немає.\n\nТут будуть виконані й закриті як '
            '«не виконано» (свайп справи вправо) — по днях.',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final byDay = <DateTime, List<HistoryEntry>>{};
    for (final e in entries) {
      (byDay[e.day] ??= []).add(e);
    }
    final days = byDay.keys.toList();
    return ListView(
      padding: const EdgeInsets.only(bottom: 96, top: 4),
      children: [
        for (final day in days)
          _HistoryDay(
            key: ValueKey('history-${day.toIso8601String().substring(0, 10)}'),
            day: day,
            entries: byDay[day]!,
            now: now,
            initiallyExpanded: day == days.first,
          ),
      ],
    );
  }
}

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

class _HistoryDay extends StatelessWidget {
  const _HistoryDay({
    super.key,
    required this.day,
    required this.entries,
    required this.now,
    required this.initiallyExpanded,
  });
  final DateTime day;
  final List<HistoryEntry> entries;
  final DateTime now;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = entries.where((e) => e.kind != HistoryKind.missed).length;
    final missed = entries.length - done;
    return Theme(
      // Без ліній зверху й знизу розгорнутого дня.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        maintainState: true,
        tilePadding: const EdgeInsets.symmetric(horizontal: 20),
        title: Text(
          _capitalize(_dateLabel(day, now)),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text.rich(
          TextSpan(
            children: [
              if (done > 0)
                TextSpan(
                  text: '✓ $done',
                  style: const TextStyle(color: AppColors.income),
                ),
              if (done > 0 && missed > 0) const TextSpan(text: '   '),
              if (missed > 0)
                TextSpan(
                  text: '✕ $missed',
                  style: const TextStyle(color: AppColors.expense),
                ),
            ],
          ),
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        children: [
          for (final e in entries)
            TodoTile(item: e.item, now: now, sectionDay: day),
        ],
      ),
    );
  }
}

// ---------------- Форма справи ----------------

enum _When { none, today, tomorrow, date }

/// Варіанти повторення у формі.
enum _Rep { none, daily, weekly, monthly, yearly, custom }

class TodoFormScreen extends ConsumerStatefulWidget {
  const TodoFormScreen({super.key, this.todo, this.presetDate});
  final Todo? todo;
  final DateTime? presetDate;

  @override
  ConsumerState<TodoFormScreen> createState() => _TodoFormScreenState();
}

class _TodoFormScreenState extends ConsumerState<TodoFormScreen> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late final TextEditingController _every;
  DateTime? _date;
  int? _minutes;
  _Rep _rep = _Rep.none;
  TodoRepeat _customUnit = TodoRepeat.day;
  Set<int> _weekdays = {};
  DateTime? _until;
  int _remind = 0;
  int _priority = TodoPriority.should;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.todo != null;

  @override
  void initState() {
    super.initState();
    final t = widget.todo;
    _title = TextEditingController(text: t?.title ?? '');
    _note = TextEditingController(text: t?.note ?? '');
    _date = t?.dueDate ?? (t == null ? widget.presetDate : null);
    if (_date != null) _date = DateTime(_date!.year, _date!.month, _date!.day);
    _minutes = t?.dueMinutes;
    _remind = t?.remindBefore ?? 0;
    _priority = t?.priority ?? TodoPriority.should;
    final every = t?.repeatEvery ?? 1;
    _every = TextEditingController(text: '${every < 2 ? 2 : every}');
    if (t != null && t.repeatUnit != TodoRepeat.none) {
      _until = t.repeatUntil;
      _weekdays = t.repeatWeekdays == null ? {} : weekdaysOf(t).toSet();
      if (every > 1) {
        _rep = _Rep.custom;
        _customUnit = t.repeatUnit;
      } else {
        _rep = switch (t.repeatUnit) {
          TodoRepeat.day => _Rep.daily,
          TodoRepeat.week => _Rep.weekly,
          TodoRepeat.month => _Rep.monthly,
          TodoRepeat.year => _Rep.yearly,
          TodoRepeat.none => _Rep.none,
        };
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _every.dispose();
    super.dispose();
  }

  _When _when(DateTime now) {
    if (_date == null) return _When.none;
    final t = DateTime(now.year, now.month, now.day);
    if (_date == t) return _When.today;
    if (_date == DateTime(t.year, t.month, t.day + 1)) return _When.tomorrow;
    return _When.date;
  }

  TodoRepeat get _unit => switch (_rep) {
    _Rep.none => TodoRepeat.none,
    _Rep.daily => TodoRepeat.day,
    _Rep.weekly => TodoRepeat.week,
    _Rep.monthly => TodoRepeat.month,
    _Rep.yearly => TodoRepeat.year,
    _Rep.custom => _customUnit,
  };

  void _setRep(_Rep r, DateTime today) {
    setState(() {
      _rep = r;
      // Повторення без дати не буває — починаємо з сьогодні.
      if (r != _Rep.none && _date == null) _date = today;
      if (_unit == TodoRepeat.week && _weekdays.isEmpty && _date != null) {
        _weekdays = {_date!.weekday};
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(todoClockProvider)();
    final when = _when(now);
    final today = DateTime(now.year, now.month, now.day);
    final scheme = Theme.of(context).colorScheme;
    final n = int.tryParse(_every.text) ?? 2;
    final text = Theme.of(context).textTheme;
    final repeating = _rep != _Rep.none;
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Справа' : 'Нова справа'),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Видалити',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _title,
              autofocus: !_isEdit,
              maxLength: 120,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Що зробити',
                hintText: 'Наприклад, Купити квитки',
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 4),
            // Етап 26: важливість.
            Text('Важливість', style: text.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in TodoPriority.all)
                  ChoiceChip(
                    key: ValueKey('priority-chip-$p'),
                    avatar: CircleAvatar(
                      radius: 6,
                      backgroundColor: priorityColor(p),
                    ),
                    label: Text(priorityLabel(p)),
                    selected: _priority == p,
                    onSelected: (_) => setState(() => _priority = p),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text(repeating ? 'Перший раз' : 'Коли', style: text.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!repeating)
                  ChoiceChip(
                    label: const Text('Без дати'),
                    selected: when == _When.none,
                    onSelected: (_) => setState(() {
                      _date = null;
                      _minutes = null;
                    }),
                  ),
                ChoiceChip(
                  label: const Text('Сьогодні'),
                  selected: when == _When.today,
                  onSelected: (_) => setState(() => _date = today),
                ),
                ChoiceChip(
                  label: const Text('Завтра'),
                  selected: when == _When.tomorrow,
                  onSelected: (_) => setState(
                    () => _date = DateTime(
                      today.year,
                      today.month,
                      today.day + 1,
                    ),
                  ),
                ),
                ChoiceChip(
                  avatar: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    when == _When.date
                        ? DateFormat('d MMMM y', 'uk').format(_date!)
                        : 'Дата…',
                  ),
                  selected: when == _When.date,
                  onSelected: (_) => _pickDate(now),
                ),
              ],
            ),
            if (_date != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(
                  _minutes == null
                      ? 'Без часу'
                      : 'О ${minutesLabel(_minutes!)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_minutes != null)
                      IconButton(
                        tooltip: 'Прибрати час',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _minutes = null),
                      ),
                    TextButton(
                      onPressed: _pickTime,
                      child: Text(_minutes == null ? 'Додати час' : 'Змінити'),
                    ),
                  ],
                ),
              ),
            if (_date != null && _minutes != null) ...[
              Row(
                children: [
                  Icon(
                    _remind < 0
                        ? Icons.notifications_off_outlined
                        : Icons.notifications_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Text('Нагадати', style: text.titleSmall),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final (m, label) in remindOptions)
                    ChoiceChip(
                      label: Text(label),
                      selected: _remind == m,
                      onSelected: (_) => setState(() => _remind = m),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            if (!repeating &&
                _date != null &&
                _date!.isBefore(today) &&
                !(widget.todo?.done ?? false))
              Text(
                'Дата в минулому — справа буде серед прострочених',
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
            const SizedBox(height: 12),
            Text('Повторення', style: text.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (r, label) in const [
                  (_Rep.none, 'Ні'),
                  (_Rep.daily, 'Щодня'),
                  (_Rep.weekly, 'Щотижня'),
                  (_Rep.monthly, 'Щомісяця'),
                  (_Rep.yearly, 'Щороку'),
                  (_Rep.custom, 'Своє…'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _rep == r,
                    onSelected: (_) => _setRep(r, today),
                  ),
              ],
            ),
            if (_rep == _Rep.custom) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Text('Кожні'),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 64,
                    child: TextField(
                      key: const ValueKey('repeat-every'),
                      controller: _every,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(3),
                      ],
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 10),
                  DropdownButton<TodoRepeat>(
                    value: _customUnit,
                    items: [
                      DropdownMenuItem(
                        value: TodoRepeat.day,
                        child: Text(plural(n, 'день', 'дні', 'днів')),
                      ),
                      DropdownMenuItem(
                        value: TodoRepeat.week,
                        child: Text(plural(n, 'тиждень', 'тижні', 'тижнів')),
                      ),
                      DropdownMenuItem(
                        value: TodoRepeat.month,
                        child: Text(plural(n, 'місяць', 'місяці', 'місяців')),
                      ),
                      DropdownMenuItem(
                        value: TodoRepeat.year,
                        child: Text(plural(n, 'рік', 'роки', 'років')),
                      ),
                    ],
                    onChanged: (u) => setState(() {
                      _customUnit = u!;
                      if (u == TodoRepeat.week &&
                          _weekdays.isEmpty &&
                          _date != null) {
                        _weekdays = {_date!.weekday};
                      }
                    }),
                  ),
                ],
              ),
            ],
            if (repeating && _unit == TodoRepeat.week) ...[
              const SizedBox(height: 10),
              Text('У дні', style: TextStyle(color: scheme.onSurfaceVariant)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (var wd = 1; wd <= 7; wd++)
                    FilterChip(
                      showCheckmark: false,
                      label: Text(weekdayShort(wd)),
                      selected: _weekdays.contains(wd),
                      onSelected: (on) => setState(() {
                        if (on) {
                          _weekdays = {..._weekdays, wd};
                        } else if (_weekdays.length > 1) {
                          _weekdays = {..._weekdays}..remove(wd);
                        }
                      }),
                    ),
                ],
              ),
            ],
            if (repeating)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_busy_outlined),
                title: Text(
                  _until == null
                      ? 'Без кінця'
                      : 'До ${DateFormat('d MMMM y', 'uk').format(_until!)}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_until != null)
                      IconButton(
                        tooltip: 'Без кінця',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => _until = null),
                      ),
                    TextButton(
                      onPressed: () => _pickUntil(now),
                      child: Text(_until == null ? 'Додати кінець' : 'Змінити'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 500,
              minLines: 2,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Нотатка (необов\'язково)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 18)),
              ),
            ),
            if (_isEdit && widget.todo!.repeatUnit == TodoRepeat.none) ...[
              const SizedBox(height: 8),
              if (widget.todo!.done || widget.todo!.failed)
                TextButton.icon(
                  onPressed: () async {
                    await ref
                        .read(databaseProvider)
                        .setTodoDone(widget.todo!.id, false);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.undo),
                  label: const Text('Повернути в невиконані'),
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () async {
                          await ref
                              .read(databaseProvider)
                              .setTodoDone(widget.todo!.id, true);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.check),
                        label: const Text('Виконано'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.expense,
                        ),
                        onPressed: () async {
                          await ref
                              .read(databaseProvider)
                              .setTodoFailed(widget.todo!.id, true);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('Не виконано'),
                      ),
                    ),
                  ],
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(DateTime now) async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 10, 12, 31),
    );
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickUntil(DateTime now) async {
    final start = _date ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: _until ?? DateTime(start.year, start.month + 3, start.day),
      firstDate: start,
      lastDate: DateTime(now.year + 30, 12, 31),
    );
    if (d != null) setState(() => _until = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(
      context: context,
      initialTime: _minutes == null
          ? const TimeOfDay(hour: 9, minute: 0)
          : TimeOfDay(hour: _minutes! ~/ 60, minute: _minutes! % 60),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (t != null) setState(() => _minutes = t.hour * 60 + t.minute);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Напиши, що зробити');
      return;
    }
    final every = _rep == _Rep.custom ? (int.tryParse(_every.text) ?? 1) : 1;
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .saveTodo(
          id: widget.todo?.id,
          title: _title.text,
          note: _note.text,
          dueDate: _date,
          dueMinutes: _minutes,
          repeat: _unit,
          repeatEvery: every < 1 ? 1 : every,
          weekdays: _weekdays.toList(),
          repeatUntil: _until,
          remindBefore: _remind,
          priority: _priority,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final t = widget.todo!;
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    await db.setTodoDeleted(t.id, true);
    if (mounted) Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('«${t.title}» видалено'),
          persist: false, // зникає сама, навіть з кнопкою
          action: SnackBarAction(
            label: 'Скасувати',
            onPressed: () => db.setTodoDeleted(t.id, false),
          ),
        ),
      );
  }
}

// ---------------- Ключові дати ----------------

class KeyDatesScreen extends ConsumerWidget {
  const KeyDatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(todoClockProvider)();
    final items = upcomingKeyDates(
      ref.watch(todosProvider).value ?? const <Todo>[],
      now,
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ключові дати')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const KeyDateFormScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Дата'),
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Тут будуть дні народження, річниці й свята.\n\nВони повторюються щороку, '
                  'показують, скільки років виповнюється, і заздалегідь нагадують у «Сьогодні».',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 96, top: 8),
              children: [
                for (final k in items)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: scheme.tertiaryContainer,
                      child: Icon(
                        keyDateIcons[k.todo.keyType] ?? Icons.star_border,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                    title: Text(k.todo.title),
                    subtitle: Text(
                      [
                        DateFormat('d MMMM', 'uk').format(k.date),
                        if (yearsText(k).isNotEmpty) yearsText(k),
                      ].join(' · '),
                    ),
                    trailing: Text(
                      daysLeftText(k.daysLeft),
                      style: TextStyle(
                        fontWeight: k.daysLeft <= 7 ? FontWeight.w600 : null,
                        color: k.daysLeft == 0 ? scheme.primary : null,
                      ),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => KeyDateFormScreen(todo: k.todo),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class KeyDateFormScreen extends ConsumerStatefulWidget {
  const KeyDateFormScreen({super.key, this.todo});
  final Todo? todo;

  @override
  ConsumerState<KeyDateFormScreen> createState() => _KeyDateFormScreenState();
}

class _KeyDateFormScreenState extends ConsumerState<KeyDateFormScreen> {
  late final TextEditingController _title;
  late String _type;
  DateTime? _date;
  late bool _countYears;
  late int _remind;
  String? _error;
  String? _dateError;

  static const _remindOptions = [
    (0, 'У день'),
    (1, 'За день'),
    (3, 'За 3 дні'),
    (7, 'За тиждень'),
    (14, 'За 2 тижні'),
  ];

  @override
  void initState() {
    super.initState();
    final t = widget.todo;
    _title = TextEditingController(text: t?.title ?? '');
    _type = t?.keyType ?? 'birthday';
    _date = t?.dueDate;
    _countYears = t?.countYears ?? true;
    _remind = t?.remindDays ?? 3;
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.todo == null ? 'Нова ключова дата' : 'Ключова дата'),
        actions: [
          if (widget.todo != null)
            IconButton(
              tooltip: 'Видалити',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final e in keyDateTypes.entries)
                  ChoiceChip(
                    avatar: Icon(keyDateIcons[e.key], size: 18),
                    showCheckmark: false,
                    label: Text(e.value),
                    selected: _type == e.key,
                    onSelected: (_) => setState(() {
                      _type = e.key;
                      if (e.key == 'holiday' || e.key == 'other') {
                        _countYears = false;
                      }
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: widget.todo == null,
              maxLength: 80,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Назва',
                hintText: switch (_type) {
                  'birthday' => 'Наприклад, День народження мами',
                  'anniversary' => 'Наприклад, Річниця весілля',
                  'holiday' => 'Наприклад, Новий рік',
                  _ => 'Що за дата',
                },
                errorText: _error,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(
                _date == null
                    ? 'Дата не вибрана'
                    : DateFormat('d MMMM y', 'uk').format(_date!),
              ),
              subtitle: Text(
                _dateError ??
                    (_type == 'birthday'
                        ? 'Дата народження (з роком)'
                        : 'Перша дата (з роком)'),
                style: _dateError == null
                    ? null
                    : TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              trailing: TextButton(
                onPressed: _pickDate,
                child: Text(_date == null ? 'Вибрати' : 'Змінити'),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Рахувати роки'),
              subtitle: Text(
                _type == 'birthday' ? '«виповнюється 55»' : '«10 років»',
              ),
              value: _countYears,
              onChanged: (v) => setState(() => _countYears = v),
            ),
            const SizedBox(height: 8),
            Text('Нагадати в «Сьогодні»', style: text.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final (d, label) in _remindOptions)
                  ChoiceChip(
                    label: Text(label),
                    selected: _remind == d,
                    onSelected: (_) => setState(() => _remind = d),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Щороку в цей день — і заздалегідь, за вибрану кількість днів.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = ref.read(todoClockProvider)();
    final d = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year - 30, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 10, 12, 31),
      initialDatePickerMode: _date == null
          ? DatePickerMode.year
          : DatePickerMode.day,
    );
    if (d != null) {
      setState(() {
        _date = d;
        _dateError = null;
      });
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Введи назву');
      return;
    }
    if (_date == null) {
      setState(() => _dateError = 'Вибери дату');
      return;
    }
    await ref
        .read(databaseProvider)
        .saveTodo(
          id: widget.todo?.id,
          title: _title.text,
          dueDate: _date,
          keyType: _type,
          countYears: _countYears,
          remindDays: _remind,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final t = widget.todo!;
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    await db.setTodoDeleted(t.id, true);
    if (mounted) Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('«${t.title}» видалено'),
          persist: false, // зникає сама, навіть з кнопкою
          action: SnackBarAction(
            label: 'Скасувати',
            onPressed: () => db.setTodoDeleted(t.id, false),
          ),
        ),
      );
  }
}
