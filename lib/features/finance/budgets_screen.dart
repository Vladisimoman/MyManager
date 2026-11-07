import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/rates_service.dart';
import 'budgets.dart';
import 'category_entries_screen.dart';
import 'finance_providers.dart';
import 'goals_screen.dart' show GoalsTab;
import 'period.dart';
import 'widgets/category_avatar.dart';

/// Бюджети (етап 11): ліміти на місяць — загальний і по категоріях витрат.

final budgetsProvider = StreamProvider<List<Budget>>(
  (ref) => ref.watch(databaseProvider).watchBudgets(),
);

/// Використання бюджетів за місяць [month].
final budgetUsagesProvider = Provider.family<List<BudgetUsage>, Period>((
  ref,
  month,
) {
  final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
  final entries = ref.watch(allEntriesProvider).value ?? const <MoneyEntry>[];
  final rates =
      ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
  final history = ref.watch(rateHistoryProvider).value;
  return sortedUsages([
    for (final b in budgets)
      budgetUsage(
        budget: b,
        entries: entries,
        month: month,
        rates: rates,
        history: history,
      ),
  ]);
});

Color budgetColor(BudgetLevel level) => switch (level) {
  BudgetLevel.ok => AppColors.income,
  BudgetLevel.warning => const Color(0xFFF9A825),
  BudgetLevel.over => AppColors.expense,
};

/// Валюти на вибір для ліміту: EUR, гривня, долар і всі валюти гаманців.
List<String> budgetCurrencyOptions(WidgetRef ref, String current) {
  final inWallets =
      (ref.watch(walletCurrenciesProvider).value ?? const <WalletCurrency>[])
          .where((c) => !c.deleted)
          .map((c) => c.currency);
  return {
    baseCurrency,
    ...RatesService.displayCurrencies,
    ...inWallets,
    current,
  }.where(isFiat).toList();
}

/// «Бюджети та цілі»: дві вкладки.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Бюджети та цілі'),
          bottom: const TabBar(tabs: [Tab(text: 'Бюджети'), Tab(text: 'Цілі')]),
        ),
        body: const TabBarView(children: [BudgetsTab(), GoalsTab()]),
      ),
    );
  }
}

class BudgetsTab extends ConsumerStatefulWidget {
  const BudgetsTab({super.key});

  @override
  ConsumerState<BudgetsTab> createState() => _BudgetsTabState();
}

class _BudgetsTabState extends ConsumerState<BudgetsTab> {
  Period _month = Period.of(PeriodKind.month, DateTime.now());

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final usages = ref.watch(budgetUsagesProvider(_month));
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    // Слухаємо, щоб список категорій був готовий до натискання «Бюджет категорії».
    ref.watch(categoriesProvider(EntryType.expense));
    final total = usages.where((u) => u.budget.categoryId == null).firstOrNull;
    final cats = usages.where((u) => u.budget.categoryId != null).toList();
    final now = DateTime.now();
    final isCurrent = _month.contains(now);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'budget-fab',
        onPressed: () => _addCategoryBudget(context, usages),
        icon: const Icon(Icons.add),
        label: const Text('Бюджет категорії'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: 'Попередній місяць',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => setState(() => _month = _month.shift(-1)),
                ),
                Expanded(
                  child: Text(
                    _month.label,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Наступний місяць',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => setState(() => _month = _month.shift(1)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (total != null)
              _BudgetCard(
                usage: total,
                title: 'Загальний бюджет',
                leading: CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(
                    Icons.account_balance_outlined,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                daysLeft: isCurrent
                    ? _month.end
                          .difference(DateTime(now.year, now.month, now.day))
                          .inDays
                    : null,
                onTap: () => openBudgetEditor(context, budget: total.budget),
              )
            else
              Card(
                elevation: 0,
                color: scheme.surfaceContainerHigh,
                child: ListTile(
                  leading: const Icon(Icons.add_chart_outlined),
                  title: const Text('Задати загальний бюджет'),
                  subtitle: const Text('Ліміт на всі витрати за місяць'),
                  onTap: () => openBudgetEditor(context),
                ),
              ),
            const SizedBox(height: 16),
            if (cats.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Бюджетів для категорій ще немає.\nНатисни «Бюджет категорії» — '
                  'наприклад, «Кафе й ресторани» не більше 200 € на місяць.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              for (final u in cats)
                _BudgetCard(
                  usage: u,
                  title: categories[u.budget.categoryId]?.name ?? 'Категорія',
                  leading: CategoryAvatar(
                    category: categories[u.budget.categoryId],
                  ),
                  daysLeft: null,
                  onTap: () => openBudgetEditor(context, budget: u.budget),
                  onOpenEntries: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => CategoryEntriesScreen(
                        type: EntryType.expense,
                        categoryId: u.budget.categoryId!,
                        period: _month,
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 8),
            Text(
              'Записи в інших валютах перераховуються у валюту бюджету за курсом дати запису.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _addCategoryBudget(
    BuildContext context,
    List<BudgetUsage> usages,
  ) async {
    final taken = usages.map((u) => u.budget.categoryId).toSet();
    final all =
        ref.read(categoriesProvider(EntryType.expense)).value ??
        const <Category>[];
    final free = all.where((c) => !c.hidden && !taken.contains(c.id)).toList();
    if (free.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для всіх категорій уже є бюджет')),
      );
      return;
    }
    final picked = await showModalBottomSheet<Category>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  'Для якої категорії?',
                  style: TextStyle(fontSize: 18),
                ),
              ),
              for (final c in free)
                ListTile(
                  leading: CategoryAvatar(category: c),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(ctx, c),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && context.mounted) {
      openBudgetEditor(context, categoryId: picked.id);
    }
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({
    required this.usage,
    required this.title,
    required this.leading,
    required this.daysLeft,
    required this.onTap,
    this.onOpenEntries,
  });

  final BudgetUsage usage;
  final String title;
  final Widget leading;
  final int? daysLeft;
  final VoidCallback onTap;
  final VoidCallback? onOpenEntries;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = usage.budget.currency;
    final color = budgetColor(usage.level);
    final left = usage.leftCents;
    final String status;
    if (left < 0) {
      status = 'Перевищено на ${formatMoney(-left, c)}';
    } else if (daysLeft != null && daysLeft! > 0) {
      status =
          'Залишилось ${formatMoney(left, c)} · ≈ ${formatMoney(left ~/ daysLeft!, c)} на день';
    } else {
      status = 'Залишилось ${formatMoney(left, c)}';
    }
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: [
              leading,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${(usage.share * 100).round()} %',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: usage.share.clamp(0, 1).toDouble(),
                        minHeight: 8,
                        color: color,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatMoney(usage.spentCents, c)} / ${formatMoney(usage.limitCents, c)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: left < 0
                            ? AppColors.expense
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    if (usage.skipped > 0)
                      Text(
                        'Без курсу не враховано записів: ${usage.skipped}',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (onOpenEntries != null)
                IconButton(
                  tooltip: 'Записи',
                  icon: const Icon(Icons.list_alt_outlined),
                  onPressed: onOpenEntries,
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Ліміт: новий / зміна ----------------

void openBudgetEditor(
  BuildContext context, {
  Budget? budget,
  String? categoryId,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BudgetEditScreen(
        budget: budget,
        categoryId: budget?.categoryId ?? categoryId,
      ),
    ),
  );
}

class BudgetEditScreen extends ConsumerStatefulWidget {
  const BudgetEditScreen({super.key, this.budget, this.categoryId});

  final Budget? budget;

  /// null — загальний бюджет.
  final String? categoryId;

  @override
  ConsumerState<BudgetEditScreen> createState() => _BudgetEditScreenState();
}

class _BudgetEditScreenState extends ConsumerState<BudgetEditScreen> {
  late final TextEditingController _amount;
  late String _currency;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.budget;
    _amount = TextEditingController(
      text: b == null ? '' : centsToInput(b.limitCents),
    );
    _currency = b?.currency ?? baseCurrency;
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final category = widget.categoryId == null
        ? null
        : categories[widget.categoryId];
    final title = widget.categoryId == null
        ? 'Загальний бюджет'
        : (category?.name ?? 'Бюджет');
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (widget.budget != null)
            IconButton(
              tooltip: 'Прибрати бюджет',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.categoryId == null
                  ? 'Скільки максимум витрачати за місяць на все разом.'
                  : 'Скільки максимум витрачати за місяць на «$title».',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              autofocus: widget.budget == null,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: Theme.of(context).textTheme.titleLarge,
              decoration: InputDecoration(
                labelText: 'Ліміт на місяць',
                errorText: _error,
                suffixText: currencySymbol(_currency),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 12),
            Text('Валюта', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in budgetCurrencyOptions(ref, _currency))
                  ChoiceChip(
                    label: Text(c),
                    selected: c == _currency,
                    onSelected: (_) => setState(() => _currency = c),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Витрати в інших валютах перераховуються в $_currency за курсом дати запису.',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
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
    final cents = parseAmountToCents(_amount.text);
    if (cents == null || cents == 0) {
      setState(() => _error = 'Введи суму, напр. 200');
      return;
    }
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .setBudget(
          categoryId: widget.categoryId,
          limitCents: cents,
          currency: _currency,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    await ref.read(databaseProvider).deleteBudget(widget.budget!.id);
    if (mounted) Navigator.of(context).pop();
  }
}

// ---------------- Попередження у формі витрати ----------------

/// Картка під категоріями у формі витрати: «Кафе: буде 230 / 200 € — перевищення на 30 €».
class BudgetWarning extends ConsumerWidget {
  const BudgetWarning({
    super.key,
    required this.categoryId,
    required this.amountCents,
    required this.currency,
    required this.date,
    this.excludeEntryId,
  });

  final String categoryId;
  final int amountCents;
  final String currency;
  final DateTime date;
  final String? excludeEntryId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider).value ?? const <Budget>[];
    if (budgets.isEmpty || amountCents <= 0) return const SizedBox.shrink();
    final previews = previewExpense(
      budgets: budgets,
      entries: ref.watch(allEntriesProvider).value ?? const <MoneyEntry>[],
      categoryId: categoryId,
      amountCents: amountCents,
      currency: currency,
      date: date,
      rates: ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{},
      history: ref.watch(rateHistoryProvider).value,
      excludeEntryId: excludeEntryId,
    );
    if (previews.isEmpty) return const SizedBox.shrink();
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    return Column(
      children: [
        for (final p in previews)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: budgetColor(p.level).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  p.level == BudgetLevel.over
                      ? Icons.warning_amber_rounded
                      : Icons.info_outline,
                  color: budgetColor(p.level),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _text(p, categories),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static String _text(BudgetPreview p, Map<String, Category> categories) {
    final c = p.budget.currency;
    final name = p.budget.categoryId == null
        ? 'Загальний бюджет'
        : 'Бюджет «${categories[p.budget.categoryId]?.name ?? ''}»';
    final line =
        '$name: буде ${formatMoney(p.afterCents, c)} з ${formatMoney(p.budget.limitCents, c)}';
    return p.level == BudgetLevel.over
        ? '$line — перевищення на ${formatMoney(p.overCents, c)}'
        : '$line — понад ${(budgetWarningShare * 100).round()} %';
  }
}
