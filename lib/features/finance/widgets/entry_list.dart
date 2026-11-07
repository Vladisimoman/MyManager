import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/database.dart';
import '../../../data/rate_history.dart';
import '../entry_form_screen.dart';
import '../finance_providers.dart';
import 'category_avatar.dart';
import '../ledger.dart';
import '../../assets/belongings.dart' show openBelonging;
import '../../assets/trade_form_screen.dart';

/// Спільні частини списків записів: рядок запису, заголовок дня,
/// групування за датою й за категоріями, видалення зі «Скасувати».

String dayLabel(DateTime day, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final today = DateTime(n.year, n.month, n.day);
  final d = DateTime(day.year, day.month, day.day);
  final diff = today.difference(d).inDays;
  if (diff == 0) return 'Сьогодні';
  if (diff == 1) return 'Вчора';
  return DateFormat('d MMMM y', 'uk').format(d);
}

void openEntryForm(BuildContext context, EntryType type, {MoneyEntry? entry}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EntryFormScreen(type: type, entry: entry),
    ),
  );
}

/// М'яке видалення з кнопкою «Скасувати» у SnackBar.
Future<void> deleteEntryWithUndo(
  BuildContext context,
  WidgetRef ref,
  MoneyEntry e,
) async {
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await db.setEntryDeleted(e.id, true);
  } catch (err) {
    messenger.showSnackBar(
      SnackBar(content: Text('Не вдалося видалити: $err')),
    );
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Запис видалено'),
      persist: false, // зникає сама, навіть з кнопкою
      action: SnackBarAction(
        label: 'Скасувати',
        onPressed: () => db.setEntryDeleted(e.id, false),
      ),
    ),
  );
}

/// Сума записів у EUR; записи без курсу рахуються окремо.
(int cents, int skipped) sumInEur(
  Iterable<MoneyEntry> entries,
  Map<String, ExchangeRate> rates, {
  RateHistory? history,
}) {
  var total = 0, skipped = 0;
  for (final e in entries) {
    // За курсом дати запису (етап 10).
    final eur = toEurCentsOn(e.amountCents, e.currency, e.date, rates, history);
    if (eur == null) {
      skipped++;
    } else {
      total += eur;
    }
  }
  return (total, skipped);
}

class DayHeader extends StatelessWidget {
  const DayHeader({super.key, required this.day});

  final DateTime day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Text(
        dayLabel(day),
        style: Theme.of(context).textTheme.labelLarge
            ?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// Рядок запису: свайп вліво — видалити, тап — редагувати.
class EntryTile extends ConsumerWidget {
  const EntryTile({
    super.key,
    required this.entry,
    required this.category,
    required this.rates,
    this.insideCategory = false,
    this.showDate = false,
    this.inWalletHistory = false,
  });

  final MoneyEntry entry;
  final Category? category;
  final Map<String, ExchangeRate> rates;

  /// Запис усередині категорії: назву категорії не повторюємо —
  /// заголовок рядка — коментар (або дата, якщо [showDate]).
  final bool insideCategory;

  /// Дата як заголовок рядка (у розгорнутій категорії, де немає заголовків днів).
  final bool showDate;

  /// Історія гаманця: записи «лише для статистики» (прибуток / збиток від продажу
  /// активу) показуємо сірими — гроші вже враховано в сумі продажу.
  final bool inWalletHistory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isIncome = entry.type == EntryType.income;
    final color = isIncome ? AppColors.income : AppColors.expense;
    // Витрата активом: під сумою — скільки списано (0,01 BTC), а не ≈ €.
    final asset = entry.assetId == null
        ? null
        : ref.watch(assetMapProvider)[entry.assetId];
    final assetLine = entry.assetUnits == null
        ? null
        : formatUnits(entry.assetUnits!, asset?.code ?? '?', sign: -1);
    final eurCents = entry.currency == baseCurrency || assetLine != null
        ? null
        : toEurCentsOn(
            entry.amountCents,
            entry.currency,
            entry.date,
            rates,
            ref.watch(rateHistoryProvider).value,
          );
    // Прибуток / збиток від продажу активу керується операцією продажу.
    final fromTrade = entry.tradeId != null;
    // Купівля / продаж речі керується карткою речі (етап 9).
    final fromBelonging = entry.belongingId != null;
    final statsOnly = inWalletHistory && fromTrade;
    final String title;
    String? subtitle;
    if (!insideCategory) {
      title = category?.name ?? 'Без категорії';
      subtitle = entry.note;
    } else if (showDate) {
      title = dayLabel(entry.date);
      subtitle = entry.note;
    } else {
      title = entry.note ?? 'Без коментаря';
      subtitle = null;
    }
    if (statsOnly) {
      subtitle = [?subtitle, 'не змінює баланс (лише статистика)'].join('\n');
    }
    return Dismissible(
      key: ValueKey('dismiss-${entry.id}'),
      direction: fromTrade || fromBelonging
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        color: AppColors.expense,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => deleteEntryWithUndo(context, ref, entry),
      child: ListTile(
        onTap: () {
          if (fromBelonging) {
            openBelonging(context, entry.belongingId!);
            return;
          }
          if (!fromTrade) {
            openEntryForm(context, entry.type, entry: entry);
            return;
          }
          final trade = (ref.read(tradesProvider).value ?? const <AssetTrade>[])
              .where((t) => t.id == entry.tradeId)
              .firstOrNull;
          if (trade != null) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => TradeFormScreen(trade: trade)),
            );
          }
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        leading: insideCategory && showDate
            ? const SizedBox(width: 40) // відступ: запис вкладений у категорію
            : CategoryAvatar(category: category),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: insideCategory && entry.note == null && !showDate
              ? TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)
              : null,
        ),
        subtitle: subtitle == null
            ? null
            : Text(
                subtitle,
                maxLines: statsOnly ? 2 : 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatMoney(
                entry.amountCents,
                entry.currency,
                sign: isIncome ? 1 : -1,
              ),
              style: TextStyle(
                color: statsOnly
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : color,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            if (assetLine != null)
              Text(
                assetLine,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            if (eurCents != null)
              Text(
                '≈ ${formatMoney(eurCents, baseCurrency)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Записи, згруповані за днями (записи мають бути відсортовані: новіші зверху).
class EntriesByDayList extends StatelessWidget {
  const EntriesByDayList({
    super.key,
    required this.entries,
    required this.categories,
    required this.rates,
    this.insideCategory = false,
  });

  final List<MoneyEntry> entries;
  final Map<String, Category> categories;
  final Map<String, ExchangeRate> rates;

  /// Усі записи з однієї категорії (екран категорії).
  final bool insideCategory;

  @override
  Widget build(BuildContext context) {
    final items = <Object>[];
    DateTime? currentDay;
    for (final e in entries) {
      if (currentDay != e.date) {
        currentDay = e.date;
        items.add(e.date);
      }
      items.add(e);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        if (item is DateTime) return DayHeader(day: item);
        final e = item as MoneyEntry;
        return EntryTile(
          key: ValueKey(e.id),
          entry: e,
          category: categories[e.categoryId],
          rates: rates,
          insideCategory: insideCategory,
        );
      },
    );
  }
}

/// Категорії з сумами (у EUR); тап розгортає записи категорії.
class EntriesByCategoryList extends ConsumerWidget {
  const EntriesByCategoryList({
    super.key,
    required this.entries,
    required this.categories,
    required this.rates,
  });

  final List<MoneyEntry> entries;
  final Map<String, Category> categories;
  final Map<String, ExchangeRate> rates;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(rateHistoryProvider).value;
    final groups = <String, List<MoneyEntry>>{};
    for (final e in entries) {
      (groups[e.categoryId] ??= []).add(e);
    }
    final sorted = [
      for (final g in groups.entries)
        (
          id: g.key,
          list: g.value,
          sum: sumInEur(g.value, rates, history: history),
        ),
    ]..sort((a, b) => b.sum.$1.compareTo(a.sum.$1));
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24, top: 4),
      children: [
        for (final g in sorted)
          Theme(
            // Прибираємо лінії, які ExpansionTile малює при розгортанні.
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: PageStorageKey('cat-${g.id}'),
              tilePadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: CategoryAvatar(category: categories[g.id]),
              title: Text(categories[g.id]?.name ?? 'Без категорії'),
              subtitle: Text(
                '${g.list.length} ${_recordsWord(g.list.length)}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              trailing: Text(
                formatMoney(g.sum.$1, baseCurrency),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              children: [
                for (final e in g.list)
                  EntryTile(
                    key: ValueKey(e.id),
                    entry: e,
                    category: categories[e.categoryId],
                    rates: rates,
                    insideCategory: true,
                    showDate: true,
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// «1 запис», «2 записи», «5 записів».
String _recordsWord(int n) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return 'запис';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'записи';
  return 'записів';
}
