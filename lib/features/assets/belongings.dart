import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/category_icons.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/rates_service.dart';
import '../finance/finance_providers.dart';
import '../wallets/wallet_widgets.dart';

/// Пасиви (етап 9): речі, якими володієш. Купівля — витрата, продаж — надходження
/// «Продаж речей». Ціна речей у загальний баланс не входить.

const belongingIcons = <String, IconData>{
  'phone': Icons.smartphone_outlined,
  'laptop': Icons.laptop_outlined,
  'tv': Icons.tv_outlined,
  'headphones': Icons.headphones_outlined,
  'watch': Icons.watch_outlined,
  'camera': Icons.photo_camera_outlined,
  'game': Icons.sports_esports_outlined,
  'car': Icons.directions_car_outlined,
  'bike': Icons.pedal_bike_outlined,
  'furniture': Icons.chair_outlined,
  'appliance': Icons.kitchen_outlined,
  'clothes': Icons.checkroom_outlined,
  'jewelry': Icons.diamond_outlined,
  'sport': Icons.fitness_center_outlined,
  'tools': Icons.build_outlined,
  'music': Icons.piano_outlined,
  'books': Icons.menu_book_outlined,
  'other': Icons.inventory_2_outlined,
};

IconData belongingIcon(String key) =>
    belongingIcons[key] ?? Icons.inventory_2_outlined;

bool isSold(Belonging b) => b.saleCents != null && b.saleDate != null;

final belongingsProvider = StreamProvider<List<Belonging>>(
  (ref) => ref.watch(databaseProvider).watchBelongings(),
);

String _dateText(DateTime d) => DateFormat('d MMMM y', 'uk').format(d);

void openBelongingForm(BuildContext context, {Belonging? belonging}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => BelongingFormScreen(belonging: belonging),
    ),
  );
}

void openBelonging(BuildContext context, String id) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => BelongingDetailScreen(belongingId: id)),
  );
}

// ---------------- Вкладка «Пасиви» ----------------

class BelongingsTab extends ConsumerWidget {
  const BelongingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    return ref
        .watch(belongingsProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Помилка: $e')),
          data: (list) {
            if (list.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Речей ще немає.\nНатисни «Додати річ», щоб записати покупку — '
                    'наприклад, телефон чи велосипед. Можна додати й те, що купив раніше.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              );
            }
            final held = list.where((b) => !isSold(b)).toList();
            final sold = list.where(isSold).toList();
            var totalEur = 0;
            var missing = false;
            for (final b in held) {
              final eur = toEurCents(b.priceCents, b.currency, rates);
              if (eur == null) {
                missing = true;
              } else {
                totalEur += eur;
              }
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                if (held.isNotEmpty)
                  Card(
                    elevation: 0,
                    color: scheme.secondaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Речей на суму',
                            style: TextStyle(
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${missing ? '≈ ' : ''}${formatMoney(totalEur, baseCurrency)}',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSecondaryContainer,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${held.length} шт. · за ціною купівлі, у загальний баланс не входить',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSecondaryContainer,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                for (final b in held) BelongingCard(belonging: b),
                if (sold.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
                    child: Text(
                      'Продані',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  for (final b in sold)
                    Opacity(opacity: 0.7, child: BelongingCard(belonging: b)),
                ],
              ],
            );
          },
        );
  }
}

class BelongingCard extends StatelessWidget {
  const BelongingCard({super.key, required this.belonging});

  final Belonging belonging;

  @override
  Widget build(BuildContext context) {
    final b = belonging;
    final scheme = Theme.of(context).colorScheme;
    final sold = isSold(b);
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openBelonging(context, b.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: scheme.secondaryContainer,
                child: Icon(
                  belongingIcon(b.icon),
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sold
                          ? 'Продано ${_dateText(b.saleDate!)}'
                          : (b.recordExpense
                                ? 'Куплено ${_dateText(b.purchaseDate)}'
                                : 'Куплено ${_dateText(b.purchaseDate)} · раніше'),
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
                    formatMoney(b.priceCents, b.currency),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (sold)
                    Text(
                      '→ ${formatMoney(b.saleCents!, b.saleCurrency ?? b.currency)}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.income,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Картка речі ----------------

class BelongingDetailScreen extends ConsumerWidget {
  const BelongingDetailScreen({super.key, required this.belongingId});

  final String belongingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(belongingsProvider).value ?? const <Belonging>[];
    final b = list.where((x) => x.id == belongingId).firstOrNull;
    if (b == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Річ не знайдено')),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final wallets = ref.watch(walletMapProvider);
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final sold = isSold(b);
    final saleCurrency = b.saleCurrency ?? b.currency;

    Widget row(IconData icon, String title, String value, {Color? color}) =>
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(
            title,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          subtitle: Text(
            value,
            style: TextStyle(fontSize: 16, color: color ?? scheme.onSurface),
          ),
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(b.name),
        actions: [
          IconButton(
            tooltip: 'Редагувати',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openBelongingForm(context, belonging: b),
          ),
          IconButton(
            tooltip: 'Видалити',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _delete(context, ref, b),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: scheme.secondaryContainer,
                  child: Icon(
                    belongingIcon(b.icon),
                    size: 30,
                    color: scheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatMoney(b.priceCents, b.currency),
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        sold ? 'Продано' : 'Є у тебе',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            row(
              Icons.shopping_cart_outlined,
              'Куплено',
              _dateText(b.purchaseDate),
            ),
            if (b.recordExpense)
              row(
                Icons.account_balance_wallet_outlined,
                'Витрата',
                '${formatMoney(b.priceCents, b.currency, sign: -1)} · '
                    '${wallets[b.walletId]?.name ?? '?'} · ${categories[b.categoryId]?.name ?? ''}',
                color: AppColors.expense,
              )
            else
              row(
                Icons.history,
                'Витрата',
                'Куплено раніше — витрату не записано',
              ),
            if (sold) ...[
              row(
                Icons.sell_outlined,
                'Продано ${_dateText(b.saleDate!)}',
                '${formatMoney(b.saleCents!, saleCurrency, sign: 1)} · ${wallets[b.saleWalletId]?.name ?? '?'}',
                color: AppColors.income,
              ),
              if (saleCurrency == b.currency)
                row(
                  Icons.calculate_outlined,
                  'Різниця з ціною купівлі',
                  formatMoney(
                    b.saleCents! - b.priceCents,
                    b.currency,
                    sign: b.saleCents! >= b.priceCents ? 1 : -1,
                  ),
                ),
            ],
            if (b.note != null) row(Icons.notes_outlined, 'Коментар', b.note!),
            const SizedBox(height: 16),
            if (!sold)
              SizedBox(
                height: 52,
                child: FilledButton.icon(
                  icon: const Icon(Icons.sell_outlined),
                  label: const Text('Продати', style: TextStyle(fontSize: 16)),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SellBelongingScreen(belonging: b),
                    ),
                  ),
                ),
              )
            else ...[
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Змінити продаж'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SellBelongingScreen(belonging: b),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                icon: const Icon(Icons.undo),
                label: const Text('Скасувати продаж'),
                onPressed: () =>
                    ref.read(databaseProvider).cancelBelongingSale(b.id),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Belonging b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Видалити «${b.name}»?'),
        content: const Text(
          'Записи купівлі й продажу цієї речі теж буде видалено.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Ні'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    await db.setBelongingDeleted(b.id, true);
    if (context.mounted) Navigator.of(context).pop();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('«${b.name}» видалено'),
        persist: false, // зникає сама, навіть з кнопкою
        action: SnackBarAction(
          label: 'Скасувати',
          onPressed: () => db.setBelongingDeleted(b.id, false),
        ),
      ),
    );
  }
}

// ---------------- Спільні шматки форм ----------------

class _WalletCurrencyPicker extends ConsumerWidget {
  const _WalletCurrencyPicker({
    required this.title,
    required this.walletId,
    required this.currency,
    required this.onWallet,
    required this.onCurrency,
  });

  final String title;
  final String walletId;
  final String currency;
  final ValueChanged<String> onWallet;
  final ValueChanged<String> onCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallets = (ref.watch(walletsProvider).value ?? const <Wallet>[])
        .where((w) => !w.archived || w.id == walletId)
        .toList();
    final all =
        ref.watch(walletCurrenciesProvider).value ?? const <WalletCurrency>[];
    final codes = currenciesOfWallet(all, walletId);
    final options = codes.contains(currency) ? codes : [...codes, currency];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wallets.length > 1) ...[
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final w in wallets)
                ChoiceChip(
                  showCheckmark: false,
                  avatar: Icon(
                    walletIcon(w.icon),
                    size: 18,
                    color: Color(w.color),
                  ),
                  label: Text(w.name),
                  selected: w.id == walletId,
                  onSelected: (_) {
                    onWallet(w.id);
                    final c = currenciesOfWallet(all, w.id);
                    if (c.isNotEmpty && !c.contains(currency)) {
                      onCurrency(c.first);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in options)
              ChoiceChip(
                label: Text(c),
                selected: c == currency,
                onSelected: (_) => onCurrency(c),
              ),
          ],
        ),
      ],
    );
  }
}

String _defaultCurrency(WidgetRef ref, String walletId) {
  final all =
      ref.read(walletCurrenciesProvider).value ?? const <WalletCurrency>[];
  final codes = currenciesOfWallet(all, walletId);
  if (codes.contains(baseCurrency)) return baseCurrency;
  return codes.firstOrNull ?? baseCurrency;
}

Future<DateTime?> _pickDate(BuildContext context, DateTime initial) {
  final now = DateTime.now();
  return showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1990),
    lastDate: DateTime(now.year + 1, 12, 31),
  );
}

// ---------------- Нова річ / редагування ----------------

class BelongingFormScreen extends ConsumerStatefulWidget {
  const BelongingFormScreen({super.key, this.belonging});

  final Belonging? belonging;

  @override
  ConsumerState<BelongingFormScreen> createState() =>
      _BelongingFormScreenState();
}

class _BelongingFormScreenState extends ConsumerState<BelongingFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _price;
  late final TextEditingController _note;
  late String _icon;
  late String _walletId;
  late String _currency;
  late String _categoryId;
  late bool _recordExpense;
  late DateTime _date;
  String? _nameError;
  String? _priceError;
  bool _saving = false;

  bool get _isEdit => widget.belonging != null;

  @override
  void initState() {
    super.initState();
    final b = widget.belonging;
    _name = TextEditingController(text: b?.name ?? '');
    _price = TextEditingController(
      text: b == null ? '' : centsToInput(b.priceCents),
    );
    _note = TextEditingController(text: b?.note ?? '');
    _icon = b?.icon ?? 'other';
    _walletId = b?.walletId ?? AppDatabase.mainWalletId;
    _currency = b?.currency ?? _defaultCurrency(ref, _walletId);
    _categoryId = b?.categoryId ?? 'exp-other';
    _recordExpense = b?.recordExpense ?? true;
    _date = b?.purchaseDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories =
        (ref.watch(categoriesProvider(EntryType.expense)).value ??
                const <Category>[])
            .where((c) => !c.hidden || c.id == _categoryId)
            .toList();
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Річ' : 'Нова річ')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              autofocus: !_isEdit,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Назва',
                hintText: 'Наприклад, iPhone 15',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _nameError = null),
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in belongingIcons.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: e.key == _icon
                            ? scheme.secondaryContainer
                            : null,
                        border: Border.all(
                          color: e.key == _icon
                              ? scheme.secondary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        e.value,
                        color: e.key == _icon
                            ? scheme.onSecondaryContainer
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: Theme.of(context).textTheme.titleLarge,
              decoration: InputDecoration(
                labelText: 'Ціна купівлі',
                errorText: _priceError,
                suffixText: currencySymbol(_currency),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _priceError = null),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Записати витрату'),
              subtitle: Text(
                _recordExpense
                    ? 'Гроші спишуться з гаманця'
                    : 'Куплено раніше — річ буде в списку, баланс не зміниться',
              ),
              value: _recordExpense,
              onChanged: (v) => setState(() => _recordExpense = v),
            ),
            if (_recordExpense) ...[
              _WalletCurrencyPicker(
                title: 'Звідки (гаманець)',
                walletId: _walletId,
                currency: _currency,
                onWallet: (w) => setState(() => _walletId = w),
                onCurrency: (c) => setState(() => _currency = c),
              ),
              const SizedBox(height: 16),
              Text(
                'Категорія витрати',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in categories)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: Icon(
                        categoryIcons[c.icon] ?? Icons.more_horiz,
                        size: 18,
                        color: Color(c.color),
                      ),
                      label: Text(c.name),
                      selected: c.id == _categoryId,
                      onSelected: (_) => setState(() => _categoryId = c.id),
                    ),
                ],
              ),
            ] else
              Wrap(
                spacing: 8,
                children: [
                  for (final c in {baseCurrency, 'UAH', 'USD', _currency})
                    ChoiceChip(
                      label: Text(c),
                      selected: c == _currency,
                      onSelected: (_) => setState(() => _currency = c),
                    ),
                ],
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Дата купівлі'),
              trailing: Text(
                _dateText(_date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () async {
                final d = await _pickDate(context, _date);
                if (d != null) setState(() => _date = d);
              },
            ),
            TextField(
              controller: _note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Коментар (необов\'язково)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
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
    final cents = parseAmountToCents(_price.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Введи назву' : null;
      _priceError = (cents == null || cents == 0)
          ? 'Введи ціну, напр. 499'
          : null;
    });
    if (_nameError != null || _priceError != null) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(databaseProvider)
          .saveBelonging(
            id: widget.belonging?.id,
            name: _name.text,
            icon: _icon,
            priceCents: cents!,
            currency: _currency,
            purchaseDate: _date,
            walletId: _walletId,
            categoryId: _categoryId,
            recordExpense: _recordExpense,
            note: _note.text,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не вдалося зберегти: $e')));
    }
  }
}

// ---------------- Продаж ----------------

class SellBelongingScreen extends ConsumerStatefulWidget {
  const SellBelongingScreen({super.key, required this.belonging});

  final Belonging belonging;

  @override
  ConsumerState<SellBelongingScreen> createState() =>
      _SellBelongingScreenState();
}

class _SellBelongingScreenState extends ConsumerState<SellBelongingScreen> {
  late final TextEditingController _amount;
  late String _walletId;
  late String _currency;
  late DateTime _date;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final b = widget.belonging;
    _amount = TextEditingController(
      text: b.saleCents == null ? '' : centsToInput(b.saleCents!),
    );
    _walletId = b.saleWalletId ?? b.walletId;
    _currency = b.saleCurrency ?? b.currency;
    _date = b.saleDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.belonging;
    final cents = parseAmountToCents(_amount.text);
    final diff = (cents != null && _currency == b.currency)
        ? cents - b.priceCents
        : null;
    return Scaffold(
      appBar: AppBar(title: Text('Продаж: ${b.name}')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Куплено за ${formatMoney(b.priceCents, b.currency)}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _amount,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: Theme.of(context).textTheme.titleLarge,
              decoration: InputDecoration(
                labelText: 'Отримано',
                errorText: _error,
                helperText: diff == null
                    ? 'Уся сума піде в надходження «Продаж речей»'
                    : 'Різниця з ціною купівлі: ${formatMoney(diff, b.currency, sign: diff >= 0 ? 1 : -1)}',
                suffixText: currencySymbol(_currency),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            const SizedBox(height: 16),
            _WalletCurrencyPicker(
              title: 'Куди (гаманець)',
              walletId: _walletId,
              currency: _currency,
              onWallet: (w) => setState(() => _walletId = w),
              onCurrency: (c) => setState(() => _currency = c),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Дата продажу'),
              trailing: Text(
                _dateText(_date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: () async {
                final d = await _pickDate(context, _date);
                if (d != null) setState(() => _date = d);
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 56,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Продати', style: TextStyle(fontSize: 18)),
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
      setState(() => _error = 'Введи суму, напр. 300');
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(databaseProvider)
          .sellBelonging(
            widget.belonging.id,
            saleCents: cents,
            currency: _currency,
            walletId: _walletId,
            date: _date,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не вдалося зберегти: $e')));
    }
  }
}
