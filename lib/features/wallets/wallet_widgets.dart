import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';

/// Іконки гаманців за ключем (ключ зберігається в базі; нові можна лише додавати).
const walletIcons = <String, IconData>{
  'cash': Icons.payments_outlined,
  'card': Icons.credit_card_outlined,
  'bank': Icons.account_balance_outlined,
  'savings': Icons.savings_outlined,
  'crypto': Icons.currency_bitcoin,
  'broker': Icons.candlestick_chart_outlined,
  'wallet': Icons.account_balance_wallet_outlined,
  'phone': Icons.phone_android_outlined,
  'safe': Icons.lock_outline,
  'business': Icons.business_center_outlined,
};

IconData walletIcon(String key) =>
    walletIcons[key] ?? Icons.account_balance_wallet_outlined;

class WalletAvatar extends StatelessWidget {
  const WalletAvatar({super.key, required this.wallet, this.size = 40});

  final Wallet? wallet;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = wallet == null ? Colors.grey : Color(wallet!.color);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(
        wallet == null ? Icons.help_outline : walletIcon(wallet!.icon),
        color: color,
        size: size * 0.55,
      ),
    );
  }
}

/// Валюти гаманця у стабільному порядку: EUR, UAH, USD, далі за абеткою.
List<String> sortCurrencies(Iterable<String> codes) {
  const first = ['EUR', 'UAH', 'USD'];
  final list = codes.toSet().toList()
    ..sort((a, b) {
      final ia = first.indexOf(a), ib = first.indexOf(b);
      if (ia != -1 || ib != -1) {
        return (ia == -1 ? 99 : ia).compareTo(ib == -1 ? 99 : ib);
      }
      return a.compareTo(b);
    });
  return list;
}

/// Валюти конкретного гаманця.
List<String> currenciesOfWallet(List<WalletCurrency> all, String walletId) =>
    sortCurrencies(
      all
          .where((c) => c.walletId == walletId && !c.deleted)
          .map((c) => c.currency),
    );

/// Кнопка-фільтр «Гаманець: Усі ▾» для списків і статистики.
class WalletFilterButton extends ConsumerWidget {
  const WalletFilterButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider).value ?? const <Wallet>[];
    final selected = ref.watch(walletFilterProvider);
    final current = wallets.where((w) => w.id == selected).firstOrNull;
    if (wallets.length < 2 && selected == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        tooltip: 'Фільтр за гаманцем',
        onSelected: (id) =>
            ref.read(walletFilterProvider.notifier).set(id == _all ? null : id),
        itemBuilder: (_) => [
          const PopupMenuItem(value: _all, child: Text('Усі гаманці')),
          for (final w in wallets)
            PopupMenuItem(
              value: w.id,
              child: Row(
                children: [
                  WalletAvatar(wallet: w, size: 28),
                  const SizedBox(width: 12),
                  Text(w.name),
                ],
              ),
            ),
        ],
        child: Chip(
          avatar: current == null
              ? const Icon(Icons.account_balance_wallet_outlined, size: 18)
              : Icon(
                  walletIcon(current.icon),
                  size: 18,
                  color: Color(current.color),
                ),
          label: Text(current == null ? 'Усі гаманці' : current.name),
          deleteIcon: const Icon(Icons.arrow_drop_down),
          onDeleted: null,
        ),
      ),
    );
  }

  static const _all = '__all__';
}

/// Рядок валют гаманця: «200,00 € · 3 000,00 ₴».
String walletBalancesLine(Map<String, int> balances) {
  final codes = sortCurrencies(balances.keys);
  return codes.map((c) => formatMoney(balances[c]!, c)).join(' · ');
}
