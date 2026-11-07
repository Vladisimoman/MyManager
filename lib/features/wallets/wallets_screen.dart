import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';
import '../finance/ledger.dart';
import 'transfer_form_screen.dart';
import 'wallet_detail_screen.dart';
import 'wallet_edit_screen.dart';
import 'wallet_widgets.dart';

/// Список гаманців з балансами в кожній валюті.
class WalletsScreen extends ConsumerWidget {
  const WalletsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = ref.watch(walletsProvider);
    final balances = ref.watch(walletBalancesProvider);
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Гаманці'),
        actions: [
          IconButton(
            tooltip: 'Переказ між гаманцями',
            icon: const Icon(Icons.swap_horiz),
            onPressed: () => _push(context, const TransferFormScreen()),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _push(context, const WalletEditScreen()),
        icon: const Icon(Icons.add),
        label: const Text('Гаманець'),
      ),
      body: SafeArea(
        child: wallets.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Помилка: $e')),
          data: (list) {
            final active = list.where((w) => !w.archived).toList();
            final archived = list.where((w) => w.archived).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final w in active)
                  _WalletCard(
                    wallet: w,
                    balances: balances[w.id] ?? const {},
                    assets: _assetLines(ref, w.id),
                    rates: rates,
                    onTap: () =>
                        _push(context, WalletDetailScreen(walletId: w.id)),
                  ),
                if (archived.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
                    child: Text(
                      'Архів',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  for (final w in archived)
                    Opacity(
                      opacity: 0.6,
                      child: _WalletCard(
                        wallet: w,
                        balances: balances[w.id] ?? const {},
                        assets: _assetLines(ref, w.id),
                        rates: rates,
                        onTap: () =>
                            _push(context, WalletDetailScreen(walletId: w.id)),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _push(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
}

/// Рядки активів гаманця: «0,001 BTC», відсортовані за тікером.
List<String> _assetLines(WidgetRef ref, String walletId) {
  final assets = ref.watch(assetMapProvider);
  final held = assetsInWallet(ref.watch(assetPositionsProvider), walletId);
  final lines = [
    for (final e in held.entries) (code: assets[e.key]?.code ?? '?', units: e.value),
  ]..sort((a, b) => a.code.compareTo(b.code));
  return [for (final l in lines) formatUnits(l.units, l.code)];
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({
    required this.wallet,
    required this.balances,
    this.assets = const [],
    required this.rates,
    required this.onTap,
  });

  final Wallet wallet;
  final Map<String, int> balances;

  /// Активи в гаманці: «0,001 BTC» (у суму ≈ € не входять).
  final List<String> assets;
  final Map<String, ExchangeRate> rates;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final codes = sortCurrencies(balances.keys);
    final total = sumToEur(balances, rates).cents;
    final multi =
        codes.length > 1 || (codes.isNotEmpty && codes.first != baseCurrency);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                WalletAvatar(wallet: wallet, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        wallet.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final c in codes)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            formatMoney(balances[c]!, c),
                            style: TextStyle(
                              fontSize: 15,
                              color: balances[c]! < 0
                                  ? AppColors.expense
                                  : null,
                            ),
                          ),
                        ),
                      for (final a in assets)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            a,
                            style: TextStyle(fontSize: 14, color: scheme.tertiary),
                          ),
                        ),
                    ],
                  ),
                ),
                if (multi)
                  Text(
                    '≈ ${formatMoney(total, baseCurrency)}',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
