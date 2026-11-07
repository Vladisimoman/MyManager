import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';
import '../finance/widgets/entry_list.dart';
import '../finance/ledger.dart';
import '../assets/assets_screen.dart';
import 'transfer_form_screen.dart';
import 'wallet_edit_screen.dart';
import 'wallet_widgets.dart';

/// Гаманець: баланси за валютами й уся історія (надходження, витрати, перекази).
class WalletDetailScreen extends ConsumerWidget {
  const WalletDetailScreen({super.key, required this.walletId});

  final String walletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletMapProvider)[walletId];
    final balances =
        ref.watch(walletBalancesProvider)[walletId] ?? const <String, int>{};
    final entries = ref.watch(allEntriesProvider).value ?? const <MoneyEntry>[];
    final transfers = ref.watch(transfersProvider).value ?? const <Transfer>[];
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    final scheme = Theme.of(context).colorScheme;

    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Гаманець не знайдено')),
      );
    }

    final trades = ref.watch(tradesProvider).value ?? const <AssetTrade>[];
    final assetMap = ref.watch(assetMapProvider);
    final held = assetsInWallet(ref.watch(assetPositionsProvider), walletId);

    // Історія: записи цього гаманця + перекази й операції з активами, новіші зверху.
    final items =
        <({DateTime date, DateTime created, Object item})>[
          for (final e in entries)
            if (e.walletId == walletId)
              (date: e.date, created: e.createdAt, item: e),
          for (final t in transfers)
            if (t.fromWalletId == walletId || t.toWalletId == walletId)
              (date: t.date, created: t.createdAt, item: t),
          for (final t in trades)
            if (t.walletId == walletId ||
                t.toWalletId == walletId ||
                t.fiatWalletId == walletId)
              (date: t.date, created: t.createdAt, item: t),
        ]..sort((a, b) {
          final d = b.date.compareTo(a.date);
          return d != 0 ? d : b.created.compareTo(a.created);
        });

    final rows = <Widget>[];
    DateTime? day;
    for (final it in items) {
      if (day != it.date) {
        day = it.date;
        rows.add(DayHeader(day: it.date));
      }
      final x = it.item;
      rows.add(
        x is MoneyEntry
            ? EntryTile(
                key: ValueKey(x.id),
                entry: x,
                category: categories[x.categoryId],
                rates: rates,
                inWalletHistory: true,
              )
            : x is AssetTrade
            ? TradeTile(
                key: ValueKey(x.id),
                trade: x,
                viewFromWalletId: walletId,
              )
            : TransferTile(
                key: ValueKey((x as Transfer).id),
                transfer: x,
                viewFromWalletId: walletId,
              ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(wallet.name),
        actions: [
          IconButton(
            tooltip: 'Редагувати гаманець',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => WalletEditScreen(wallet: wallet),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WalletAvatar(wallet: wallet, size: 52),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final c in sortCurrencies(balances.keys))
                          Text(
                            formatMoney(balances[c]!, c),
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: balances[c]! < 0
                                  ? AppColors.expense
                                  : null,
                            ),
                          ),
                        for (final e in held.entries)
                          Text(
                            formatUnits(e.value, assetMap[e.key]?.code ?? '?'),
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.tertiary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => TransferFormScreen(fromWalletId: walletId),
                  ),
                ),
                icon: const Icon(Icons.swap_horiz),
                label: const Text('Переказ з цього гаманця'),
              ),
            ),
            const Divider(height: 24),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Записів і переказів ще немає',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              )
            else
              ...rows,
          ],
        ),
      ),
    );
  }
}

/// Рядок переказу в історії. Сума — зі знаком з точки зору [viewFromWalletId]
/// (якщо null — показуємо «звідки → куди» без знака).
class TransferTile extends ConsumerWidget {
  const TransferTile({
    super.key,
    required this.transfer,
    this.viewFromWalletId,
  });

  final Transfer transfer;
  final String? viewFromWalletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletMapProvider);
    final scheme = Theme.of(context).colorScheme;
    final t = transfer;
    final from = wallets[t.fromWalletId]?.name ?? '?';
    final to = wallets[t.toWalletId]?.name ?? '?';
    final sameWallet = t.fromWalletId == t.toWalletId;
    final isOut = viewFromWalletId == t.fromWalletId;

    final title = sameWallet
        ? 'Обмін ${t.fromCurrency} → ${t.toCurrency}'
        : (viewFromWalletId == null
              ? '$from → $to'
              : (isOut ? 'Переказ → $to' : 'Переказ ← $from'));
    final exchange = t.fromCurrency != t.toCurrency;

    final String main;
    final String? second;
    if (sameWallet || viewFromWalletId == null) {
      main = formatMoney(t.fromAmountCents, t.fromCurrency);
      second = exchange
          ? '→ ${formatMoney(t.toAmountCents, t.toCurrency)}'
          : null;
    } else if (isOut) {
      main = formatMoney(t.fromAmountCents, t.fromCurrency, sign: -1);
      second = exchange
          ? '→ ${formatMoney(t.toAmountCents, t.toCurrency)}'
          : null;
    } else {
      main = formatMoney(t.toAmountCents, t.toCurrency, sign: 1);
      second = exchange
          ? '← ${formatMoney(t.fromAmountCents, t.fromCurrency)}'
          : null;
    }

    return Dismissible(
      key: ValueKey('dismiss-tr-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.expense,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => deleteTransferWithUndo(context, ref, t),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TransferFormScreen(transfer: t)),
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: scheme.secondaryContainer,
            shape: BoxShape.circle,
          ),
          child: Icon(
            sameWallet ? Icons.currency_exchange : Icons.swap_horiz,
            color: scheme.onSecondaryContainer,
            size: 22,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: t.note == null
            ? null
            : Text(t.note!, maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              main,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            if (second != null)
              Text(
                second,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }
}

Future<void> deleteTransferWithUndo(
  BuildContext context,
  WidgetRef ref,
  Transfer t,
) async {
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await db.setTransferDeleted(t.id, true);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не вдалося видалити: $e')));
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Переказ видалено'),
      persist: false, // зникає сама, навіть з кнопкою
      action: SnackBarAction(
        label: 'Скасувати',
        onPressed: () => db.setTransferDeleted(t.id, false),
      ),
    ),
  );
}
