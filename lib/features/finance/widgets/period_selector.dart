import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../finance_providers.dart';
import '../period.dart';

/// Перемикач періоду: тиждень / місяць / рік / свій + стрілки «назад / вперед».
class PeriodSelector extends ConsumerWidget {
  const PeriodSelector({super.key});

  static const _labels = {
    PeriodKind.week: 'Тиждень',
    PeriodKind.month: 'Місяць',
    PeriodKind.year: 'Рік',
    PeriodKind.custom: 'Свій',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final period = ref.watch(periodProvider);
    final notifier = ref.read(periodProvider.notifier);

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<PeriodKind>(
            showSelectedIcon: false,
            segments: [
              for (final k in PeriodKind.values)
                ButtonSegment(value: k, label: Text(_labels[k]!)),
            ],
            selected: {period.kind},
            onSelectionChanged: (s) async {
              final kind = s.first;
              if (kind == PeriodKind.custom) {
                await _pickRange(context, notifier, period);
              } else {
                notifier.setKind(kind);
              }
            },
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            IconButton(
              tooltip: 'Попередній період',
              icon: const Icon(Icons.chevron_left),
              onPressed: period.canShift ? () => notifier.shift(-1) : null,
            ),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: period.kind == PeriodKind.custom
                    ? () => _pickRange(context, notifier, period)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    period.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Наступний період',
              icon: const Icon(Icons.chevron_right),
              onPressed: period.canShift ? () => notifier.shift(1) : null,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickRange(
    BuildContext context,
    PeriodNotifier notifier,
    Period current,
  ) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(
        start: current.start,
        end: current.lastDay,
      ),
      helpText: 'Вибери період',
      saveText: 'Готово',
    );
    if (range != null) notifier.setCustom(range.start, range.end);
  }
}
