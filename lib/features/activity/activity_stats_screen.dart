import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/database.dart';
import 'activity_logic.dart';
import 'activity_screen.dart';
import 'activity_stats.dart';

/// Статистика Activity (етап 15).

const _usefulColor = Color(0xFF2E7D32);
const _neutralColor = Color(0xFF90A4AE);
const _wasteColor = Color(0xFFC62828);

Color kindColor(ActivityKind k) => switch (k) {
  ActivityKind.useful => _usefulColor,
  ActivityKind.neutral => _neutralColor,
  ActivityKind.waste => _wasteColor,
};

class ActivityStatsScreen extends ConsumerStatefulWidget {
  const ActivityStatsScreen({super.key, this.kind = ActivityPeriodKind.week});
  final ActivityPeriodKind kind;

  @override
  ConsumerState<ActivityStatsScreen> createState() =>
      _ActivityStatsScreenState();
}

class _ActivityStatsScreenState extends ConsumerState<ActivityStatsScreen> {
  late ActivityPeriod _period = ActivityPeriod.of(
    widget.kind,
    ref.read(activityClockProvider)(),
  );

  static const _labels = {
    ActivityPeriodKind.day: 'День',
    ActivityPeriodKind.week: 'Тиждень',
    ActivityPeriodKind.month: 'Місяць',
    ActivityPeriodKind.custom: 'Свій',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(activityClockProvider)();
    final list = ref.watch(activitiesProvider).value ?? const <Activity>[];
    final cats = ref.watch(activityCategoryMapProvider);
    final stats = computeActivityStats(
      activities: list,
      categories: cats,
      period: _period,
      now: now,
    );
    // Період ще триває — порівнюємо з таким самим відрізком попереднього
    // (пн–пт цього тижня з пн–пт минулого), інакше порівняння нечесне.
    final prevPeriod = _period.shift(-1);
    final ongoing = !now.isBefore(_period.start) && now.isBefore(_period.end);
    final prevNow = ongoing
        ? prevPeriod.start.add(now.difference(_period.start))
        : now;
    final prev = computeActivityStats(
      activities: list,
      categories: cats,
      period: prevPeriod,
      now: prevNow,
    );
    final future = _period.start.isAfter(now);

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика Activity')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<ActivityPeriodKind>(
                showSelectedIcon: false,
                segments: [
                  for (final k in ActivityPeriodKind.values)
                    ButtonSegment(value: k, label: Text(_labels[k]!)),
                ],
                selected: {_period.kind},
                onSelectionChanged: (s) async {
                  final k = s.first;
                  if (k == ActivityPeriodKind.custom) {
                    await _pickRange();
                  } else {
                    setState(() => _period = ActivityPeriod.of(k, now));
                  }
                },
              ),
            ),
            Row(
              children: [
                IconButton(
                  tooltip: 'Попередній період',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _period = _period.shift(-1)),
                ),
                Expanded(
                  child: Text(
                    _period.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Наступний період',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _period.shift(1).start.isAfter(now)
                      ? null
                      : () => setState(() => _period = _period.shift(1)),
                ),
              ],
            ),
            if (stats.total == Duration.zero)
              Padding(
                padding: const EdgeInsets.all(40),
                child: Text(
                  future
                      ? 'Цей період ще не настав'
                      : 'За цей період нічого не записано',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else ...[
              _ProductivityCard(stats: stats, prev: prev),
              const SizedBox(height: 16),
              _Pie(stats: stats, categories: cats),
              if (stats.days.length > 1) ...[
                const SizedBox(height: 20),
                Text('По днях', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 8),
                _DaysChart(stats: stats),
                const SizedBox(height: 4),
                _Legend(),
              ],
              const SizedBox(height: 20),
              Text('Категорії', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              for (final c in stats.byCategory)
                _CategoryRow(
                  item: c,
                  category: cats[c.categoryId],
                  stats: stats,
                  prev: prev.timeOf(c.categoryId),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ActivityCategoryRecordsScreen(
                        categoryId: c.categoryId,
                        period: _period,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                ongoing
                    ? 'Порівняння — з тим самим відрізком попереднього періоду '
                          '(${prevPeriod.label}, до ${DateFormat('d MMM, HH:mm', 'uk').format(prevNow)}).'
                    : 'Порівняння — з попереднім таким самим періодом (${prevPeriod.label}).',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange() async {
    final now = ref.read(activityClockProvider)();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: DateTimeRange(
        start: _period.start,
        end: DateTime(_period.end.year, _period.end.month, _period.end.day - 1),
      ),
    );
    if (r != null) {
      setState(() => _period = ActivityPeriod.custom(r.start, r.end));
    }
  }
}

class _ProductivityCard extends StatelessWidget {
  const _ProductivityCard({required this.stats, required this.prev});
  final ActivityStats stats;
  final ActivityStats prev;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = stats.total;
    Widget seg(ActivityKind k) {
      final share = stats.share(k);
      return share <= 0
          ? const SizedBox.shrink()
          : Expanded(
              flex: math.max(1, (share * 1000).round()),
              child: Container(height: 12, color: kindColor(k)),
            );
    }

    final usefulDelta =
        stats.share(ActivityKind.useful) - prev.share(ActivityKind.useful);
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Записано ${formatDuration(total)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (stats.elapsedDays > 1)
                  Text(
                    '≈ ${formatDuration(stats.averagePerDay(total))} / день',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Row(
                children: [for (final k in ActivityKind.values) seg(k)],
              ),
            ),
            const SizedBox(height: 10),
            for (final k in ActivityKind.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: kindColor(k),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: Text(kindLabel(k))),
                    Text(
                      '${formatDuration(stats.byKind[k] ?? Duration.zero)} · ${percent(stats.share(k))}',
                      style: TextStyle(
                        color: k == ActivityKind.neutral ? null : kindColor(k),
                      ),
                    ),
                  ],
                ),
              ),
            if (prev.total > Duration.zero) ...[
              const SizedBox(height: 8),
              Text(
                usefulDelta.abs() < 0.01
                    ? 'Частка корисного — як у попередньому періоді'
                    : 'Частка корисного ${usefulDelta > 0 ? 'зросла' : 'впала'} на '
                          '${(usefulDelta.abs() * 100).round()} п. п. порівняно з попереднім періодом',
                style: TextStyle(
                  fontSize: 12,
                  color: usefulDelta >= 0.01
                      ? _usefulColor
                      : (usefulDelta <= -0.01
                            ? _wasteColor
                            : scheme.onSurfaceVariant),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie({required this.stats, required this.categories});
  final ActivityStats stats;
  final Map<String, ActivityCategory> categories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 200,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: stats.byCategory.length > 1 ? 2 : 0,
              centerSpaceRadius: 62,
              sections: [
                for (final c in stats.byCategory)
                  PieChartSectionData(
                    value: c.duration.inSeconds.toDouble(),
                    color: Color(categories[c.categoryId]?.color ?? 0xFF9E9E9E),
                    radius: 34,
                    showTitle: false,
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Разом',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              Text(
                formatDuration(stats.total),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Стовпчики по днях: корисне / нейтральне / марнування один над одним (у годинах).
class _DaysChart extends StatelessWidget {
  const _DaysChart({required this.stats});
  final ActivityStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final days = stats.days;
    final maxH = days.fold<double>(
      0,
      (m, d) => math.max(m, d.total.inMinutes / 60),
    );
    final top = math.max(4, (maxH / 4).ceil() * 4).toDouble();
    final step = days.length > 14 ? 5 : 1;
    final rodWidth = (240 / days.length).clamp(4.0, 22.0);
    double h(Duration? d) => (d ?? Duration.zero).inMinutes / 60;

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          maxY: top,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: top / 4,
            getDrawingHorizontalLine: (_) =>
                FlLine(color: scheme.outlineVariant, strokeWidth: 0.6),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                interval: top / 4,
                getTitlesWidget: (v, meta) => SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${v.round()} г',
                    style: TextStyle(
                      fontSize: 10,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= days.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  final d = days[i].day;
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      days.length <= 7
                          ? DateFormat('EE', 'uk').format(d)
                          : '${d.day}',
                      style: TextStyle(
                        fontSize: 10,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, _, rod, _) {
                final d = days[group.x];
                return BarTooltipItem(
                  '${DateFormat('d MMM', 'uk').format(d.day)}\n'
                  'корисне ${formatDuration(d.byKind[ActivityKind.useful] ?? Duration.zero)}\n'
                  'марнування ${formatDuration(d.byKind[ActivityKind.waste] ?? Duration.zero)}\n'
                  'усього ${formatDuration(d.total)}',
                  TextStyle(color: scheme.onInverseSurface, fontSize: 11),
                );
              },
            ),
          ),
          barGroups: [
            for (var i = 0; i < days.length; i++)
              () {
                final u = h(days[i].byKind[ActivityKind.useful]);
                final n = h(days[i].byKind[ActivityKind.neutral]);
                final w = h(days[i].byKind[ActivityKind.waste]);
                return BarChartGroupData(
                  x: i,
                  barRods: [
                    BarChartRodData(
                      toY: u + n + w,
                      width: rodWidth,
                      borderRadius: BorderRadius.zero,
                      rodStackItems: [
                        BarChartRodStackItem(0, u, _usefulColor),
                        BarChartRodStackItem(u, u + n, _neutralColor),
                        BarChartRodStackItem(u + n, u + n + w, _wasteColor),
                      ],
                    ),
                  ],
                );
              }(),
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 14,
      children: [
        for (final k in ActivityKind.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, color: kindColor(k)),
              const SizedBox(width: 4),
              Text(kindLabel(k), style: const TextStyle(fontSize: 11)),
            ],
          ),
      ],
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.item,
    required this.category,
    required this.stats,
    required this.prev,
    required this.onTap,
  });
  final CategoryTime item;
  final ActivityCategory? category;
  final ActivityStats stats;
  final Duration prev;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = stats.total.inSeconds == 0
        ? 0.0
        : item.duration.inSeconds / stats.total.inSeconds;
    final delta = item.duration - prev;
    final kind = category?.kind ?? ActivityKind.neutral;
    // Більше корисного / менше марнування — добре (зелене).
    final good = kind == ActivityKind.useful
        ? !delta.isNegative
        : delta.isNegative;
    final parts = [
      percent(share),
      if (stats.elapsedDays > 1)
        '≈ ${formatDuration(stats.averagePerDay(item.duration))} / день',
    ];
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            ActivityAvatar(category: category),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category?.name ?? 'Без категорії',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    parts.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: share,
                      minHeight: 5,
                      color: Color(category?.color ?? 0xFF9E9E9E),
                      backgroundColor: scheme.surfaceContainerHighest,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatDuration(item.duration),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (prev > Duration.zero || delta > Duration.zero)
                  Text(
                    formatDelta(delta),
                    style: TextStyle(
                      fontSize: 11,
                      color:
                          delta.inMinutes.abs() < 1 ||
                              kind == ActivityKind.neutral
                          ? scheme.onSurfaceVariant
                          : (good ? _usefulColor : _wasteColor),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Записи однієї категорії за період ----------------

class ActivityCategoryRecordsScreen extends ConsumerWidget {
  const ActivityCategoryRecordsScreen({
    super.key,
    required this.categoryId,
    required this.period,
  });
  final String categoryId;
  final ActivityPeriod period;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(activityClockProvider)();
    final cat = ref.watch(activityCategoryMapProvider)[categoryId];
    final list =
        (ref.watch(activitiesProvider).value ?? const <Activity>[])
            .where(
              (a) =>
                  !a.deleted &&
                  a.categoryId == categoryId &&
                  a.start.isBefore(period.end) &&
                  (a.end ?? now).isAfter(period.start),
            )
            .toList()
          ..sort((a, b) => b.start.compareTo(a.start));
    final total = list.fold<Duration>(
      Duration.zero,
      (s, a) => s + (a.end ?? now).difference(a.start),
    );
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(cat?.name ?? 'Категорія')),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              '${period.label} · ${list.length} записів · ${formatDuration(total)}',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
          for (final a in list)
            ListTile(
              leading: ActivityAvatar(category: cat),
              title: Text(activityDayLabel(a.start, now)),
              subtitle: Text(
                [
                  '${hm(a.start)} – ${a.end == null ? 'зараз' : hm(a.end!)}',
                  ?a.note,
                ].join(' · '),
              ),
              trailing: Text(
                a.end == null
                    ? 'триває'
                    : formatDuration(a.end!.difference(a.start)),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onTap: () => openActivityForm(context, activity: a),
            ),
        ],
      ),
    );
  }
}
