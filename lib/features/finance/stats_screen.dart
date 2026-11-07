import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import 'finance_providers.dart';
import 'stats.dart';
import 'widgets/category_avatar.dart';
import 'widgets/period_selector.dart';
import '../wallets/wallet_widgets.dart';
import 'category_entries_screen.dart';

/// Статистика за вибраний період: підсумки, категорії, динаміка, баланс.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  EntryType _pieType = EntryType.expense;

  @override
  Widget build(BuildContext context) {
    final stats = ref.watch(statsProvider);
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};

    return Scaffold(
      appBar: AppBar(title: const Text('Статистика')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const PeriodSelector(),
            const SizedBox(height: 4),
            const _CurrencyFilter(),
            const SizedBox(height: 4),
            const WalletFilterButton(),
            const SizedBox(height: 8),
            ...stats.when(
              loading: () => [
                const Padding(
                  padding: EdgeInsets.all(48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
              error: (e, _) => [Text('Помилка: $e')],
              data: (s) => _content(context, s, categories),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    PeriodStats s,
    Map<String, Category> categories,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final empty = s.incomeCents == 0 && s.expenseCents == 0;
    final byCat = _pieType == EntryType.expense
        ? s.expenseByCategory
        : s.incomeByCategory;
    final pieTotal = _pieType == EntryType.expense
        ? s.expenseCents
        : s.incomeCents;

    return [
      if (s.onlyCurrency)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Лише записи в ${s.currency}, суми без перерахунку',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
      _SummaryRow(stats: s),
      if (s.skippedCount > 0)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Не враховано записів без курсу валюти: ${s.skippedCount}',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.expense, fontSize: 12),
          ),
        ),
      if (empty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Text(
            'За цей період записів немає',
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant),
          ),
        )
      else ...[
        _SectionTitle('За категоріями'),
        SegmentedButton<EntryType>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: EntryType.expense, label: Text('Витрати')),
            ButtonSegment(value: EntryType.income, label: Text('Надходження')),
          ],
          selected: {_pieType},
          onSelectionChanged: (v) => setState(() => _pieType = v.first),
        ),
        const SizedBox(height: 16),
        if (byCat.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              _pieType == EntryType.expense
                  ? 'Витрат за період немає'
                  : 'Надходжень за період немає',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          )
        else ...[
          _CategoryDonut(
            items: byCat,
            categories: categories,
            totalCents: pieTotal,
            currency: s.currency,
          ),
          const SizedBox(height: 12),
          for (final c in byCat)
            _CategoryRow(
              item: c,
              category: categories[c.categoryId],
              currency: s.currency,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CategoryEntriesScreen(
                    categoryId: c.categoryId,
                    type: _pieType,
                    period: s.period,
                    onlyCurrency: s.onlyCurrency ? s.currency : null,
                  ),
                ),
              ),
            ),
        ],
        _SectionTitle(_barsTitle(s.bucketSize)),
        _Legend(),
        const SizedBox(height: 8),
        _IncomeExpenseBars(stats: s),
        _SectionTitle(
          s.onlyCurrency
              ? 'Накопичено в ${s.currency} (надходження − витрати)'
              : 'Баланс',
        ),
        _BalanceLine(stats: s),
      ],
    ];
  }

  static String _barsTitle(BucketSize size) => switch (size) {
    BucketSize.day => 'Надходження й витрати по днях',
    BucketSize.week => 'Надходження й витрати по тижнях',
    BucketSize.month => 'Надходження й витрати по місяцях',
  };
}

// ---------------- Підсумки ----------------

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.stats});
  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            _cell(
              context,
              'Надходження',
              formatMoney(stats.incomeCents, stats.currency, sign: 1),
              AppColors.income,
            ),
            _cell(
              context,
              'Витрати',
              formatMoney(stats.expenseCents, stats.currency, sign: -1),
              AppColors.expense,
            ),
            _cell(
              context,
              'Різниця',
              formatMoney(
                stats.netCents,
                stats.currency,
                sign: stats.netCents > 0 ? 1 : 0,
              ),
              stats.netCents < 0 ? AppColors.expense : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String label, String value, Color? color) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 12),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------- Категорії ----------------

class _CategoryDonut extends StatelessWidget {
  const _CategoryDonut({
    required this.items,
    required this.categories,
    required this.totalCents,

    required this.currency,
  });

  final List<CategoryTotal> items;
  final Map<String, Category> categories;
  final int totalCents;
  final String currency;

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
              sectionsSpace: items.length > 1 ? 2 : 0,
              centerSpaceRadius: 62,
              sections: [
                for (final c in items)
                  PieChartSectionData(
                    value: c.cents.toDouble(),
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
                formatMoney(totalCents, currency),
                style: const TextStyle(
                  fontSize: 16,
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

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.item,
    required this.category,
    required this.currency,
    required this.onTap,
  });
  final CategoryTotal item;
  final Category? category;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(category?.color ?? 0xFF9E9E9E);
    final pct = NumberFormat.decimalPercentPattern(
      locale: 'uk',
      decimalDigits: item.share < 0.1 ? 1 : 0,
    ).format(item.share);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            CategoryAvatar(category: category, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          category?.name ?? 'Без категорії',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        formatMoney(item.cents, currency),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: item.share,
                            minHeight: 6,
                            color: color,
                            backgroundColor: scheme.surfaceContainerHighest,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text(
                          pct,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------- Стовпчики ----------------

class _Legend extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget item(Color c, String t) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 6),
        Text(t, style: const TextStyle(fontSize: 12)),
      ],
    );
    return Row(
      children: [
        item(AppColors.income, 'Надходження'),
        const SizedBox(width: 16),
        item(AppColors.expense, 'Витрати'),
      ],
    );
  }
}

/// «Круглий» крок сітки: 1, 2, 2,5 або 5 × 10ⁿ, щоб вийшло ~4 лінії.
double _niceStep(double range, {int target = 4}) {
  if (range <= 0) return 1;
  final raw = range / target;
  final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
  for (final m in const [1.0, 2.0, 2.5, 5.0, 10.0]) {
    if (m * mag >= raw) return m * mag;
  }
  return 10 * mag;
}

/// Короткий підпис осі: «2,5к» замість «2500». Точність залежить від кроку сітки.
String _axisLabel(double v, double step) {
  if (v.abs() >= 1000) {
    final digits = step >= 1000
        ? (step % 1000 == 0 ? 0 : 1)
        : (step >= 100 ? 1 : 2);
    return '${NumberFormat.decimalPatternDigits(locale: 'uk', decimalDigits: digits).format(v / 1000)}к';
  }
  return NumberFormat.decimalPatternDigits(
    locale: 'uk',
    decimalDigits: step < 1 ? 2 : 0,
  ).format(v);
}

/// Підпис лише на лініях сітки (fl_chart додає ще підписи min / max).
bool _onGrid(double v, double step) =>
    ((v / step) - (v / step).round()).abs() < 1e-6;

/// Крок підписів по осі X, щоб вони не налазили один на одного.
int _labelStep(int count) => math.max(1, (count / 7).ceil());

class _IncomeExpenseBars extends StatelessWidget {
  const _IncomeExpenseBars({required this.stats});
  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = stats.buckets;
    final maxY =
        b.fold<int>(
          0,
          (m, x) => math.max(m, math.max(x.incomeCents, x.expenseCents)),
        ) /
        100;
    final rodWidth = (220 / (b.length * 2)).clamp(3.0, 14.0);
    final step = _labelStep(b.length);
    final yStep = _niceStep(maxY == 0 ? 1 : maxY);
    final yTop = math.max(1, (maxY / yStep).ceil()) * yStep;

    return SizedBox(
      height: 220,
      child: BarChart(
        BarChartData(
          maxY: yTop,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: yStep,
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
                reservedSize: 40,
                interval: yStep,
                getTitlesWidget: (v, meta) => !_onGrid(v, yStep)
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _axisLabel(v, yStep),
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
                reservedSize: 26,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (i < 0 || i >= b.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      b[i].label,
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
              getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                '${b[group.x].label}\n${formatMoney((rod.toY * 100).round(), stats.currency)}',
                TextStyle(color: scheme.onInverseSurface, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < b.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  BarChartRodData(
                    toY: b[i].incomeCents / 100,
                    color: AppColors.income,
                    width: rodWidth,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                  BarChartRodData(
                    toY: b[i].expenseCents / 100,
                    color: AppColors.expense,
                    width: rodWidth,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
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

// ---------------- Лінія балансу ----------------

class _BalanceLine extends StatelessWidget {
  const _BalanceLine({required this.stats});
  final PeriodStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final b = stats.buckets;
    // Майбутні проміжки не малюємо: баланс там ще невідомий.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final shown = b.where((x) => !x.start.isAfter(today)).toList();
    final values = [
      for (final x in (shown.isEmpty ? b.take(1) : shown))
        x.balanceAtEndCents / 100,
    ];
    final lo = values.reduce(math.min), hi = values.reduce(math.max);
    final yStep = _niceStep(
      hi - lo > 0 ? hi - lo : math.max(hi.abs() * 0.2, 10),
    );
    var minY = (lo / yStep).floor() * yStep;
    var maxY = (hi / yStep).ceil() * yStep;
    if (maxY - minY < yStep * 2) {
      minY -= yStep;
      maxY += yStep;
    }
    if (lo >= 0 && minY < 0) minY = 0;
    final step = _labelStep(b.length);

    return SizedBox(
      height: 200,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (b.length - 1).toDouble().clamp(1, double.infinity),
          minY: minY,
          maxY: maxY,
          gridData: FlGridData(
            drawVerticalLine: false,
            horizontalInterval: yStep,
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
                reservedSize: 40,
                interval: yStep,
                getTitlesWidget: (v, meta) => !_onGrid(v, yStep)
                    ? const SizedBox.shrink()
                    : SideTitleWidget(
                        meta: meta,
                        child: Text(
                          _axisLabel(v, yStep),
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
                reservedSize: 26,
                interval: 1,
                getTitlesWidget: (v, meta) {
                  final i = v.toInt();
                  if (v != i || i < 0 || i >= b.length || i % step != 0) {
                    return const SizedBox.shrink();
                  }
                  return SideTitleWidget(
                    meta: meta,
                    child: Text(
                      b[i].label,
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
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    '${b[s.x.toInt()].label}\n${formatMoney((s.y * 100).round(), stats.currency)}',
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < values.length; i++)
                  FlSpot(i.toDouble(), values[i]),
              ],
              color: scheme.primary,
              barWidth: 2.5,
              isCurved: false,
              dotData: FlDotData(show: b.length <= 14),
              belowBarData: BarAreaData(
                show: true,
                color: scheme.primary.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Перемикач «Усі / EUR / UAH / …» — валюти, які є в гаманцях.
class _CurrencyFilter extends ConsumerWidget {
  const _CurrencyFilter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(statsCurrencyProvider);
    // Валюти, у яких є гроші або рухи: з гаманців і з записів / переказів.
    final codes = sortCurrencies(
      [
        ...(ref.watch(walletCurrenciesProvider).value ??
                const <WalletCurrency>[])
            .map((c) => c.currency),
        ...(ref.watch(movementsProvider).value ?? const []).map(
          (m) => m.currency,
        ),
        ?selected,
      ].where(isFiat),
    );
    final notifier = ref.read(statsCurrencyProvider.notifier);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Усі'),
            selected: selected == null,
            onSelected: (_) => notifier.set(null),
          ),
          for (final c in codes)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: ChoiceChip(
                label: Text(c),
                selected: selected == c,
                onSelected: (_) => notifier.set(c),
              ),
            ),
        ],
      ),
    );
  }
}
