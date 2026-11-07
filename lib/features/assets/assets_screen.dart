import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';
import '../finance/ledger.dart';
import '../finance/widgets/entry_list.dart';
import '../wallets/wallet_widgets.dart';
import 'belongings.dart';
import 'trade_form_screen.dart';

IconData assetKindIcon(AssetKind k) => switch (k) {
  AssetKind.crypto => Icons.currency_bitcoin,
  AssetKind.stock => Icons.candlestick_chart_outlined,
  AssetKind.other => Icons.diamond_outlined,
};

String assetKindLabel(AssetKind k) => switch (k) {
  AssetKind.crypto => 'Крипта',
  AssetKind.stock => 'Акції / ETF',
  AssetKind.other => 'Інше',
};

/// «Активи та пасиви»: активи (крипта, акції) — етап 8; пасиви (речі) — етап 9.
class AssetsScreen extends StatefulWidget {
  const AssetsScreen({super.key});

  @override
  State<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends State<AssetsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final belongingsTab = _tabs.index == 1;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Активи та пасиви'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Активи'),
            Tab(text: 'Пасиви'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => belongingsTab
            ? openBelongingForm(context)
            : Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TradeFormScreen()),
              ),
        icon: const Icon(Icons.add),
        label: Text(belongingsTab ? 'Додати річ' : 'Купити'),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [_AssetsTab(), BelongingsTab()],
      ),
    );
  }
}

class _AssetsTab extends ConsumerWidget {
  const _AssetsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assets = ref.watch(assetsProvider);
    final positions = ref.watch(assetPositionsProvider);
    final scheme = Theme.of(context).colorScheme;

    return assets.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Помилка: $e')),
      data: (list) {
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'Активів ще немає.\nНатисни «Купити», щоб записати першу купівлю — '
                'наприклад, 100 \$ → 0,001 BTC.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final held = list
            .where((a) => (positions[a.id]?.units ?? 0) != 0)
            .toList();
        final sold = list
            .where((a) => (positions[a.id]?.units ?? 0) == 0)
            .toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text(
              'Ціна купівлі, без поточної вартості. У загальний баланс активи не входять.',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            for (final a in held)
              _AssetCard(asset: a, position: positions[a.id]),
            if (sold.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                child: Text(
                  'Продані повністю',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
              for (final a in sold)
                Opacity(
                  opacity: 0.6,
                  child: _AssetCard(asset: a, position: positions[a.id]),
                ),
            ],
          ],
        );
      },
    );
  }
}

class _AssetCard extends StatelessWidget {
  const _AssetCard({required this.asset, required this.position});

  final Asset asset;
  final AssetPosition? position;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = position;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AssetDetailScreen(assetId: asset.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.tertiaryContainer,
                  child: Icon(
                    assetKindIcon(asset.kind),
                    color: scheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${asset.code} · ${asset.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatUnits(p?.units ?? 0, asset.code),
                        style: const TextStyle(fontSize: 15),
                      ),
                      if (p != null && p.units > 0)
                        Text(
                          'Середня ціна ${formatUnitPrice(p.avgPriceCents, asset.basisCurrency)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Вкладено',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      formatMoney(p?.basisCents ?? 0, asset.basisCurrency),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Актив: кількість, середня ціна, де лежить, історія операцій і витрат.
class AssetDetailScreen extends ConsumerWidget {
  const AssetDetailScreen({super.key, required this.assetId});

  final String assetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetMapProvider)[assetId];
    final position = ref.watch(assetPositionsProvider)[assetId];
    final wallets = ref.watch(walletMapProvider);
    final trades = (ref.watch(tradesProvider).value ?? const <AssetTrade>[])
        .where((t) => t.assetId == assetId)
        .toList();
    final spends = (ref.watch(allEntriesProvider).value ?? const <MoneyEntry>[])
        .where((e) => e.assetId == assetId)
        .toList();
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    final scheme = Theme.of(context).colorScheme;

    if (asset == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Актив не знайдено')),
      );
    }

    final items =
        <({DateTime date, DateTime created, Object item})>[
          for (final t in trades) (date: t.date, created: t.createdAt, item: t),
          for (final e in spends) (date: e.date, created: e.createdAt, item: e),
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
        x is AssetTrade
            ? TradeTile(key: ValueKey(x.id), trade: x)
            : EntryTile(
                key: ValueKey((x as MoneyEntry).id),
                entry: x,
                category: categories[x.categoryId],
                rates: rates,
              ),
      );
    }

    void open(TradeType type) => Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TradeFormScreen(type: type, assetId: assetId),
      ),
    );

    final byWallet =
        position?.unitsByWallet.entries.where((e) => e.value != 0).toList() ??
        const [];

    return Scaffold(
      appBar: AppBar(title: Text('${asset.code} · ${asset.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Text(
                formatUnits(position?.units ?? 0, asset.code),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                [
                  'Вкладено ${formatMoney(position?.basisCents ?? 0, asset.basisCurrency)}',
                  if (position != null && position.units > 0)
                    'середня ціна ${formatUnitPrice(position.avgPriceCents, asset.basisCurrency)}',
                ].join(' · '),
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
            ),
            if (byWallet.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final e in byWallet)
                      Chip(
                        avatar: wallets[e.key] == null
                            ? null
                            : Icon(
                                walletIcon(wallets[e.key]!.icon),
                                size: 18,
                                color: Color(wallets[e.key]!.color),
                              ),
                        label: Text(
                          '${wallets[e.key]?.name ?? '?'}: ${formatUnits(e.value, asset.code)}',
                        ),
                      ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: () => open(TradeType.buy),
                      child: const Text('Купити'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: (position?.units ?? 0) > 0
                          ? () => open(TradeType.sell)
                          : null,
                      child: const Text('Продати'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: (position?.units ?? 0) > 0
                          ? () => open(TradeType.move)
                          : null,
                      child: const Text('Переказ'),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 32),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Операцій немає')),
              )
            else
              ...rows,
          ],
        ),
      ),
    );
  }
}

/// Рядок операції з активом: «Купівля 0,001 BTC» з сумою грошей.
class TradeTile extends ConsumerWidget {
  const TradeTile({super.key, required this.trade, this.viewFromWalletId});

  final AssetTrade trade;

  /// Якщо показуємо в історії гаманця — знаки сум з його точки зору.
  final String? viewFromWalletId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = trade;
    final asset = ref.watch(assetMapProvider)[t.assetId];
    final wallets = ref.watch(walletMapProvider);
    final scheme = Theme.of(context).colorScheme;
    final code = asset?.code ?? '?';

    final title = switch (t.type) {
      TradeType.buy => 'Купівля ${formatUnits(t.units, code)}',
      TradeType.sell => 'Продаж ${formatUnits(t.units, code)}',
      TradeType.move =>
        'Переказ ${formatUnits(t.units, code)} → ${wallets[t.toWalletId]?.name ?? '?'}',
    };
    final subtitleParts = <String>[
      if (t.type == TradeType.move) 'з ${wallets[t.walletId]?.name ?? '?'}',
      if (t.type == TradeType.buy && t.fiatWalletId == null)
        'Куплено раніше → ${wallets[t.walletId]?.name ?? '?'}',
      if (t.type == TradeType.buy && t.fiatWalletId != null)
        'з ${wallets[t.fiatWalletId]?.name ?? '?'} → ${wallets[t.walletId]?.name ?? '?'}',
      if (t.type == TradeType.sell)
        '${wallets[t.walletId]?.name ?? '?'} → ${wallets[t.fiatWalletId]?.name ?? '?'}',
      if (t.note != null) t.note!,
    ];

    String? amount;
    Color? color;
    final v = viewFromWalletId;
    final assetSide =
        v != null && v != t.fiatWalletId; // гаманець бачить лише актив
    if (assetSide || t.type == TradeType.move) {
      final into =
          (t.type == TradeType.buy && v == t.walletId) ||
          (t.type == TradeType.move && v == t.toWalletId);
      amount = formatUnits(
        t.units,
        code,
        sign: v == null ? 0 : (into ? 1 : -1),
      );
      color = scheme.tertiary;
    } else if (t.fiatCents != null && t.fiatCurrency != null) {
      final out = t.type == TradeType.buy;
      // Куплено раніше — гроші не рухались, показуємо ціну без знака.
      final earlier = out && t.fiatWalletId == null;
      amount = formatMoney(
        t.fiatCents!,
        t.fiatCurrency!,
        sign: earlier ? 0 : (out ? -1 : 1),
      );
      color = out ? null : AppColors.income;
    }

    return Dismissible(
      key: ValueKey('dismiss-trade-${t.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: AppColors.expense,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) => deleteTradeWithUndo(context, ref, t),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => TradeFormScreen(trade: t))),
        leading: CircleAvatar(
          radius: 20,
          backgroundColor: scheme.tertiaryContainer,
          child: Icon(
            switch (t.type) {
              TradeType.buy => Icons.add_shopping_cart,
              TradeType.sell => Icons.sell_outlined,
              TradeType.move => Icons.swap_horiz,
            },
            size: 20,
            color: scheme.onTertiaryContainer,
          ),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitleParts.isEmpty
            ? null
            : Text(
                subtitleParts.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: amount == null
            ? null
            : Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                  color: color,
                ),
              ),
      ),
    );
  }
}

Future<void> deleteTradeWithUndo(
  BuildContext context,
  WidgetRef ref,
  AssetTrade t,
) async {
  final db = ref.read(databaseProvider);
  final messenger = ScaffoldMessenger.of(context);
  try {
    await db.setTradeDeleted(t.id, true);
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Не вдалося видалити: $e')));
    return;
  }
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: const Text('Операцію видалено'),
      persist: false, // зникає сама, навіть з кнопкою
      action: SnackBarAction(
        label: 'Скасувати',
        onPressed: () => db.setTradeDeleted(t.id, false),
      ),
    ),
  );
}
