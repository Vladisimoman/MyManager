import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../data/database.dart';
import '../finance/finance_providers.dart';
import 'wallet_widgets.dart';

/// Переказ між гаманцями або обмін валют (у тому ж гаманці чи між різними).
/// Обидві суми вводяться вручну — курс обмінника буває свій.
class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key, this.transfer, this.fromWalletId});

  final Transfer? transfer;
  final String? fromWalletId;

  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  late final TextEditingController _fromAmount;
  late final TextEditingController _toAmount;
  late final TextEditingController _note;
  String? _fromWallet, _fromCurrency, _toWallet, _toCurrency;
  late DateTime _date;
  String? _error;
  bool _saving = false;

  bool get _isEdit => widget.transfer != null;
  bool get _sameCurrency =>
      _fromCurrency != null && _fromCurrency == _toCurrency;

  @override
  void initState() {
    super.initState();
    final t = widget.transfer;
    _fromAmount = TextEditingController(
      text: t == null ? '' : centsToInput(t.fromAmountCents),
    );
    _toAmount = TextEditingController(
      text: t == null ? '' : centsToInput(t.toAmountCents),
    );
    _note = TextEditingController(text: t?.note ?? '');
    _date = t?.date ?? DateTime.now();
    _fromWallet = t?.fromWalletId ?? widget.fromWalletId;
    _fromCurrency = t?.fromCurrency;
    _toWallet = t?.toWalletId;
    _toCurrency = t?.toCurrency;
  }

  @override
  void dispose() {
    _fromAmount.dispose();
    _toAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wallets = (ref.watch(walletsProvider).value ?? const <Wallet>[])
        .where((w) => !w.archived || w.id == _fromWallet || w.id == _toWallet)
        .toList();
    final allCurrencies =
        ref.watch(walletCurrenciesProvider).value ?? const <WalletCurrency>[];

    // Значення за замовчуванням: перший гаманець → другий, перша валюта кожного.
    _fromWallet ??= wallets.isNotEmpty ? wallets.first.id : null;
    _toWallet ??=
        wallets.where((w) => w.id != _fromWallet).firstOrNull?.id ??
        _fromWallet;
    final fromCurrencies = _fromWallet == null
        ? <String>[]
        : currenciesOfWallet(allCurrencies, _fromWallet!);
    final toCurrencies = _toWallet == null
        ? <String>[]
        : currenciesOfWallet(allCurrencies, _toWallet!);
    if (_fromCurrency == null || !fromCurrencies.contains(_fromCurrency)) {
      _fromCurrency = fromCurrencies.firstOrNull;
    }
    if (_toCurrency == null || !toCurrencies.contains(_toCurrency)) {
      _toCurrency = toCurrencies.contains(_fromCurrency)
          ? _fromCurrency
          : toCurrencies.firstOrNull;
    }

    final from = parseAmountToCents(_fromAmount.text);
    final to = _sameCurrency ? from : parseAmountToCents(_toAmount.text);
    String? rateText;
    if (!_sameCurrency && from != null && to != null && from > 0 && to > 0) {
      final r = to / from;
      final f = NumberFormat.decimalPatternDigits(
        locale: 'uk',
        decimalDigits: r >= 10 ? 2 : 4,
      );
      rateText = 'Курс: 1 $_fromCurrency = ${f.format(r)} $_toCurrency';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Переказ' : 'Новий переказ'),
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
            _side(
              title: 'Звідки',
              wallets: wallets,
              walletId: _fromWallet,
              currencies: fromCurrencies,
              currency: _fromCurrency,
              amount: _fromAmount,
              onWallet: (id) => setState(() => _fromWallet = id),
              onCurrency: (c) => setState(() => _fromCurrency = c),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Icon(Icons.arrow_downward, size: 28),
            ),
            _side(
              title: 'Куди',
              wallets: wallets,
              walletId: _toWallet,
              currencies: toCurrencies,
              currency: _toCurrency,
              amount: _sameCurrency ? null : _toAmount,
              onWallet: (id) => setState(() => _toWallet = id),
              onCurrency: (c) => setState(() => _toCurrency = c),
            ),
            if (rateText != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  rateText,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
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
            const SizedBox(height: 12),
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
                onPressed: _saving ? null : _save,
                child: const Text('Зберегти', style: TextStyle(fontSize: 18)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _side({
    required String title,
    required List<Wallet> wallets,
    required String? walletId,
    required List<String> currencies,
    required String? currency,
    required TextEditingController? amount,
    required ValueChanged<String> onWallet,
    required ValueChanged<String> onCurrency,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: walletId,
              isExpanded: true,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final w in wallets)
                  DropdownMenuItem(
                    value: w.id,
                    child: Row(
                      children: [
                        Icon(
                          walletIcon(w.icon),
                          color: Color(w.color),
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(w.name, overflow: TextOverflow.ellipsis),
                        ),
                      ],
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onWallet(v);
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in currencies)
                  ChoiceChip(
                    label: Text(c),
                    selected: c == currency,
                    onSelected: (_) => onCurrency(c),
                  ),
              ],
            ),
            if (amount != null) ...[
              const SizedBox(height: 8),
              TextField(
                controller: amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                ],
                style: Theme.of(context).textTheme.titleLarge,
                decoration: InputDecoration(
                  labelText: title == 'Звідки' ? 'Сума' : 'Отримано',
                  suffixText: currency == null
                      ? null
                      : currencySymbol(currency),
                  border: const OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() => _error = null),
              ),
            ],
          ],
        ),
      ),
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

  Future<void> _save() async {
    final from = parseAmountToCents(_fromAmount.text);
    final to = _sameCurrency ? from : parseAmountToCents(_toAmount.text);
    String? error;
    if (_fromWallet == null ||
        _toWallet == null ||
        _fromCurrency == null ||
        _toCurrency == null) {
      error = 'Вибери гаманці й валюти';
    } else if (_fromWallet == _toWallet && _sameCurrency) {
      error = 'Вибери інший гаманець або іншу валюту';
    } else if (from == null || from == 0) {
      error = 'Введи суму більше нуля';
    } else if (to == null || to == 0) {
      error = 'Введи, скільки отримано';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    try {
      if (_isEdit) {
        await db.updateTransfer(
          widget.transfer!.id,
          fromWalletId: _fromWallet!,
          fromCurrency: _fromCurrency!,
          fromAmountCents: from!,
          toWalletId: _toWallet!,
          toCurrency: _toCurrency!,
          toAmountCents: to!,
          date: _date,
          note: _note.text,
        );
      } else {
        await db.addTransfer(
          fromWalletId: _fromWallet!,
          fromCurrency: _fromCurrency!,
          fromAmountCents: from!,
          toWalletId: _toWallet!,
          toCurrency: _toCurrency!,
          toAmountCents: to!,
          date: _date,
          note: _note.text,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не вдалося зберегти переказ: $e')),
      );
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити переказ?'),
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
    await ref
        .read(databaseProvider)
        .setTransferDeleted(widget.transfer!.id, true);
    if (mounted) Navigator.of(context).pop();
  }
}
