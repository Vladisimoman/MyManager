import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/database.dart';
import '../activity/activity_logic.dart' show formatDuration;
import '../activity/activity_screen.dart';
import '../activity/activity_stats.dart';
import '../activity/activity_stats_screen.dart' show kindColor;
import '../finance/finance_providers.dart' show databaseProvider;
import 'todo_logic.dart';
import 'todo_screen.dart';

/// Календар (етап 18): місяць із позначками справ, ключових дат
/// і (за бажанням) активностей; під ним — усе на вибраний день.

const calendarActivitiesKey = 'calendar_show_activities';

final calendarActivitiesProvider = StreamProvider<bool>(
  (ref) => ref
      .watch(databaseProvider)
      .watchSetting(calendarActivitiesKey)
      .map((v) => v == '1'),
);

const _activityDot = Color(0xFF00897B);

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _selected = _day(ref.read(todoClockProvider)());
  late DateTime _month = DateTime(_selected.year, _selected.month);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  void _showMonth(DateTime month, DateTime today) {
    setState(() {
      _month = DateTime(month.year, month.month);
      _selected = (today.year == _month.year && today.month == _month.month)
          ? today
          : _month;
    });
  }

  void _goToday(DateTime today) => setState(() {
    _selected = today;
    _month = DateTime(today.year, today.month);
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(todoClockProvider)();
    final today = _day(now);
    // Видалені серії — щоб їхні минулі дні лишались у календарі (етап 24).
    final todos = [
      ...?ref.watch(todosProvider).value,
      ...?ref.watch(deletedSeriesProvider).value,
    ];
    final completions =
        ref.watch(todoCompletionsProvider).value ?? const <TodoCompletion>[];
    final showActivities = ref.watch(calendarActivitiesProvider).value ?? false;
    // Слухаємо завжди (Riverpod 3 призупиняє непрослуховувані провайдери).
    final activities =
        ref.watch(activitiesProvider).value ?? const <Activity>[];
    final categories = ref.watch(activityCategoryMapProvider);

    final grid = monthGrid(_month);
    final agenda = agendaBetween(
      todos,
      grid.first,
      grid.last,
      now,
      completions: completions,
    );
    final actByDay = <DateTime, Duration>{};
    ActivityStats? dayStats;
    if (showActivities) {
      final stats = computeActivityStats(
        activities: activities,
        categories: categories,
        period: ActivityPeriod.custom(grid.first, grid.last),
        now: now,
      );
      for (final d in stats.days) {
        actByDay[d.day] = d.total;
      }
      dayStats = computeActivityStats(
        activities: activities,
        categories: categories,
        period: ActivityPeriod.of(ActivityPeriodKind.day, _selected),
        now: now,
      );
    }

    final isCurrent =
        _selected == today &&
        _month.year == today.year &&
        _month.month == today.month;
    final dayAgenda = agenda[_selected];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Календар'),
        actions: [
          if (!isCurrent)
            TextButton(
              onPressed: () => _goToday(today),
              child: const Text('Сьогодні'),
            ),
          IconButton(
            tooltip: showActivities
                ? 'Сховати активності'
                : 'Показати активності',
            isSelected: showActivities,
            // Увімкнено — кнопка підсвічена, як у модулі Activity.
            style: showActivities
                ? IconButton.styleFrom(
                    backgroundColor: scheme.secondaryContainer,
                    foregroundColor: scheme.onSecondaryContainer,
                  )
                : null,
            icon: const Icon(Icons.insights_outlined),
            selectedIcon: const Icon(Icons.insights),
            onPressed: () => ref
                .read(databaseProvider)
                .setSetting(calendarActivitiesKey, showActivities ? null : '1'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTodoForm(context, date: _selected),
        icon: const Icon(Icons.add),
        label: const Text('Справа'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          GestureDetector(
            // Свайп уліво/вправо — наступний/попередній місяць.
            onHorizontalDragEnd: (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 200) return;
              _showMonth(
                DateTime(_month.year, _month.month + (v < 0 ? 1 : -1)),
                today,
              );
            },
            child: Column(
              children: [
                _MonthHeader(
                  month: _month,
                  onPrev: () => _showMonth(
                    DateTime(_month.year, _month.month - 1),
                    today,
                  ),
                  onNext: () => _showMonth(
                    DateTime(_month.year, _month.month + 1),
                    today,
                  ),
                ),
                const _WeekdayRow(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: GridView.count(
                    crossAxisCount: 7,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    childAspectRatio: 0.92,
                    children: [
                      for (final d in grid)
                        _DayCell(
                          day: d,
                          inMonth: d.month == _month.month,
                          isToday: d == today,
                          selected: d == _selected,
                          agenda: agenda[d],
                          past: d.isBefore(today),
                          activity: actByDay[d] ?? Duration.zero,
                          onTap: () => setState(() {
                            _selected = d;
                            if (d.month != _month.month) {
                              _month = DateTime(d.year, d.month);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
                _Legend(showActivities: showActivities),
              ],
            ),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text(
              _dayTitle(_selected, today),
              key: const ValueKey('calendar-day-title'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          if (dayAgenda != null)
            for (final k in dayAgenda.keyDates) _KeyDateRow(item: k),
          if (dayAgenda != null)
            for (final t in dayAgenda.todos)
              TodoTile(item: t, now: now, sectionDay: _selected),
          if (dayAgenda == null || dayAgenda.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Text(
                _selected.isBefore(today)
                    ? 'Справ цього дня не було'
                    : 'Нічого не заплановано. Натисни «Справа», щоб додати.',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          if (dayStats != null) _DayActivities(stats: dayStats, day: _selected),
        ],
      ),
    );
  }

  static String _dayTitle(DateTime d, DateTime today) {
    final s = DateFormat(
      d.year == today.year ? 'EEEE, d MMMM' : 'EEEE, d MMMM y',
      'uk',
    ).format(d);
    final cap = s[0].toUpperCase() + s.substring(1);
    final diff = DateTime.utc(
      d.year,
      d.month,
      d.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    return switch (diff) {
      0 => '$cap · сьогодні',
      1 => '$cap · завтра',
      -1 => '$cap · вчора',
      _ => cap,
    };
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.onPrev,
    required this.onNext,
  });
  final DateTime month;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final s = DateFormat('LLLL y', 'uk').format(month);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Попередній місяць',
            icon: const Icon(Icons.chevron_left),
            onPressed: onPrev,
          ),
          Expanded(
            child: Text(
              s[0].toUpperCase() + s.substring(1),
              key: const ValueKey('calendar-month'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          IconButton(
            tooltip: 'Наступний місяць',
            icon: const Icon(Icons.chevron_right),
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}

class _WeekdayRow extends StatelessWidget {
  const _WeekdayRow();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          for (var wd = 1; wd <= 7; wd++)
            Expanded(
              child: Text(
                weekdayShort(wd),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: wd >= 6 ? AppColors.expense : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.selected,
    required this.agenda,
    required this.past,
    required this.activity,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool selected;
  final DayAgenda? agenda;
  final bool past;
  final Duration activity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final a = agenda;
    final dots = <Color>[
      if (a != null && a.openCount > 0)
        past ? AppColors.expense : scheme.primary
      else if (a != null && a.missedCount > 0)
        AppColors
            .expense // «не виконано» або виконано пізніше
      else if (a != null && a.todos.isNotEmpty)
        scheme.outline, // усе виконано
      if (a != null && a.keyDates.isNotEmpty) Colors.pink.shade300,
      if (activity.inMinutes > 0) _activityDot,
    ];
    final fg = selected
        ? scheme.onPrimary
        : (inMonth ? scheme.onSurface : scheme.outline);
    return InkWell(
      key: ValueKey(
        'day-${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}',
      ),
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? scheme.primary : null,
              border: isToday && !selected
                  ? Border.all(color: scheme.primary, width: 1.5)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                color: fg,
                fontWeight: isToday || selected ? FontWeight.w700 : null,
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 6,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final c in dots)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 1.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: inMonth ? c : c.withValues(alpha: 0.4),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.showActivities});
  final bool showActivities;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(Color c, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 4,
        children: [
          item(scheme.primary, 'справи'),
          item(AppColors.expense, 'не виконано'),
          item(scheme.outline, 'виконано'),
          item(Colors.pink.shade300, 'ключові дати'),
          if (showActivities) item(_activityDot, 'активності'),
        ],
      ),
    );
  }
}

class _KeyDateRow extends StatelessWidget {
  const _KeyDateRow({required this.item});
  final KeyDateItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final k = item;
    return ListTile(
      contentPadding: const EdgeInsets.only(left: 16, right: 20),
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: scheme.tertiaryContainer,
        child: Icon(
          keyDateIcons[k.todo.keyType] ?? Icons.star_border,
          size: 20,
          color: scheme.onTertiaryContainer,
        ),
      ),
      title: Text(k.todo.title),
      subtitle: Text(
        [
          keyDateTypes[k.todo.keyType] ?? 'Ключова дата',
          if (yearsText(k).isNotEmpty) yearsText(k),
        ].join(' · '),
      ),
      onTap: () => openTodoForm(context, todo: k.todo),
    );
  }
}

class _DayActivities extends ConsumerWidget {
  const _DayActivities({required this.stats, required this.day});
  final ActivityStats stats;
  final DateTime day;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final cats = ref.watch(activityCategoryMapProvider);
    final top = stats.byCategory.take(5).toList();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: const EdgeInsets.only(left: 20, right: 12),
            title: Text(
              stats.total == Duration.zero
                  ? 'Активностей не записано'
                  : 'Активності · ${formatDuration(stats.total)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            trailing: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ActivityScreen(day: day)),
              ),
              child: const Text('Відкрити'),
            ),
          ),
          for (final c in top)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
              child: Row(
                children: [
                  Icon(
                    activityIcon(cats[c.categoryId]?.icon ?? ''),
                    size: 18,
                    color: kindColor(
                      cats[c.categoryId]?.kind ?? ActivityKind.neutral,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      cats[c.categoryId]?.name ?? '—',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    formatDuration(c.duration),
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          if (stats.byCategory.length > top.length)
            Padding(
              padding: const EdgeInsets.fromLTRB(50, 0, 20, 4),
              child: Text(
                'і ще ${stats.byCategory.length - top.length}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}
