import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import 'finance_providers.dart';
import 'widgets/entry_list.dart';
import 'widgets/period_selector.dart';
import '../wallets/wallet_widgets.dart';

/// Як показувати список: за датою чи за категоріями. Запам'ятовується до закриття додатку.
class ListByCategoryNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool v) => state = v;
}

final listByCategoryProvider = NotifierProvider<ListByCategoryNotifier, bool>(
  ListByCategoryNotifier.new,
);

/// Список надходжень або витрат за вибраний період.
class EntriesListScreen extends ConsumerWidget {
  const EntriesListScreen({super.key, required this.type});

  final EntryType type;

  bool get _isIncome => type == EntryType.income;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(entriesProvider(type));
    final categories = ref.watch(categoryMapProvider).value ?? const {};
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    final period = ref.watch(periodProvider);
    final byCategory = ref.watch(listByCategoryProvider);
    final walletFilter = ref.watch(walletFilterProvider);
    final color = _isIncome ? AppColors.income : AppColors.expense;

    return Scaffold(
      appBar: AppBar(title: Text(_isIncome ? 'Надходження' : 'Витрати')),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 8),
            _AddButton(
              color: color,
              tooltip: _isIncome ? 'Додати надходження' : 'Додати витрату',
              onTap: () => openEntryForm(context, type),
            ),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: PeriodSelector(),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: WalletFilterButton(),
            ),
            Expanded(
              child: entries.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Помилка: $e')),
                data: (all) {
                  final list = all
                      .where(
                        (e) =>
                            period.contains(e.date) &&
                            (walletFilter == null ||
                                e.walletId == walletFilter),
                      )
                      .toList();
                  if (list.isEmpty) {
                    return _EmptyState(
                      isIncome: _isIncome,
                      anyAtAll: all.isNotEmpty,
                    );
                  }
                  return Column(
                    children: [
                      _PeriodTotal(
                        entries: list,
                        rates: rates,
                        isIncome: _isIncome,
                        byCategory: byCategory,
                        onToggle: (v) =>
                            ref.read(listByCategoryProvider.notifier).set(v),
                      ),
                      Expanded(
                        child: byCategory
                            ? EntriesByCategoryList(
                                entries: list,
                                categories: categories,
                                rates: rates,
                              )
                            : EntriesByDayList(
                                entries: list,
                                categories: categories,
                                rates: rates,
                              ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  final Color color;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const SizedBox(
            width: 64,
            height: 64,
            child: Icon(Icons.add, color: Colors.white, size: 36),
          ),
        ),
      ),
    );
  }
}

/// «Разом за період» + перемикач «За датою / За категоріями».
class _PeriodTotal extends ConsumerWidget {
  const _PeriodTotal({
    required this.entries,
    required this.rates,
    required this.isIncome,
    required this.byCategory,
    required this.onToggle,
  });

  final List<MoneyEntry> entries;
  final Map<String, ExchangeRate> rates;
  final bool isIncome;
  final bool byCategory;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (total, skipped) = sumInEur(
      entries,
      rates,
      history: ref.watch(rateHistoryProvider).value,
    );
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Разом за період',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                formatMoney(total, baseCurrency, sign: isIncome ? 1 : -1),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isIncome ? AppColors.income : AppColors.expense,
                ),
              ),
              if (skipped > 0)
                Tooltip(
                  message: 'Без $skipped записів — немає курсу валюти',
                  child: const Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(
                      Icons.info_outline,
                      size: 16,
                      color: AppColors.expense,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<bool>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: const [
                ButtonSegment(
                  value: false,
                  icon: Icon(Icons.calendar_today_outlined, size: 16),
                  label: Text('За датою'),
                ),
                ButtonSegment(
                  value: true,
                  icon: Icon(Icons.category_outlined, size: 16),
                  label: Text('За категоріями'),
                ),
              ],
              selected: {byCategory},
              onSelectionChanged: (v) => onToggle(v.first),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isIncome, this.anyAtAll = false});

  final bool isIncome;
  final bool anyAtAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          anyAtAll
              ? (isIncome
                    ? 'За цей період надходжень немає.'
                    : 'За цей період витрат немає.')
              : isIncome
              ? 'Надходжень ще немає.\nНатисни «+», щоб додати перше.'
              : 'Витрат ще немає.\nНатисни «+», щоб додати першу.',
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
