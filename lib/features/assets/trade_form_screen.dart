import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/rates_service.dart';
import '../finance/finance_providers.dart';
import '../finance/ledger.dart';
import '../wallets/wallet_widgets.dart';

/// Купівля, продаж або переказ активу. Нова операція ([trade] == null) або редагування.
///
/// Купівля: гроші з гаманця → актив у гаманець (не витрата).
/// Продаж: актив з гаманця → гроші в гаманець; різниця з ціною купівлі —
/// автоматичний запис «Інвестиційний прибуток / збиток».
/// Переказ: актив з одного гаманця в інший.
class TradeFormScreen extends ConsumerStatefulWidget {
  const TradeFormScreen({
    super.key,
    this.type = TradeType.buy,
    this.assetId,
    this.walletId,
    this.trade,
  });

  final TradeType type;
  final String? assetId;
  final String? walletId;
  final AssetTrade? trade;

  @override
  ConsumerState<TradeFormScreen> createState() => _TradeFormScreenState();
}

class _TradeFormScreenState extends ConsumerState<TradeFormScreen> {
  late TradeType _type;
  String? _assetId; // null + _newAsset = новий актив
  bool _newAsset = false;
  final _code = TextEditingController();
  final _name = TextEditingController();
  AssetKind _kind = AssetKind.crypto;

  late final TextEditingController _units;
  late final TextEditingController _fiat;
  late final TextEditingController _note;
  String? _wallet; // де актив (купівля — куди; продаж / переказ — звідки)
  String? _toWallet; // переказ — куди
  String? _fiatWallet;
  String? _fiatCurrency;

  /// Актив, який уже був до додатка: гроші не списуються, ціна купівлі — довідкова.
  bool _existing = false;
  late DateTime _date;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.trade != null;

  @override
  void initState() {
    super.initState();
    final t = widget.trade;
    _type = t?.type ?? widget.type;
    _assetId = t?.assetId ?? widget.assetId;
    _units = TextEditingController(
      text: t == null ? '' : unitsToInput(t.units),
    );
    _fiat = TextEditingController(
      text: t?.fiatCents == null ? '' : centsToInput(t!.fiatCents!),
    );
    _note = TextEditingController(text: t?.note ?? '');
    _wallet = t?.walletId ?? widget.walletId;
    _toWallet = t?.toWalletId;
    _fiatWallet = t?.fiatWalletId;
    _fiatCurrency = t?.fiatCurrency;
    _existing = t != null && t.type == TradeType.buy && t.fiatWalletId == null;
    _date = t?.date ?? DateTime.now();
  }

  @override
  void dispose() {
    for (final c in [_code, _name, _units, _fiat, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Позиція активу без цієї операції (щоб при редагуванні не рахувати її двічі).
  AssetPosition? _positionWithoutThis() {
    if (_assetId == null) return null;
    final trades = (ref.read(tradesProvider).value ?? const <AssetTrade>[])
        .where((t) => t.id != widget.trade?.id)
        .toList();
    final entries = ref.read(allEntriesProvider).value ?? const <MoneyEntry>[];
    return assetPositions(trades: trades, entries: entries)[_assetId];
  }

  @override
  Widget build(BuildContext context) {
    final assets = ref.watch(assetsProvider).value ?? const <Asset>[];
    final wallets = (ref.watch(walletsProvider).value ?? const <Wallet>[])
        .where(
          (w) =>
              !w.archived || {_wallet, _toWallet, _fiatWallet}.contains(w.id),
        )
        .toList();
    final allCurrencies =
        ref.watch(walletCurrenciesProvider).value ?? const <WalletCurrency>[];
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};
    ref.watch(tradesProvider);
    ref.watch(allEntriesProvider);

    if (!_newAsset &&
        _assetId == null &&
        assets.isEmpty &&
        _type == TradeType.buy) {
      _newAsset = true;
    }
    final asset = assets.where((a) => a.id == _assetId).firstOrNull;
    final position = _positionWithoutThis();

    // Продаж / переказ: стандартно — гаманець, де цього активу найбільше.
    if (_wallet == null && _type != TradeType.buy && position != null) {
      final held =
          position.unitsByWallet.entries.where((e) => e.value > 0).toList()
            ..sort((a, b) => b.value.compareTo(a.value));
      _wallet = held.firstOrNull?.key;
    }
    _wallet ??= wallets.firstOrNull?.id;
    _fiatWallet ??= _wallet;
    if (_type == TradeType.move) {
      _toWallet ??= wallets.where((w) => w.id != _wallet).firstOrNull?.id;
    }
    final existing = _existing && _type == TradeType.buy;
    final fiatCodes = existing
        // Ціна купівлі — у будь-якій валюті, не прив'язаній до гаманця.
        ? {
            baseCurrency,
            ...RatesService.displayCurrencies,
            ...allCurrencies.where((c) => !c.deleted).map((c) => c.currency),
            ?asset?.basisCurrency,
          }.where(isFiat).toList()
        : _fiatWallet == null
        ? <String>[]
        : currenciesOfWallet(allCurrencies, _fiatWallet!);
    if (_fiatCurrency == null || !fiatCodes.contains(_fiatCurrency)) {
      _fiatCurrency = fiatCodes.contains(asset?.basisCurrency)
          ? asset!.basisCurrency
          : fiatCodes.firstOrNull;
    }

    final units = parseUnits(_units.text);
    final fiat = parseAmountToCents(_fiat.text);
    final code =
        asset?.code ??
        (_code.text.trim().isEmpty ? '?' : _code.text.trim().toUpperCase());
    final available = (position != null && _wallet != null)
        ? position.unitsIn(_wallet!)
        : 0;

    // Підказки під формою.
    final hints = <String>[];
    if (_type != TradeType.move &&
        units != null &&
        units > 0 &&
        fiat != null &&
        fiat > 0) {
      final price = fiat * unitsScale / units;
      hints.add(
        'Ціна: ${formatMoney(price.round(), _fiatCurrency!)} за 1 $code',
      );
    }
    if (_type == TradeType.sell &&
        position != null &&
        asset != null &&
        units != null &&
        units > 0) {
      final cost = position.costOf(units);
      hints.add(
        'Ціна купівлі цієї кількості: ${formatMoney(cost, asset.basisCurrency)}',
      );
      if (fiat != null && _fiatCurrency != null) {
        final costInFiat = convertCents(
          cost,
          asset.basisCurrency,
          _fiatCurrency!,
          rates,
        );
        if (costInFiat == null) {
          hints.add(
            'Немає курсу ${asset.basisCurrency}→$_fiatCurrency, щоб порахувати прибуток',
          );
        } else {
          final pnl = fiat - costInFiat;
          hints.add(
            pnl >= 0
                ? 'Прибуток: ${formatMoney(pnl, _fiatCurrency!, sign: 1)} → у надходження'
                : 'Збиток: ${formatMoney(pnl, _fiatCurrency!)} → у витрати',
          );
        }
      }
    }

    final title = switch (_type) {
      TradeType.buy => _isEdit ? 'Купівля' : 'Купити актив',
      TradeType.sell => _isEdit ? 'Продаж' : 'Продати актив',
      TradeType.move => _isEdit ? 'Переказ активу' : 'Переказати актив',
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (_isEdit)
            IconButton(
              tooltip: 'Видалити',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (!_isEdit)
              SegmentedButton<TradeType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TradeType.buy, label: Text('Купівля')),
                  ButtonSegment(value: TradeType.sell, label: Text('Продаж')),
                  ButtonSegment(value: TradeType.move, label: Text('Переказ')),
                ],
                selected: {_type},
                onSelectionChanged: (v) => setState(() {
                  _type = v.first;
                  _error = null;
                  if (_type != TradeType.buy) {
                    _newAsset = false;
                    _wallet = null; // підставимо гаманець, де актив є
                  }
                }),
              ),
            const SizedBox(height: 16),
            _assetPicker(assets),
            if (_newAsset) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _code,
                      textCapitalization: TextCapitalization.characters,
                      maxLength: 10,
                      decoration: const InputDecoration(
                        labelText: 'Тікер',
                        hintText: 'BTC',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _name,
                      maxLength: 40,
                      decoration: const InputDecoration(
                        labelText: 'Назва',
                        hintText: 'Bitcoin',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              SegmentedButton<AssetKind>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: AssetKind.crypto, label: Text('Крипта')),
                  ButtonSegment(
                    value: AssetKind.stock,
                    label: Text('Акції / ETF'),
                  ),
                  ButtonSegment(value: AssetKind.other, label: Text('Інше')),
                ],
                selected: {_kind},
                onSelectionChanged: (v) => setState(() => _kind = v.first),
              ),
            ],
            const SizedBox(height: 16),
            _walletDropdown(
              label: switch (_type) {
                TradeType.buy => 'Куди зарахувати актив',
                TradeType.sell => 'З якого гаманця продаєш',
                TradeType.move => 'Звідки',
              },
              wallets: wallets,
              value: _wallet,
              onChanged: (v) => setState(() {
                _wallet = v;
                if (_type == TradeType.buy && _fiatWallet == null) {
                  _fiatWallet = v;
                }
              }),
            ),
            if (_type == TradeType.move) ...[
              const SizedBox(height: 12),
              _walletDropdown(
                label: 'Куди',
                wallets: wallets,
                value: _toWallet,
                onChanged: (v) => setState(() => _toWallet = v),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _units,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: Theme.of(context).textTheme.titleLarge,
              decoration: InputDecoration(
                labelText: 'Кількість',
                suffixText: code,
                helperText: _type == TradeType.buy || asset == null
                    ? 'До 8 знаків після коми'
                    : 'Є в гаманці: ${formatUnits(available, code)}',
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (_type == TradeType.buy)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Уже маю — купив раніше'),
                subtitle: Text(
                  existing
                      ? 'Гроші не списуються. Вкажи, за скільки купував — для прибутку при продажі'
                      : 'Увімкни, щоб додати актив, який був до додатка',
                ),
                value: _existing,
                onChanged: (v) => setState(() {
                  _existing = v;
                  _error = null;
                }),
              ),
            if (_type != TradeType.move) ...[
              const SizedBox(height: 16),
              Text(
                existing
                    ? 'За скільки купував'
                    : (_type == TradeType.buy ? 'Чим платиш' : 'Що отримуєш'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              if (!existing) ...[
                _walletDropdown(
                  label: _type == TradeType.buy ? 'З гаманця' : 'У гаманець',
                  wallets: wallets,
                  value: _fiatWallet,
                  onChanged: (v) => setState(() => _fiatWallet = v),
                ),
                const SizedBox(height: 8),
              ],
              Wrap(
                spacing: 8,
                children: [
                  for (final c in fiatCodes)
                    ChoiceChip(
                      label: Text(c),
                      selected: c == _fiatCurrency,
                      onSelected: (_) => setState(() => _fiatCurrency = c),
                    ),
                ],
              ),
              if (fiatCodes.isEmpty)
                Text(
                  'У цьому гаманці немає валют — додай валюту в гаманці',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _fiat,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                ],
                style: Theme.of(context).textTheme.titleLarge,
                decoration: InputDecoration(
                  labelText: existing
                      ? 'Ціна купівлі (усього)'
                      : (_type == TradeType.buy ? 'Сплачено' : 'Отримано'),
                  suffixText: _fiatCurrency == null
                      ? null
                      : currencySymbol(_fiatCurrency!),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
            for (final h in hints)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  h,
                  style: TextStyle(
                    color: h.startsWith('Збиток')
                        ? AppColors.expense
                        : h.startsWith('Прибуток')
                        ? AppColors.income
                        : Theme.of(context).colorScheme.primary,
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: const Text('Дата'),
              trailing: Text(
                DateFormat('d MMMM y', 'uk').format(_date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              onTap: _pickDate,
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
                onPressed: _saving ? null : () => _save(asset, position, rates),
                child: const Text('Зберегти', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _assetPicker(List<Asset> assets) {
    const newValue = '__new__';
    return DropdownButtonFormField<String>(
      key: ValueKey('asset-${_newAsset ? newValue : _assetId}'),
      initialValue: _newAsset ? newValue : _assetId,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Актив',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final a in assets)
          DropdownMenuItem(
            value: a.id,
            child: Text(
              '${a.code} · ${a.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
        if (_type == TradeType.buy && !_isEdit)
          const DropdownMenuItem(value: newValue, child: Text('+ Новий актив')),
      ],
      onChanged: _isEdit
          ? null
          : (v) => setState(() {
              _newAsset = v == newValue;
              _assetId = v == newValue ? null : v;
              _error = null;
              if (_type != TradeType.buy) _wallet = null;
            }),
    );
  }

  Widget _walletDropdown({
    required String label,
    required List<Wallet> wallets,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$label-$value'),
      initialValue: wallets.any((w) => w.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final w in wallets)
          DropdownMenuItem(
            value: w.id,
            child: Row(
              children: [
                Icon(walletIcon(w.icon), color: Color(w.color), size: 20),
                const SizedBox(width: 10),
                Flexible(child: Text(w.name, overflow: TextOverflow.ellipsis)),
              ],
            ),
          ),
      ],
      onChanged: onChanged,
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save(
    Asset? asset,
    AssetPosition? position,
    Map<String, ExchangeRate> rates,
  ) async {
    final units = parseUnits(_units.text);
    final fiat = parseAmountToCents(_fiat.text);
    final available = (position != null && _wallet != null)
        ? position.unitsIn(_wallet!)
        : 0;
    final existing = _existing && _type == TradeType.buy;

    String? error;
    if (_newAsset && _code.text.trim().isEmpty) {
      error = 'Введи тікер активу, напр. BTC';
    } else if (!_newAsset && asset == null) {
      error = 'Вибери актив';
    } else if (_wallet == null) {
      error = 'Вибери гаманець';
    } else if (units == null || units == 0) {
      error = 'Введи кількість більше нуля';
    } else if (_type != TradeType.buy && units > available) {
      error = 'У гаманці лише ${formatUnits(available, asset!.code)}';
    } else if (_type == TradeType.move &&
        (_toWallet == null || _toWallet == _wallet)) {
      error = 'Вибери інший гаманець призначення';
    } else if (_type != TradeType.move &&
        ((!existing && _fiatWallet == null) || _fiatCurrency == null)) {
      error = 'Вибери гаманець і валюту';
    } else if (_type != TradeType.move && (fiat == null || fiat == 0)) {
      error = existing
          ? 'Введи, за скільки купував (можна приблизно)'
          : (_type == TradeType.buy
                ? 'Введи, скільки сплачено'
                : 'Введи, скільки отримано');
    }

    // Ціна купівлі в обліковій валюті активу.
    var basis = 0;
    var pnl = 0;
    final basisCurrency = asset?.basisCurrency ?? _fiatCurrency;
    if (error == null && _type == TradeType.buy) {
      final b = convertCents(fiat!, _fiatCurrency!, basisCurrency!, rates);
      if (b == null) {
        error =
            'Немає курсу $_fiatCurrency→$basisCurrency. Онови курси (потрібен інтернет).';
      } else {
        basis = b;
      }
    }
    if (error == null && _type == TradeType.sell) {
      basis = position!.costOf(units!);
      final costInFiat = convertCents(
        basis,
        asset!.basisCurrency,
        _fiatCurrency!,
        rates,
      );
      if (costInFiat == null) {
        error =
            'Немає курсу ${asset.basisCurrency}→$_fiatCurrency. Онови курси (потрібен інтернет).';
      } else {
        pnl = fiat! - costInFiat;
      }
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    try {
      var assetId = _assetId;
      if (_newAsset) {
        assetId = await db.addAsset(
          code: _code.text,
          name: _name.text.trim().isEmpty
              ? _code.text.trim().toUpperCase()
              : _name.text,
          kind: _kind,
          basisCurrency: basisCurrency!,
        );
      }
      final code = asset?.code ?? _code.text.trim().toUpperCase();
      await db.saveTrade(
        id: widget.trade?.id,
        type: _type,
        assetId: assetId!,
        units: units!,
        walletId: _wallet!,
        toWalletId: _type == TradeType.move ? _toWallet : null,
        // Наявний актив — без гаманця грошей, тож баланс не змінюється.
        fiatWalletId: _type == TradeType.move || existing ? null : _fiatWallet,
        fiatCurrency: _type == TradeType.move ? null : _fiatCurrency,
        fiatCents: _type == TradeType.move ? null : fiat,
        basisCents: basis,
        pnlCents: pnl,
        date: _date,
        note: _note.text,
        pnlNote: 'Продаж ${unitsToInput(units)} $code',
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Не вдалося зберегти: $e')));
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити операцію?'),
        content: const Text(
          'Запис прибутку чи збитку від неї теж буде видалено.',
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
    if (ok != true) return;
    await ref.read(databaseProvider).setTradeDeleted(widget.trade!.id, true);
    if (mounted) Navigator.of(context).pop();
  }
}
