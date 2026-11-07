import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/category_icons.dart' show categoryColors;
import '../../core/money.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';
import '../settings/initial_balance.dart';
import 'wallet_widgets.dart';

/// Новий гаманець ([wallet] == null) або редагування наявного:
/// назва, іконка, колір, валюти з початковими балансами, архів, видалення.
class WalletEditScreen extends ConsumerStatefulWidget {
  const WalletEditScreen({super.key, this.wallet});

  final Wallet? wallet;

  @override
  ConsumerState<WalletEditScreen> createState() => _WalletEditScreenState();
}

class _WalletEditScreenState extends ConsumerState<WalletEditScreen> {
  late final TextEditingController _name;
  late String _icon;
  late int _color;
  late bool _archived;
  late final Map<String, int> _currencies; // валюта → початковий баланс
  late final Set<String> _original;
  String? _nameError;
  bool _saving = false;

  bool get _isNew => widget.wallet == null;
  bool get _isMain => widget.wallet?.id == AppDatabase.mainWalletId;

  @override
  void initState() {
    super.initState();
    final w = widget.wallet;
    _name = TextEditingController(text: w?.name ?? '');
    _icon = w?.icon ?? 'card';
    _color = w?.color ?? categoryColors[4];
    _archived = w?.archived ?? false;
    final all =
        ref.read(walletCurrenciesProvider).value ?? const <WalletCurrency>[];
    _currencies = w == null
        ? {baseCurrency: 0}
        : {
            for (final c in all)
              if (c.walletId == w.id && !c.deleted) c.currency: c.initialCents,
          };
    _original = {..._currencies.keys};
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final preview = Wallet(
      id: '',
      name: _name.text,
      icon: _icon,
      color: _color,
      sortOrder: 0,
      archived: false,
      updatedAt: DateTime(2000),
      deleted: false,
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'Новий гаманець' : 'Гаманець'),
        actions: [
          if (!_isNew && !_isMain)
            IconButton(
              tooltip: 'Видалити гаманець',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                WalletAvatar(wallet: preview, size: 56),
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: _isNew,
                    maxLength: 30,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Назва',
                      hintText: 'Напр. Картка Monobank',
                      errorText: _nameError,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() => _nameError = null),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Валюти й початковий баланс', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Скільки було в кожній валюті до початку обліку. Торкнись, щоб змінити.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final c in sortCurrencies(_currencies.keys))
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  child: Text(
                    currencySymbol(c),
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                title: Text('$c · ${fiatCurrencies[c] ?? c}'),
                subtitle: Text(
                  'Початковий: ${formatMoney(_currencies[c]!, c)}',
                ),
                onTap: () => _editInitial(c),
                trailing: IconButton(
                  tooltip: 'Прибрати валюту',
                  icon: const Icon(Icons.close),
                  onPressed: () => _removeCurrency(c),
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addCurrency,
                icon: const Icon(Icons.add),
                label: const Text('Додати валюту'),
              ),
            ),
            const SizedBox(height: 12),
            Text('Іконка', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final key in walletIcons.keys)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = key),
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: key == _icon
                            ? Color(_color).withValues(alpha: 0.15)
                            : null,
                        border: Border.all(
                          color: key == _icon
                              ? Color(_color)
                              : scheme.outlineVariant,
                          width: key == _icon ? 2 : 1,
                        ),
                      ),
                      child: Icon(
                        walletIcons[key],
                        color: key == _icon ? Color(_color) : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Колір', style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final c in categoryColors)
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c == _color
                              ? scheme.onSurface
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: c == _color
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            if (!_isNew && !_isMain) ...[
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('В архіві'),
                subtitle: const Text(
                  'Не пропонувати в записах і переказах. Баланс і історія зберігаються.',
                ),
                value: _archived,
                onChanged: (v) => setState(() => _archived = v),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editInitial(String currency) async {
    final v = await showInitialBalanceDialog(
      context,
      currentCents: _currencies[currency] ?? 0,
      currency: currency,
    );
    if (v != null) setState(() => _currencies[currency] = v);
  }

  Future<void> _addCurrency() async {
    final available = [
      for (final c in fiatCurrencies.keys)
        if (!_currencies.containsKey(c)) c,
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'Додати валюту',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            for (final c in available)
              ListTile(
                leading: SizedBox(
                  width: 36,
                  child: Center(child: Text(currencySymbol(c))),
                ),
                title: Text(fiatCurrencies[c]!),
                trailing: Text(c),
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    setState(() => _currencies[picked] = 0);
    await _editInitial(picked);
  }

  Future<void> _removeCurrency(String currency) async {
    if (!_isNew && _original.contains(currency)) {
      final used = await ref
          .read(databaseProvider)
          .isWalletUsed(widget.wallet!.id, currency: currency);
      if (!mounted) return;
      if (used) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'У $currency є записи або перекази — валюту не можна прибрати',
            ),
          ),
        );
        return;
      }
    }
    setState(() => _currencies.remove(currency));
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = 'Введи назву');
      return;
    }
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    try {
      if (_isNew) {
        await db.addWallet(
          name: name,
          icon: _icon,
          color: _color,
          currencies: _currencies,
        );
      } else {
        final id = widget.wallet!.id;
        await db.transaction(() async {
          await db.updateWallet(
            id,
            name: name,
            icon: _icon,
            color: _color,
            archived: _archived,
          );
          final all =
              ref.read(walletCurrenciesProvider).value ??
              const <WalletCurrency>[];
          final before = {
            for (final c in all)
              if (c.walletId == id && !c.deleted) c.currency: c.initialCents,
          };
          for (final e in _currencies.entries) {
            if (before[e.key] != e.value) {
              await db.setWalletCurrency(id, e.key, e.value);
            }
          }
          for (final c in before.keys) {
            if (!_currencies.containsKey(c)) {
              await db.removeWalletCurrency(id, c);
            }
          }
        });
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не вдалося зберегти гаманець: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final db = ref.read(databaseProvider);
    final id = widget.wallet!.id;
    if (await db.isWalletUsed(id)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'У гаманці є записи або перекази. Його можна лише перенести в архів.',
          ),
        ),
      );
      return;
    }
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Видалити «${widget.wallet!.name}»?'),
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
    if (ok != true) return;
    await db.deleteWallet(id);
    if (!mounted) return;
    // Закриваємо і редагування, і екран гаманця (редагування відкривається з нього).
    Navigator.of(context)
      ..pop()
      ..pop();
  }
}
