import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/rates_service.dart';
import '../../sync/sync_controller.dart';
import '../assets/assets_screen.dart';
import '../settings/settings_screen.dart';
import '../wallets/wallets_screen.dart';
import 'entries_list_screen.dart';
import 'budgets.dart';
import 'capital.dart';
import 'budgets_screen.dart';
import 'finance_providers.dart';
import 'goals_screen.dart' show goalProgressProvider;
import 'period.dart';
import 'stats_screen.dart';
import 'templates_screen.dart';

/// Головний екран Finance: загальний баланс і кнопки надходжень / витрат.
class FinanceHomeScreen extends ConsumerStatefulWidget {
  const FinanceHomeScreen({super.key});

  @override
  ConsumerState<FinanceHomeScreen> createState() => _FinanceHomeScreenState();
}

class _FinanceHomeScreenState extends ConsumerState<FinanceHomeScreen> {
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    // Тихо оновлюємо курси, якщо вони застаріли (старші за 6 год).
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _refreshRates(manual: false),
    );
  }

  Future<void> _refreshRates({required bool manual}) async {
    if (_refreshing) return;
    setState(() => _refreshing = true);
    final service = ref.read(ratesServiceProvider);
    final result = manual
        ? await service.refresh()
        : await service.refreshIfStale();
    if (!mounted) return;
    setState(() => _refreshing = false);
    // Курси на дати записів (етап 10) — тихо, у фоні.
    unawaited(service.fillHistory().catchError((_) => false));
    if (manual) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(switch (result) {
            RatesRefreshResult.failed => 'Не вдалося оновити курси. Перевір інтернет — поки діють збережені.',
            _ => 'Курси оновлено',
          }),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final balance = ref.watch(balanceProvider);
    final rates = ref.watch(ratesProvider).value ?? const {};

    return Scaffold(
      appBar: AppBar(title: const Text('Finance')),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.zero,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Регулярні платежі, день яких настав (етап 12).
              const PendingPaymentsCard(),
              _BalanceCard(
                balance: balance,
                rates: rates,
                onTap: () => _open(context, const StatsScreen()),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 96,
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionTile(
                        label: '+ Надходження',
                        color: AppColors.income,
                        onTap: () => _open(
                          context,
                          const EntriesListScreen(type: EntryType.income),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _ActionTile(
                        label: '− Витрати',
                        color: AppColors.expense,
                        onTap: () => _open(
                          context,
                          const EntriesListScreen(type: EntryType.expense),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _RatesInfo(
                rates: rates,
                refreshing: _refreshing,
                onRefresh: () => _refreshRates(manual: true),
              ),
              const SizedBox(height: 8),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _open(context, const SettingsScreen()),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SyncStatusLine(
                    state: ref.watch(syncControllerProvider),
                    compact: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => _open(context, const WalletsScreen()),
                      icon: const Icon(Icons.account_balance_wallet_outlined),
                      label: const Text('Гаманці'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: () => _open(context, const AssetsScreen()),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text(
                        'Активи та пасиви',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const _BudgetsButton(),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: () => _open(context, const TemplatesScreen()),
                icon: const Icon(Icons.event_repeat_outlined),
                label: const Text('Шаблони й регулярні платежі'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

/// Кнопка «Бюджети» з коротким підсумком поточного місяця (етап 11).
class _BudgetsButton extends ConsumerWidget {
  const _BudgetsButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usages = ref.watch(
      budgetUsagesProvider(Period.of(PeriodKind.month, DateTime.now())),
    );
    final total = usages.where((u) => u.budget.categoryId == null).firstOrNull;
    final over = usages.where((u) => u.level == BudgetLevel.over).length;
    final parts = <String>[];
    if (total != null) parts.add('бюджет ${(total.share * 100).round()} %');
    if (over > 0) parts.add('перевищено: $over');
    if (usages.isNotEmpty && total == null && over == 0) parts.add('бюджети в межах');
    // Цілі (1.15): скільки активних і загальний прогрес.
    final goals = ref
        .watch(goalProgressProvider)
        .values
        .where((p) => !p.goal.archived)
        .toList();
    if (goals.isNotEmpty) {
      final reached = goals.where((p) => p.reached).length;
      parts.add('цілей: ${goals.length}${reached > 0 ? ' (досягнуто $reached)' : ''}');
    }
    final color = usages.isEmpty
        ? null
        : budgetColor(
            usages.map((u) => u.level).reduce((a, b) => a.index >= b.index ? a : b),
          );
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const BudgetsScreen()),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.pie_chart_outline, size: 18),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Бюджети та цілі'),
                if (parts.isNotEmpty)
                  Text(
                    parts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: color, fontSize: 12),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Картка балансу зі свайпом (правка після етапу 13): три сторінки —
/// гроші; гроші + активи; гроші + активи + речі. Дотик — статистика.
class _BalanceCard extends ConsumerStatefulWidget {
  const _BalanceCard({
    required this.balance,
    required this.rates,
    required this.onTap,
  });

  final AsyncValue<BalanceSummary> balance;
  final Map<String, ExchangeRate> rates;
  final VoidCallback onTap;

  static const height = 236.0;

  @override
  ConsumerState<_BalanceCard> createState() => _BalanceCardState();
}

class _BalanceCardState extends ConsumerState<_BalanceCard> {
  final _pages = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Сума в інших валютах: «≈ 621 950,12 ₴ · 13 790,45 \$».
  String _otherCurrencies(int eurCents) {
    final parts = [
      for (final c in RatesService.displayCurrencies)
        if (widget.rates[c] != null)
          formatMoney((eurCents * widget.rates[c]!.perEur).round(), c),
    ];
    return parts.isEmpty ? '' : '≈ ${parts.join(' · ')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = widget.balance.value;
    final capital = ref.watch(capitalProvider);
    final money = summary?.cents ?? 0;
    String fmt(int c) => formatMoney(c, baseCurrency);

    final pages = <Widget>[
      _buildPage(
        title: 'Загальний баланс',
        cents: summary?.cents,
        lines: [
          if (summary != null) _otherCurrencies(summary.cents),
        ],
        warning: summary != null && summary.skippedCount > 0
            ? 'Без залишку в ${summary.skippedByCurrency.keys.join(', ')} — '
                  'немає курсу, потрібен інтернет'
            : null,
      ),
      _buildPage(
        title: 'Баланс + активи',
        cents: summary == null ? null : money + capital.assetsCents,
        lines: [
          'гроші ${fmt(money)} · активи ${fmt(capital.assetsCents)}',
          'активи — за ціною купівлі',
        ],
        warning: capital.missing.isEmpty ? null : 'Немає курсу ${capital.missing.join(', ')}',
      ),
      _buildPage(
        title: 'Баланс + активи + пасиви',
        cents: summary == null
            ? null
            : money + capital.assetsCents + capital.belongingsCents,
        lines: [
          'гроші ${fmt(money)} · активи ${fmt(capital.assetsCents)} · '
              'речі ${fmt(capital.belongingsCents)}',
          'активи й речі — за ціною купівлі',
        ],
        warning: capital.missing.isEmpty ? null : 'Немає курсу ${capital.missing.join(', ')}',
      ),
    ];

    return Column(
      children: [
        SizedBox(
          height: _BalanceCard.height,
          child: PageView(
            controller: _pages,
            onPageChanged: (i) => setState(() => _page = i),
            children: pages,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pages.length; i++)
              GestureDetector(
                onTap: () => _pages.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
                child: AnimatedContainer(
                  key: ValueKey('balance-dot-$i'),
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: i == _page ? 18 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: i == _page ? scheme.primary : scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPage({
    required String title,
    required int? cents,
    required List<String> lines,
    String? warning,
  }) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: text.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              if (widget.balance.hasError)
                Text(
                  'Помилка: ${widget.balance.error}',
                  style: TextStyle(color: scheme.error),
                )
              else if (cents == null)
                const SizedBox(
                  height: 44,
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(cents, baseCurrency),
                    style: text.displaySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cents < 0 ? AppColors.expense : null,
                    ),
                  ),
                ),
              for (final l in lines.where((l) => l.isNotEmpty))
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    l,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
              if (warning != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    warning,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: AppColors.expense),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.bar_chart, size: 18, color: scheme.primary),
                  const SizedBox(width: 4),
                  Text('Статистика', style: TextStyle(color: scheme.primary)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Рядок з поточними курсами й часом оновлення.
class _RatesInfo extends StatelessWidget {
  const _RatesInfo({
    required this.rates,
    required this.refreshing,
    required this.onRefresh,
  });

  final Map<String, ExchangeRate> rates;
  final bool refreshing;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final small = Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: scheme.onSurfaceVariant);
    final shown = RatesService.displayCurrencies
        .where(rates.containsKey)
        .toList();

    final String line1;
    final String line2;
    if (shown.isEmpty) {
      line1 = 'Курсів валют ще немає';
      line2 = 'Завантажаться, щойно буде інтернет';
    } else {
      line1 = '1 € = ${shown.map((c) => _rateText(rates[c]!)).join(' · ')}';
      final fetched = shown
          .map((c) => rates[c]!.fetchedAt)
          .reduce((a, b) => a.isBefore(b) ? a : b);
      final sources = shown
          .map((c) => rates[c]!.source == 'NBU' ? 'НБУ' : 'ЄЦБ')
          .toSet()
          .join(' і ');
      line2 =
          'Курси $sources, оновлено ${DateFormat("dd.MM 'о' HH:mm", 'uk').format(fetched.toLocal())}';
    }

    return Row(
      children: [
        Icon(Icons.currency_exchange, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(line1, style: Theme.of(context).textTheme.bodyMedium),
              Text(line2, style: small),
            ],
          ),
        ),
        refreshing
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : IconButton(
                tooltip: 'Оновити курси',
                icon: const Icon(Icons.refresh),
                onPressed: onRefresh,
              ),
      ],
    );
  }

  static String _rateText(ExchangeRate r) {
    final f = NumberFormat.decimalPatternDigits(
      locale: 'uk',
      decimalDigits: r.perEur >= 10 ? 2 : 4,
    );
    return '${f.format(r.perEur)} ${currencySymbol(r.currency)}';
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.label,
    required this.color,
    required this.onTap,
  });

  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
