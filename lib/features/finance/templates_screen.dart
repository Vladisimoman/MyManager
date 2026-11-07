import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../wallets/wallet_widgets.dart';
import 'entry_form_screen.dart';
import 'finance_providers.dart';
import 'recurring.dart';
import 'widgets/category_avatar.dart';
import 'widgets/entry_list.dart' show dayLabel;

/// Шаблони й регулярні платежі (етап 12).

final templatesProvider = StreamProvider<List<EntryTemplate>>(
  (ref) => ref.watch(databaseProvider).watchTemplates(),
);

final handledOccurrencesProvider = StreamProvider<Set<String>>(
  (ref) => ref.watch(databaseProvider).watchHandledOccurrences(),
);

/// Платежі, що чекають підтвердження сьогодні.
final pendingPaymentsProvider = Provider<List<PendingPayment>>((ref) {
  final templates = ref.watch(templatesProvider).value;
  final handled = ref.watch(handledOccurrencesProvider).value;
  if (templates == null || handled == null) return const [];
  return pendingPayments(templates, handled, DateTime.now());
});

String _date(DateTime d) => DateFormat('d MMMM y', 'uk').format(d);

/// «15 листопада» (цей рік) або «15 листопада 2027».
String _shortDate(DateTime d) => d.year == DateTime.now().year
    ? DateFormat('d MMMM', 'uk').format(d)
    : _date(d);

String _amountText(EntryTemplate t) => formatMoney(
  t.amountCents,
  t.currency,
  sign: t.type == EntryType.income ? 1 : -1,
);

/// Записати шаблон одним дотиком (на [date], з id [id] для регулярного платежу).
Future<String> recordTemplate(
  AppDatabase db,
  EntryTemplate t, {
  DateTime? date,
  String? id,
}) => db.addEntry(
  id: id,
  type: t.type,
  amountCents: t.amountCents,
  currency: t.currency,
  categoryId: t.categoryId,
  date: date ?? DateTime.now(),
  note: t.note ?? t.name,
  walletId: t.walletId,
);

void openTemplateEditor(
  BuildContext context, {
  EntryTemplate? template,
  EntryType? type,
}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => TemplateEditScreen(template: template, type: type),
    ),
  );
}

/// Форма запису, заповнена з шаблону (для «Змінити» в очікуваному платежі).
void openPaymentForm(BuildContext context, PendingPayment p) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EntryFormScreen(
        type: p.template.type,
        template: p.template,
        presetDate: p.date,
        fixedId: p.id,
      ),
    ),
  );
}

// ---------------- Блок на екрані Finance ----------------

class PendingPaymentsCard extends ConsumerWidget {
  const PendingPaymentsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pending = ref.watch(pendingPaymentsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final db = ref.read(databaseProvider);
    return Card(
      elevation: 0,
      color: scheme.tertiaryContainer,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                'Очікують підтвердження (${pending.length})',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ),
            for (final p in pending)
              ListTile(
                key: ValueKey(p.id),
                contentPadding: const EdgeInsets.only(left: 12, right: 0),
                leading: CategoryAvatar(
                  category: categories[p.template.categoryId],
                ),
                title: Text(
                  p.template.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${_amountText(p.template)}\n${_pendingDay(p.date)}',
                  maxLines: 2,
                ),
                isThreeLine: true,
                onTap: () => openPaymentForm(context, p),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => recordTemplate(
                        db,
                        p.template,
                        date: p.date,
                        id: p.id,
                      ),
                      child: const Text('Записати'),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Ще',
                      onSelected: (v) {
                        if (v == 'edit') openPaymentForm(context, p);
                        if (v == 'skip') _skip(context, db, p);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text('Змінити суму…'),
                        ),
                        PopupMenuItem(value: 'skip', child: Text('Пропустити')),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _skip(
    BuildContext context,
    AppDatabase db,
    PendingPayment p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await db.skipOccurrence(p.template, p.id, p.date);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Пропущено: ${p.template.name}, ${dayLabel(p.date).toLowerCase()}',
          ),
          // Скасувати = прибрати позначку, щоб платіж знову чекав.
          persist: false, // зникає сама, навіть з кнопкою
          action: SnackBarAction(
            label: 'Скасувати',
            onPressed: () => db.deleteEntryRow(p.id),
          ),
        ),
      );
  }
}

String _pendingDay(DateTime d) {
  final label = dayLabel(d);
  // «Сьогодні» / «Вчора» лишаємо, решту — коротко.
  return label.contains(RegExp(r'\d')) ? _shortDate(d) : label;
}

// ---------------- Шаблони у формі запису ----------------

/// Рядок шаблонів зверху форми нового запису: дотик — одразу записати на сьогодні,
/// довге натискання — заповнити форму.
class TemplateChips extends ConsumerWidget {
  const TemplateChips({
    super.key,
    required this.type,
    required this.onFill,
    required this.onRecorded,
  });

  final EntryType type;
  final ValueChanged<EntryTemplate> onFill;
  final ValueChanged<EntryTemplate> onRecorded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = (ref.watch(templatesProvider).value ?? const <EntryTemplate>[])
        .where((t) => t.type == type)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    final db = ref.read(databaseProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Шаблони — дотик записує на сьогодні, довге натискання — заповнює форму',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final t in list)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onLongPress: () => onFill(t),
                      child: ActionChip(
                        avatar: const Icon(Icons.bolt, size: 18),
                        label: Text(
                          '${t.name} · ${formatMoney(t.amountCents, t.currency)}',
                        ),
                        onPressed: () async {
                          await recordTemplate(db, t);
                          onRecorded(t);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------- Список шаблонів ----------------

class TemplatesScreen extends ConsumerWidget {
  const TemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final list = ref.watch(templatesProvider).value ?? const <EntryTemplate>[];
    final handled =
        ref.watch(handledOccurrencesProvider).value ?? const <String>{};
    final categories =
        ref.watch(categoryMapProvider).value ?? const <String, Category>{};
    final recurring = list.where(isRecurring).toList();
    final simple = list.where((t) => !isRecurring(t)).toList();
    final today = DateTime.now();

    Widget tile(EntryTemplate t) {
      final next = nextOccurrence(t, handled, today);
      return ListTile(
        leading: CategoryAvatar(category: categories[t.categoryId]),
        title: Text(t.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          isRecurring(t)
              ? '${repeatLabel(t.repeat)}${next == null ? '' : ' · ${_shortDate(next)}'}'
              : (categories[t.categoryId]?.name ?? ''),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          _amountText(t),
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: t.type == EntryType.income
                ? AppColors.income
                : AppColors.expense,
          ),
        ),
        onTap: () => openTemplateEditor(context, template: t),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Шаблони й регулярні')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => openTemplateEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Новий'),
      ),
      body: SafeArea(
        child: list.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Тут будуть шаблони («Кава 3,50 € з картки») і регулярні платежі '
                    '(підписки, оренда, зарплата).\n\nНатисни «Новий» або збережи запис '
                    'як шаблон прямо у формі витрати.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  if (recurring.isNotEmpty) ...[
                    _Header('Регулярні платежі'),
                    for (final t in recurring) tile(t),
                  ],
                  if (simple.isNotEmpty) ...[
                    _Header('Шаблони'),
                    for (final t in simple) tile(t),
                  ],
                ],
              ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(
      text,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
}

// ---------------- Форма шаблону ----------------

class TemplateEditScreen extends ConsumerStatefulWidget {
  const TemplateEditScreen({super.key, this.template, this.type});

  final EntryTemplate? template;
  final EntryType? type;

  @override
  ConsumerState<TemplateEditScreen> createState() => _TemplateEditScreenState();
}

class _TemplateEditScreenState extends ConsumerState<TemplateEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _note;
  late EntryType _type;
  late String _walletId;
  late String _currency;
  String? _categoryId;
  late RepeatKind _repeat;
  late DateTime _start;
  String? _nameError;
  String? _amountError;
  bool _categoryError = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final t = widget.template;
    _name = TextEditingController(text: t?.name ?? '');
    _amount = TextEditingController(
      text: t == null ? '' : centsToInput(t.amountCents),
    );
    _note = TextEditingController(text: t?.note ?? '');
    _type = t?.type ?? widget.type ?? EntryType.expense;
    _walletId = t?.walletId ?? AppDatabase.mainWalletId;
    _currency = t?.currency ?? baseCurrency;
    _categoryId = t?.categoryId;
    _repeat = t?.repeat ?? RepeatKind.none;
    _start = t?.startDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final wallets = (ref.watch(walletsProvider).value ?? const <Wallet>[])
        .where((w) => !w.archived || w.id == _walletId)
        .toList();
    final codes = currenciesOfWallet(
      ref.watch(walletCurrenciesProvider).value ?? const <WalletCurrency>[],
      _walletId,
    );
    final currencyOptions = codes.contains(_currency) || codes.isEmpty
        ? [...codes, if (!codes.contains(_currency)) _currency]
        : codes;
    if (!currencyOptions.contains(_currency)) _currency = currencyOptions.first;
    final categories =
        (ref.watch(categoriesProvider(_type)).value ?? const <Category>[])
            .where((c) => !c.hidden || c.id == _categoryId)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.template == null ? 'Новий шаблон' : 'Шаблон'),
        actions: [
          if (widget.template != null)
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
            SegmentedButton<EntryType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: EntryType.expense, label: Text('Витрата')),
                ButtonSegment(
                  value: EntryType.income,
                  label: Text('Надходження'),
                ),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() {
                _type = v.first;
                _categoryId = null;
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _name,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Назва',
                hintText: 'Наприклад, Netflix або Кава',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _nameError = null),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: text.titleLarge,
              decoration: InputDecoration(
                labelText: 'Сума',
                errorText: _amountError,
                helperText: _repeat == RepeatKind.none
                    ? null
                    : 'Якщо сума щоразу інша — зміниш при підтвердженні',
                suffixText: currencySymbol(_currency),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _amountError = null),
            ),
            const SizedBox(height: 12),
            if (wallets.length > 1) ...[
              Text(
                _type == EntryType.income
                    ? 'Куди (гаманець)'
                    : 'Звідки (гаманець)',
                style: text.titleSmall,
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
              const SizedBox(height: 8),
            ],
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in currencyOptions)
                  ChoiceChip(
                    label: Text(c),
                    selected: c == _currency,
                    onSelected: (_) => setState(() => _currency = c),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Категорія', style: text.titleSmall),
            if (_categoryError)
              Text('Вибери категорію', style: TextStyle(color: scheme.error)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in categories)
                  ChoiceChip(
                    showCheckmark: false,
                    avatar: CategoryAvatar(category: c, size: 22),
                    label: Text(c.name),
                    selected: c.id == _categoryId,
                    onSelected: (_) => setState(() {
                      _categoryId = c.id;
                      _categoryError = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Text('Повторення', style: text.titleSmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final r in RepeatKind.values)
                  ChoiceChip(
                    label: Text(repeatLabel(r)),
                    selected: r == _repeat,
                    onSelected: (_) => setState(() => _repeat = r),
                  ),
              ],
            ),
            if (_repeat != RepeatKind.none) ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_repeat_outlined),
                title: const Text('Перший платіж'),
                trailing: Text(_date(_start), style: text.titleMedium),
                onTap: _pickStart,
              ),
              Text(
                '${switch (_repeat) {
                  RepeatKind.weekly => 'Кожного тижня в той самий день тижня.',
                  RepeatKind.monthly => 'Щомісяця ${_start.day}-го числа (у коротших місяцях — в останній день).',
                  RepeatKind.yearly => 'Щороку ${DateFormat('d MMMM', 'uk').format(_start)}.',
                  RepeatKind.none => '',
                }} У день платежу на екрані Finance з\'явиться «Очікують підтвердження».',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _note,
              maxLength: 200,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Коментар до записів (необов\'язково)',
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

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2, 12, 31),
    );
    if (d != null) setState(() => _start = d);
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_amount.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Введи назву' : null;
      _amountError = (cents == null || cents == 0)
          ? 'Введи суму, напр. 12,99'
          : null;
      _categoryError = _categoryId == null;
    });
    if (_nameError != null || _amountError != null || _categoryError) return;
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .saveTemplate(
          id: widget.template?.id,
          type: _type,
          name: _name.text,
          amountCents: cents!,
          currency: _currency,
          categoryId: _categoryId!,
          walletId: _walletId,
          note: _note.text,
          repeat: _repeat,
          startDate: _start,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final t = widget.template!;
    final db = ref.read(databaseProvider);
    final messenger = ScaffoldMessenger.of(context);
    await db.setTemplateDeleted(t.id, true);
    if (mounted) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Шаблон «${t.name}» видалено. Уже зроблені записи лишаються.',
        ),
        persist: false, // зникає сама, навіть з кнопкою
        action: SnackBarAction(
          label: 'Скасувати',
          onPressed: () => db.setTemplateDeleted(t.id, false),
        ),
      ),
    );
  }
}
