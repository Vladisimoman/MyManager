import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import 'finance_providers.dart';
import 'period.dart';
import 'widgets/category_avatar.dart';
import 'widgets/entry_list.dart';

/// Записи однієї категорії за період — відкривається зі статистики.
/// [onlyCurrency] — якщо в статистиці вибрано окрему валюту.
class CategoryEntriesScreen extends ConsumerWidget {
  const CategoryEntriesScreen({
    super.key,
    required this.categoryId,
    required this.type,
    required this.period,
    this.onlyCurrency,
  });

  final String categoryId;
  final EntryType type;
  final Period period;
  final String? onlyCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesProvider(type));
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    final category = categories[categoryId];
    final walletFilter = ref.watch(walletFilterProvider);
    final scheme = Theme.of(context).colorScheme;
    final isIncome = type == EntryType.income;

    return Scaffold(
      appBar: AppBar(title: Text(category?.name ?? 'Категорія')),
      body: SafeArea(
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Помилка: $e')),
          data: (all) {
            final list = all
                .where(
                  (e) =>
                      e.categoryId == categoryId &&
                      period.contains(e.date) &&
                      (walletFilter == null || e.walletId == walletFilter) &&
                      (onlyCurrency == null || e.currency == onlyCurrency),
                )
                .toList();
            final total = onlyCurrency != null
                ? list.fold<int>(0, (a, e) => a + e.amountCents)
                : sumInEur(
                    list,
                    rates,
                    history: ref.watch(rateHistoryProvider).value,
                  ).$1;
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                  child: Row(
                    children: [
                      CategoryAvatar(category: category, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              period.label,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              onlyCurrency == null
                                  ? 'Записів: ${list.length}'
                                  : 'Записів у $onlyCurrency: ${list.length}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(
                          total,
                          onlyCurrency ?? baseCurrency,
                          sign: isIncome ? 1 : -1,
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: isIncome
                              ? AppColors.income
                              : AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: list.isEmpty
                      ? Center(
                          child: Text(
                            'Записів немає',
                            style: TextStyle(color: scheme.onSurfaceVariant),
                          ),
                        )
                      : EntriesByDayList(
                          entries: list,
                          categories: categories,
                          rates: rates,
                          insideCategory: true,
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
