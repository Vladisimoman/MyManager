import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../data/rates_service.dart';
import 'finance_providers.dart';
import 'widgets/category_avatar.dart';
import '../wallets/wallet_widgets.dart';
import '../assets/assets_screen.dart' show assetKindIcon;
import 'budgets_screen.dart' show BudgetWarning;
import 'ledger.dart';
import 'templates_screen.dart' show TemplateChips;

/// Додавання нового запису або редагування існуючого ([entry] != null).
class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({
    super.key,
    required this.type,
    this.entry,
    this.template,
    this.presetDate,
    this.fixedId,
  });

  final EntryType type;
  final MoneyEntry? entry;

  /// Новий запис, заповнений із шаблону / регулярного платежу (етап 12).
  final EntryTemplate? template;
  final DateTime? presetDate;

  /// Сталий id запису регулярного платежу.
  final String? fixedId;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late String _currency;
  late String _walletId;

  /// Витрата активом (етап 8): що списуємо з гаманця замість валюти.
  String? _assetId;
  late final String _initialWalletId;
  late DateTime _date;
  String? _categoryId;
  String? _amountError;
  bool _categoryError = false;
  bool _saving = false;
  bool _done = false; // збережено або видалено — виходимо без питань

  bool get _isEdit => widget.entry != null;

  /// Чи змінив користувач щось у формі.
  bool get _dirty {
    final e = widget.entry;
    if (e == null) {
      return _amount.text.trim().isNotEmpty ||
          _note.text.trim().isNotEmpty ||
          _categoryId != null ||
          _walletId != _initialWalletId;
    }
    return parseAmountToCents(_amount.text) != e.amountCents ||
        _currency != e.currency ||
        _walletId != e.walletId ||
        _assetId != e.assetId ||
        _categoryId != e.categoryId ||
        _date != e.date ||
        _note.text.trim() != (e.note ?? '');
  }

  bool get _isIncome => widget.type == EntryType.income;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    _assetId = e?.assetId;
    _amount = TextEditingController(
      text: e == null
          ? ''
          : (e.assetUnits != null
                ? unitsToInput(e.assetUnits!)
                : centsToInput(e.amountCents)),
    );
    _note = TextEditingController(text: e?.note ?? '');
    _currency = e?.currency ?? baseCurrency;
    // Новий запис — у гаманець з фільтра (якщо вибрано) або в «Готівку».
    _walletId =
        e?.walletId ??
        ref.read(walletFilterProvider) ??
        AppDatabase.mainWalletId;
    _initialWalletId = _walletId;
    _date = e?.date ?? widget.presetDate ?? DateTime.now();
    _categoryId = e?.categoryId;
    if (e == null && widget.template != null) _fillFrom(widget.template!);
  }

  /// Заповнити форму з шаблону (довге натискання на шаблон або регулярний платіж).
  void _fillFrom(EntryTemplate t) {
    _assetId = null;
    _amount.text = centsToInput(t.amountCents);
    _note.text = t.note ?? t.name;
    _currency = t.currency;
    _walletId = t.walletId;
    _categoryId = t.categoryId;
    _categoryError = false;
    _amountError = null;
  }

  /// «Зберегти як шаблон»: поточні сума, валюта, гаманець, категорія.
  Future<void> _saveAsTemplate() async {
    final cents = parseAmountToCents(_amount.text);
    if (_assetId != null || cents == null || cents == 0 || _categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Спершу введи суму у валюті й вибери категорію')),
      );
      return;
    }
    final category = ref.read(categoryMapProvider).value?[_categoryId];
    final note = _note.text.trim();
    final name = note.isNotEmpty ? note : (category?.name ?? 'Шаблон');
    await ref.read(databaseProvider).saveTemplate(
          type: widget.type,
          name: name,
          amountCents: cents,
          currency: _currency,
          categoryId: _categoryId!,
          walletId: _walletId,
          note: note,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Шаблон «$name» збережено')),
    );
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoriesProvider(widget.type));
    final wallets = (ref.watch(walletsProvider).value ?? const <Wallet>[])
        .where((w) => !w.archived || w.id == _walletId)
        .toList();
    final walletCurrencies = currenciesOfWallet(
      ref.watch(walletCurrenciesProvider).value ?? const <WalletCurrency>[],
      _walletId,
    );
    // Валюта має бути з вибраного гаманця (при редагуванні старого запису — лишаємо як є).
    final currencyOptions = [
      ...walletCurrencies,
      if (!walletCurrencies.contains(_currency) &&
          widget.entry?.currency == _currency)
        _currency,
    ];
    if (currencyOptions.isNotEmpty && !currencyOptions.contains(_currency)) {
      _currency = currencyOptions.first;
    }
    final rates =
        ref.watch(ratesProvider).value ?? const <String, ExchangeRate>{};

    // Активи в гаманці, якими можна заплатити (лише для витрат).
    final assetMap = ref.watch(assetMapProvider);
    final positions = _positionsWithoutThis();
    final walletAssets = _isIncome
        ? const <String, int>{}
        : {
            for (final e in assetsInWallet(positions, _walletId).entries)
              if (e.value > 0) e.key: e.value,
            if (_assetId != null &&
                widget.entry?.assetId == _assetId &&
                widget.entry?.walletId == _walletId)
              _assetId!: positions[_assetId]?.unitsIn(_walletId) ?? 0,
          };
    if (_assetId != null && !walletAssets.containsKey(_assetId)) {
      _assetId = null;
    }
    final asset = _assetId == null ? null : assetMap[_assetId];

    final typedCents = parseAmountToCents(_amount.text);
    final eurHint = (_currency == baseCurrency || typedCents == null)
        ? null
        : toEurCents(typedCents, _currency, rates);
    String? assetHint;
    if (asset != null) {
      final units = parseUnits(_amount.text);
      final have = formatUnits(walletAssets[_assetId] ?? 0, asset.code);
      assetHint = units == null || units == 0
          ? 'Є в гаманці: $have'
          : '≈ ${formatMoney(positions[_assetId]!.costOf(units), asset.basisCurrency)} '
                'за ціною купівлі · є $have';
    }
    // Попередження про бюджет (етап 11): сума витрати в її валюті.
    final int? budgetCents;
    final String budgetCurrency;
    if (asset != null) {
      final units = parseUnits(_amount.text);
      budgetCents = units == null || positions[_assetId] == null ? null : positions[_assetId]!.costOf(units);
      budgetCurrency = asset.basisCurrency;
    } else {
      budgetCents = typedCents;
      budgetCurrency = _currency;
    }
    final accent = _isIncome ? AppColors.income : AppColors.expense;
    final title = _isEdit
        ? 'Редагування'
        : (_isIncome ? 'Нове надходження' : 'Нова витрата');

    return PopScope(
      canPop: _done || !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          setState(() => _done = true);
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (!_isEdit && widget.fixedId == null)
              IconButton(
                tooltip: 'Зберегти як шаблон',
                icon: const Icon(Icons.bookmark_add_outlined),
                onPressed: _saveAsTemplate,
              ),
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
              if (!_isEdit && widget.fixedId == null)
                TemplateChips(
                  type: widget.type,
                  onFill: (t) => setState(() => _fillFrom(t)),
                  onRecorded: (t) {
                    final messenger = ScaffoldMessenger.of(context);
                    setState(() => _done = true);
                    Navigator.of(context).pop();
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          'Записано: ${t.name} · ${formatMoney(t.amountCents, t.currency)}',
                        ),
                      ),
                    );
                  },
                ),
              TextField(
                controller: _amount,
                autofocus: !_isEdit && widget.template == null,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
                ],
                style: Theme.of(context).textTheme.headlineMedium,
                decoration: InputDecoration(
                  labelText: asset != null ? 'Кількість' : 'Сума',
                  errorText: _amountError,
                  helperText: asset != null
                      ? assetHint
                      : _currency == baseCurrency
                      ? null
                      : (eurHint != null
                            ? '≈ ${formatMoney(eurHint, baseCurrency)} за поточним курсом'
                            : 'Курсу $_currency ще немає — у баланс увійде після оновлення'),
                  border: const OutlineInputBorder(),
                  suffixText: asset != null
                      ? asset.code
                      : currencySymbol(_currency),
                ),
                onChanged: (_) => setState(() => _amountError = null),
              ),
              const SizedBox(height: 16),
              if (wallets.length > 1) ...[
                Text(
                  _isIncome ? 'Куди (гаманець)' : 'Звідки (гаманець)',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
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
                        selected: w.id == _walletId,
                        onSelected: (_) => setState(() => _walletId = w.id),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in currencyOptions)
                    ChoiceChip(
                      label: Text(c),
                      selected: _assetId == null && c == _currency,
                      onSelected: (_) => setState(() {
                        if (_assetId != null) _amount.clear();
                        _assetId = null;
                        _currency = c;
                      }),
                    ),
                  for (final id in walletAssets.keys)
                    ChoiceChip(
                      avatar: Icon(
                        assetKindIcon(assetMap[id]?.kind ?? AssetKind.other),
                        size: 18,
                      ),
                      showCheckmark: false,
                      label: Text(assetMap[id]?.code ?? '?'),
                      selected: _assetId == id,
                      onSelected: (_) => setState(() {
                        if (_assetId != id) _amount.clear();
                        _assetId = id;
                        _amountError = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text('Категорія', style: Theme.of(context).textTheme.titleMedium),
              if (_categoryError)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'Вибери категорію',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              categories.when(
                loading: () => const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Text('Помилка: $e'),
                data: (visible) => _CategoryGrid(
                  categories: _withCurrent(visible),
                  selectedId: _categoryId,
                  accent: accent,
                  onSelect: (id) => setState(() {
                    _categoryId = id;
                    _categoryError = false;
                  }),
                ),
              ),
              if (!_isIncome && _categoryId != null && budgetCents != null)
                BudgetWarning(
                  categoryId: _categoryId!,
                  amountCents: budgetCents,
                  currency: budgetCurrency,
                  date: _date,
                  excludeEntryId: widget.entry?.id,
                ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 8),
              TextField(
                controller: _note,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Коментар (необов\'язково)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 56,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: accent),
                  onPressed: _saving ? null : _save,
                  child: const Text('Зберегти', style: TextStyle(fontSize: 18)),
                ),
              ),
            ],
          ),
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

  /// Позиції активів без цього запису (щоб при редагуванні не рахувати його двічі).
  Map<String, AssetPosition> _positionsWithoutThis() {
    final entries =
        (ref.watch(allEntriesProvider).value ?? const <MoneyEntry>[])
            .where((e) => e.id != widget.entry?.id)
            .toList();
    return assetPositions(
      trades: ref.watch(tradesProvider).value ?? const [],
      entries: entries,
    );
  }

  Future<void> _save() async {
    var cents = parseAmountToCents(_amount.text);
    var currency = _currency;
    int? units;
    final asset = _assetId == null
        ? null
        : ref.read(assetMapProvider)[_assetId];
    if (asset != null) {
      // Витрата активом: сума — ціна купівлі цієї кількості.
      final position = _positionsWithoutThis()[_assetId];
      units = parseUnits(_amount.text);
      final have = position?.unitsIn(_walletId) ?? 0;
      setState(() {
        _amountError = (units == null || units == 0)
            ? 'Введи кількість, напр. 0,01'
            : (units > have
                  ? 'У гаманці лише ${formatUnits(have, asset.code)}'
                  : null);
        _categoryError = _categoryId == null;
      });
      if (_amountError != null || _categoryError) return;
      cents = position!.costOf(units!);
      currency = asset.basisCurrency;
    } else {
      setState(() {
        _amountError = (cents == null || cents == 0)
            ? 'Введи суму більше нуля, напр. 12,50'
            : null;
        _categoryError = _categoryId == null;
      });
      if (_amountError != null || _categoryError) return;
    }

    setState(() => _saving = true);
    final db = ref.read(databaseProvider);
    try {
      if (_isEdit) {
        await db.updateEntry(
          widget.entry!.id,
          amountCents: cents!,
          currency: currency,
          categoryId: _categoryId!,
          date: _date,
          note: _note.text,
          walletId: _walletId,
          assetId: asset?.id,
          assetUnits: units,
        );
      } else {
        await db.addEntry(
          id: widget.fixedId,
          type: widget.type,
          amountCents: cents!,
          currency: currency,
          categoryId: _categoryId!,
          date: _date,
          note: _note.text,
          walletId: _walletId,
          assetId: asset?.id,
          assetUnits: units,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Не вдалося зберегти запис: $e')));
      return;
    }
    if (!mounted) return;
    setState(() => _done = true);
    Navigator.of(context).pop();
  }

  /// Видимі категорії + категорія запису, що редагується, навіть якщо її приховано.
  List<Category> _withCurrent(List<Category> visible) {
    final id = _categoryId;
    if (id == null || visible.any((c) => c.id == id)) return visible;
    final current = ref.read(categoryMapProvider).value?[id];
    return current == null ? visible : [...visible, current];
  }

  Future<bool> _confirmDiscard() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вийти без збереження?'),
        content: const Text('Внесені зміни буде втрачено.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Залишитись'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Вийти'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Видалити запис?'),
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
    try {
      await ref.read(databaseProvider).setEntryDeleted(widget.entry!.id, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Не вдалося видалити: $e')));
      }
      return;
    }
    if (!mounted) return;
    setState(() => _done = true);
    Navigator.of(context).pop();
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({
    required this.categories,
    required this.selectedId,
    required this.accent,
    required this.onSelect,
  });

  final List<Category> categories;
  final String? selectedId;
  final Color accent;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.82,
      children: [
        for (final c in categories)
          _CategoryCell(
            category: c,
            selected: c.id == selectedId,
            accent: accent,
            onTap: () => onSelect(c.id),
          ),
      ],
    );
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.category,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final Category category;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent : Colors.transparent,
            width: 2,
          ),
          color: selected ? accent.withValues(alpha: 0.08) : null,
        ),
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CategoryAvatar(category: category, size: 40),
            const SizedBox(height: 4),
            Text(
              category.name,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, height: 1.15),
            ),
          ],
        ),
      ),
    );
  }
}
