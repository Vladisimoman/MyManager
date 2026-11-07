import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/category_icons.dart' show categoryColors;
import '../../data/database.dart';
import '../finance/finance_providers.dart' show databaseProvider;
import 'activity_logic.dart';
import 'activity_stats_screen.dart';

/// Activity (етап 14): що робив і скільки часу.

final activityCategoriesProvider = StreamProvider<List<ActivityCategory>>(
  (ref) => ref.watch(databaseProvider).watchActivityCategories(),
);

final activityCategoryMapProvider = Provider<Map<String, ActivityCategory>>((
  ref,
) {
  final list =
      ref.watch(activityCategoriesProvider).value ?? const <ActivityCategory>[];
  return {for (final c in list) c.id: c};
});

final activitiesProvider = StreamProvider<List<Activity>>(
  (ref) => ref.watch(databaseProvider).watchActivities(),
);

/// Годинник — щоб у тестах керувати «зараз».
final activityClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

const activityIcons = <String, IconData>{
  'sleep': Icons.bedtime_outlined,
  'breakfast': Icons.free_breakfast_outlined,
  'lunch': Icons.lunch_dining_outlined,
  'dinner': Icons.dinner_dining_outlined,
  'work': Icons.work_outline,
  'study': Icons.school_outlined,
  'sport': Icons.fitness_center,
  'commute': Icons.directions_bus_outlined,
  'youtube': Icons.smart_display_outlined,
  'social': Icons.forum_outlined,
  'rest': Icons.weekend_outlined,
  'chores': Icons.cleaning_services_outlined,
  'reading': Icons.menu_book_outlined,
  'games': Icons.sports_esports_outlined,
  'walk': Icons.directions_walk,
  'hygiene': Icons.shower_outlined,
  'cooking': Icons.soup_kitchen_outlined,
  'shopping': Icons.shopping_cart_outlined,
  'meditation': Icons.self_improvement,
  'code': Icons.code,
  'movie': Icons.movie_outlined,
  'music': Icons.music_note_outlined,
  'call': Icons.call_outlined,
  'friends': Icons.groups_outlined,
  'family': Icons.family_restroom,
  'health': Icons.favorite_border,
  'other': Icons.more_horiz,
};

IconData activityIcon(String key) => activityIcons[key] ?? Icons.more_horiz;

final _hm = DateFormat('HH:mm', 'uk');
String hm(DateTime d) => _hm.format(d);

/// «Сьогодні», «Вчора», «понеділок, 26 жовтня».
String activityDayLabel(DateTime day, DateTime now) {
  final d = dayStart(day), t = dayStart(now);
  final diff = t.difference(d).inDays;
  if (diff == 0) return 'Сьогодні';
  if (diff == 1) return 'Вчора';
  return DateFormat(
    d.year == t.year ? 'EEEE, d MMMM' : 'd MMMM y',
    'uk',
  ).format(d);
}

class ActivityAvatar extends StatelessWidget {
  const ActivityAvatar({super.key, required this.category, this.size = 40});
  final ActivityCategory? category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = Color(category?.color ?? 0xFF757575);
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: color.withValues(alpha: 0.15),
      child: Icon(
        activityIcon(category?.icon ?? 'other'),
        color: color,
        size: size * 0.55,
      ),
    );
  }
}

// ---------------- Головний екран Activity ----------------

class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key, this.day});

  /// Який день відкрити (з календаря); null — сьогодні.
  final DateTime? day;

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  late DateTime _day = dayStart(
    widget.day ?? ref.read(activityClockProvider)(),
  );
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Раз на хвилину оновлюємо «зараз» (хвіст-прогалина, тривалість таймера).
    _tick = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(activityClockProvider)();
    final list = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final cats = ref.watch(activityCategoryMapProvider);
    ref.watch(activityCategoriesProvider);
    final running = runningActivity(list);
    final timeline = dayTimeline(list, _day, now);
    final isToday = dayStart(now) == _day;
    final tracked = trackedOn(list, _day, now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Activity'),
        actions: [
          IconButton(
            tooltip: 'Статистика',
            icon: const Icon(Icons.bar_chart),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ActivityStatsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Категорії активностей',
            icon: const Icon(Icons.category_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const ActivityCategoriesScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (running != null)
              RunningCard(
                activity: running,
                category: cats[running.categoryId],
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Попередній день',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: () => setState(
                      () =>
                          _day = DateTime(_day.year, _day.month, _day.day - 1),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: _pickDay,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            Text(
                              activityDayLabel(_day, now),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'Записано ${formatDuration(tracked)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Наступний день',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: isToday
                        ? null
                        : () => setState(
                            () => _day = DateTime(
                              _day.year,
                              _day.month,
                              _day.day + 1,
                            ),
                          ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: timeline.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          isToday
                              ? 'Сьогодні ще нічого не записано.\n\nНатисни «Додати активність», коли щось закінчив '
                                    '(наприклад, «Сон з 1:00 до 8:00»), або «Таймер», щоб почати зараз.'
                              : 'Цього дня нічого не записано',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 16),
                      children: [
                        for (final i in timeline)
                          i.isGap
                              ? _GapTile(item: i)
                              : _ActivityTile(
                                  item: i,
                                  category: cats[i.activity!.categoryId],
                                  now: now,
                                ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: SizedBox(
                      height: 52,
                      child: FilledButton.icon(
                        onPressed: () => openActivityForm(context),
                        icon: const Icon(Icons.add),
                        label: const Text('Додати активність'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () => startTimer(context, ref),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Таймер'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDay() async {
    final now = ref.read(activityClockProvider)();
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (d != null) setState(() => _day = dayStart(d));
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({
    required this.item,
    required this.category,
    required this.now,
  });
  final TimelineItem item;
  final ActivityCategory? category;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = item.activity!;
    final scheme = Theme.of(context).colorScheme;
    final running = a.end == null;
    final full = (a.end ?? now).difference(a.start);
    final from = item.startsBefore ? '${hm(a.start)} (учора)' : hm(item.from);
    final to = running
        ? 'зараз'
        : (item.endsAfter ? '${hm(a.end!)} (наст. день)' : hm(item.to));
    return ListTile(
      key: ValueKey('activity-${a.id}'),
      leading: ActivityAvatar(category: category),
      title: Text(
        category?.name ?? 'Без категорії',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        ['$from – $to', ?a.note].join(' · '),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Text(
        running ? 'триває' : formatDuration(full),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: running ? scheme.primary : null,
        ),
      ),
      onTap: () => openActivityForm(context, activity: a),
    );
  }
}

class _GapTile extends StatelessWidget {
  const _GapTile({required this.item});
  final TimelineItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => openActivityForm(context, start: item.from, end: item.to),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 16,
              child: Center(
                child: Container(
                  width: 2,
                  height: 24,
                  color: scheme.outlineVariant,
                ),
              ),
            ),
            const SizedBox(width: 28),
            Expanded(
              child: Text(
                'Не записано ${formatDuration(item.duration)} · ${hm(item.from)} – ${hm(item.to)}',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
            Icon(Icons.add_circle_outline, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// Картка запущеного таймера: що, скільки минуло, «Завершити».
class RunningCard extends ConsumerStatefulWidget {
  const RunningCard({
    super.key,
    required this.activity,
    required this.category,
  });
  final Activity activity;
  final ActivityCategory? category;

  @override
  ConsumerState<RunningCard> createState() => _RunningCardState();
}

class _RunningCardState extends ConsumerState<RunningCard> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(activityClockProvider)();
    final a = widget.activity;
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            ActivityAvatar(category: widget.category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.category?.name ?? 'Активність',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    '${formatClock(now.difference(a.start))} · з ${hm(a.start)}',
                    style: TextStyle(
                      color: scheme.onPrimaryContainer,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => ref
                  .read(databaseProvider)
                  .stopActivity(a.id, ref.read(activityClockProvider)()),
              icon: const Icon(Icons.stop),
              label: const Text('Завершити'),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Таймер»: вибрати категорію — почати зараз. Якщо щось уже триває — воно завершується.
Future<void> startTimer(BuildContext context, WidgetRef ref) async {
  final cat = await pickActivityCategory(context, ref, title: 'Що починаєш?');
  if (cat == null) return;
  final db = ref.read(databaseProvider);
  final now = ref.read(activityClockProvider)();
  final running = runningActivity(
    ref.read(activitiesProvider).value ?? const [],
  );
  if (running != null) await db.stopActivity(running.id, now);
  await db.saveActivity(categoryId: cat.id, start: now);
}

Future<ActivityCategory?> pickActivityCategory(
  BuildContext context,
  WidgetRef ref, {
  required String title,
}) {
  final cats =
      (ref.read(activityCategoriesProvider).value ?? const <ActivityCategory>[])
          .where((c) => !c.hidden)
          .toList();
  return showModalBottomSheet<ActivityCategory>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(ctx).textTheme.titleMedium),
            const SizedBox(height: 12),
            _CategoryGrid(
              categories: cats,
              selectedId: null,
              onSelect: (c) => Navigator.pop(ctx, c),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });
  final List<ActivityCategory> categories;
  final String? selectedId;
  final ValueChanged<ActivityCategory> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.95,
      children: [
        for (final c in categories)
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => onSelect(c),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: c.id == selectedId
                      ? Color(c.color)
                      : Colors.transparent,
                  width: 2,
                ),
                color: c.id == selectedId
                    ? Color(c.color).withValues(alpha: 0.08)
                    : null,
              ),
              padding: const EdgeInsets.all(4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ActivityAvatar(category: c),
                  const SizedBox(height: 4),
                  Text(
                    c.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: scheme.onSurface),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------- Форма активності ----------------

void openActivityForm(
  BuildContext context, {
  Activity? activity,
  DateTime? start,
  DateTime? end,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          ActivityFormScreen(activity: activity, start: start, end: end),
    ),
  );
}

class ActivityFormScreen extends ConsumerStatefulWidget {
  const ActivityFormScreen({super.key, this.activity, this.start, this.end});
  final Activity? activity;

  /// Заповнення прогалини: готові межі.
  final DateTime? start;
  final DateTime? end;

  @override
  ConsumerState<ActivityFormScreen> createState() => _ActivityFormScreenState();
}

class _ActivityFormScreenState extends ConsumerState<ActivityFormScreen> {
  late final TextEditingController _note;
  String? _categoryId;
  late DateTime _start;
  DateTime? _end; // null — таймер триває (лише при редагуванні)
  bool _autoStart = false;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.activity != null;

  @override
  void initState() {
    super.initState();
    final a = widget.activity;
    final now = _trim(ref.read(activityClockProvider)());
    _note = TextEditingController(text: a?.note ?? '');
    _categoryId = a?.categoryId;
    if (a != null) {
      _start = a.start;
      _end = a.end;
    } else if (widget.start != null) {
      _start = widget.start!;
      _end = widget.end ?? now;
    } else {
      final s = suggestedStart(
        ref.read(activitiesProvider).value ?? const [],
        now,
      );
      _autoStart = s != null;
      _start = s ?? now.subtract(const Duration(hours: 1));
      _end = now;
    }
  }

  static DateTime _trim(DateTime d) =>
      DateTime(d.year, d.month, d.day, d.hour, d.minute);

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final now = ref.watch(activityClockProvider)();
    final cats =
        (ref.watch(activityCategoriesProvider).value ??
                const <ActivityCategory>[])
            .where((c) => !c.hidden || c.id == _categoryId)
            .toList();
    final catMap = ref.watch(activityCategoryMapProvider);
    final list = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final end = _end ?? now;
    final dur = end.difference(_start);
    final clash = dur.inSeconds > 0
        ? overlapping(
            list,
            _start,
            end,
            exceptId: widget.activity?.id,
            now: now,
          )
        : const <Activity>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Активність' : 'Нова активність'),
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
          padding: const EdgeInsets.all(16),
          children: [
            Text('Що робив', style: text.titleSmall),
            const SizedBox(height: 8),
            _CategoryGrid(
              categories: cats,
              selectedId: _categoryId,
              onSelect: (c) => setState(() {
                _categoryId = c.id;
                _error = null;
              }),
            ),
            const SizedBox(height: 12),
            Card(
              elevation: 0,
              color: scheme.surfaceContainerHigh,
              child: Column(
                children: [
                  _TimeRow(
                    label: 'Початок',
                    value: _start,
                    now: now,
                    hint: _autoStart ? 'з кінця попередньої' : null,
                    onChanged: (v) => setState(() {
                      _start = v;
                      _autoStart = false;
                      _error = null;
                    }),
                  ),
                  const Divider(height: 1),
                  _TimeRow(
                    label: 'Кінець',
                    value: _end,
                    now: now,
                    hint: _end == null ? 'триває (таймер)' : null,
                    onChanged: (v) => setState(() {
                      _end = v;
                      _error = null;
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              dur.inSeconds > 0
                  ? 'Тривалість: ${formatDuration(dur)}'
                  : 'Кінець має бути пізніше за початок',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: dur.inSeconds > 0 ? scheme.primary : scheme.error,
              ),
            ),
            if (!_isEdit && !_autoStart && widget.start == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Попередньої активності немає — вкажи, з котрої години',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            if (clash.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Перетинається з: ${clash.map((a) => '${catMap[a.categoryId]?.name ?? '?'} ${hm(a.start)}–${a.end == null ? 'зараз' : hm(a.end!)}').join(', ')}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFF57C00),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Коментар (необов\'язково)',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_categoryId == null) {
      setState(() => _error = 'Вибери, що робив');
      return;
    }
    final now = ref.read(activityClockProvider)();
    if (_end != null && !_end!.isAfter(_start)) {
      setState(() => _error = 'Кінець має бути пізніше за початок');
      return;
    }
    if (_end == null && _start.isAfter(now)) {
      setState(() => _error = 'Таймер не може починатись у майбутньому');
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .saveActivity(
          id: widget.activity?.id,
          categoryId: _categoryId!,
          start: _start,
          end: _end,
          note: _note.text,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final a = widget.activity!;
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    await db.setActivityDeleted(a.id, true);
    if (mounted) Navigator.of(context).pop();
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Активність видалено'),
          persist: false, // зникає сама, навіть з кнопкою
          action: SnackBarAction(
            label: 'Скасувати',
            onPressed: () => db.setActivityDeleted(a.id, false),
          ),
        ),
      );
  }
}

/// Рядок «Початок / Кінець»: дата й час, дотик — змінити.
class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.label,
    required this.value,
    required this.now,
    required this.onChanged,
    this.hint,
  });
  final String label;
  final DateTime? value;
  final DateTime now;
  final String? hint;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final v = value ?? now;
    return ListTile(
      title: Text(label),
      subtitle: hint == null ? null : Text(hint!),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: v,
                firstDate: DateTime(now.year - 5),
                lastDate: DateTime(now.year + 1),
              );
              if (d != null) {
                onChanged(DateTime(d.year, d.month, d.day, v.hour, v.minute));
              }
            },
            child: Text(activityDayLabel(v, now)),
          ),
          TextButton(
            onPressed: () async {
              final t = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(v),
                builder: (ctx, child) => MediaQuery(
                  data: MediaQuery.of(ctx)
                      .copyWith(alwaysUse24HourFormat: true),
                  child: child!,
                ),
              );
              if (t != null) {
                onChanged(DateTime(v.year, v.month, v.day, t.hour, t.minute));
              }
            },
            child: Text(
              hm(v),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Категорії активностей ----------------

class ActivityCategoriesScreen extends ConsumerWidget {
  const ActivityCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats =
        ref.watch(activityCategoriesProvider).value ??
        const <ActivityCategory>[];
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Категорії активностей')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Нова категорія',
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ActivityCategoryEditScreen()),
        ),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88, top: 8),
        children: [
          for (final c in cats)
            Opacity(
              opacity: c.hidden ? 0.5 : 1,
              child: ListTile(
                leading: ActivityAvatar(category: c),
                title: Text(c.name),
                subtitle: Text(
                  c.hidden
                      ? '${kindLabel(c.kind)} · прихована'
                      : kindLabel(c.kind),
                  style: TextStyle(color: _kindColor(c.kind, scheme)),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ActivityCategoryEditScreen(category: c),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

Color _kindColor(ActivityKind k, ColorScheme scheme) => switch (k) {
  ActivityKind.useful => const Color(0xFF2E7D32),
  ActivityKind.neutral => scheme.onSurfaceVariant,
  ActivityKind.waste => const Color(0xFFC62828),
};

class ActivityCategoryEditScreen extends ConsumerStatefulWidget {
  const ActivityCategoryEditScreen({super.key, this.category});
  final ActivityCategory? category;

  @override
  ConsumerState<ActivityCategoryEditScreen> createState() =>
      _ActivityCategoryEditScreenState();
}

class _ActivityCategoryEditScreenState
    extends ConsumerState<ActivityCategoryEditScreen> {
  late final TextEditingController _name;
  late String _icon;
  late int _color;
  late ActivityKind _kind;
  late bool _hidden;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    _name = TextEditingController(text: c?.name ?? '');
    _icon = c?.icon ?? 'other';
    _color = c?.color ?? categoryColors.first;
    _kind = c?.kind ?? ActivityKind.neutral;
    _hidden = c?.hidden ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.category == null ? 'Нова категорія' : 'Категорія'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              autofocus: widget.category == null,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Назва',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _nameError = null),
            ),
            Text('Продуктивність', style: text.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<ActivityKind>(
              showSelectedIcon: false,
              segments: [
                for (final k in ActivityKind.values)
                  ButtonSegment(
                    value: k,
                    label: Text(kindLabel(k), textAlign: TextAlign.center),
                  ),
              ],
              selected: {_kind},
              onSelectionChanged: (v) => setState(() => _kind = v.first),
            ),
            const SizedBox(height: 16),
            Text('Колір', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in categoryColors)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color
                              ? Theme.of(context).colorScheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Іконка', style: text.titleSmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in activityIcons.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: e.key == _icon
                            ? Color(_color).withValues(alpha: 0.15)
                            : null,
                        border: Border.all(
                          color: e.key == _icon
                              ? Color(_color)
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        e.value,
                        color: e.key == _icon ? Color(_color) : null,
                      ),
                    ),
                  ),
              ],
            ),
            if (widget.category != null)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Приховати'),
                subtitle: const Text(
                  'Не показувати при додаванні. Старі записи й статистика лишаються.',
                ),
                value: _hidden,
                onChanged: (v) => setState(() => _hidden = v),
              ),
            const SizedBox(height: 16),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Введи назву');
      return;
    }
    await ref
        .read(databaseProvider)
        .saveActivityCategory(
          id: widget.category?.id,
          name: _name.text,
          icon: _icon,
          color: _color,
          kind: _kind,
          hidden: _hidden,
        );
    if (mounted) Navigator.of(context).pop();
  }
}
