import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import 'budgets_screen.dart' show budgetCurrencyOptions;
import 'finance_providers.dart';
import 'goals.dart';
import 'widgets/entry_list.dart' show dayLabel;

/// Цілі накопичення (1.15): «на що й скільки збираю» + внески вручну.

final goalsProvider = StreamProvider<List<Goal>>(
  (ref) => ref.watch(databaseProvider).watchGoals(),
);

final goalContributionsProvider = StreamProvider<List<GoalContribution>>(
  (ref) => ref.watch(databaseProvider).watchGoalContributions(),
);

final goalProgressProvider = Provider<Map<String, GoalProgress>>((ref) {
  return goalProgress(
    ref.watch(goalsProvider).value ?? const <Goal>[],
    ref.watch(goalContributionsProvider).value ?? const <GoalContribution>[],
  );
});

const goalIcons = <String, IconData>{
  'savings': Icons.savings_outlined,
  'laptop': Icons.laptop_outlined,
  'phone': Icons.smartphone_outlined,
  'car': Icons.directions_car_outlined,
  'home': Icons.home_outlined,
  'travel': Icons.flight_takeoff_outlined,
  'beach': Icons.beach_access_outlined,
  'gift': Icons.card_giftcard_outlined,
  'education': Icons.school_outlined,
  'health': Icons.favorite_border,
  'ring': Icons.diamond_outlined,
  'bike': Icons.pedal_bike_outlined,
  'game': Icons.sports_esports_outlined,
  'emergency': Icons.shield_outlined,
  'baby': Icons.child_friendly_outlined,
  'pets': Icons.pets_outlined,
};

IconData goalIcon(String key) => goalIcons[key] ?? Icons.savings_outlined;

String _date(DateTime d) => DateFormat('d MMMM y', 'uk').format(d);

void openGoal(BuildContext context, String id) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GoalDetailScreen(goalId: id)));

void openGoalEditor(BuildContext context, {Goal? goal}) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => GoalEditScreen(goal: goal)));

// ---------------- Вкладка «Цілі» ----------------

class GoalsTab extends ConsumerStatefulWidget {
  const GoalsTab({super.key});

  @override
  ConsumerState<GoalsTab> createState() => _GoalsTabState();
}

class _GoalsTabState extends ConsumerState<GoalsTab> {
  bool _showArchive = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = ref.watch(goalProgressProvider).values.toList();
    final active = progress.where((p) => !p.goal.archived).toList()
      ..sort((a, b) {
        // Недосягнуті — зверху, серед них ближчий термін — вище.
        if (a.reached != b.reached) return a.reached ? 1 : -1;
        final da = a.goal.deadline, db = b.goal.deadline;
        if (da != null && db != null) return da.compareTo(db);
        if (da != null) return -1;
        if (db != null) return 1;
        return a.goal.createdAt.compareTo(b.goal.createdAt);
      });
    final archived = progress.where((p) => p.goal.archived).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'goal-fab',
        onPressed: () => openGoalEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Нова ціль'),
      ),
      body: SafeArea(
        child: progress.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'Цілей ще немає.\nНатисни «Нова ціль» — наприклад, «Ноутбук, 1 500 € до березня».\n\n'
                    'Відкладаєш вручну: гроші лишаються в гаманцях, а ціль показує, скільки з них уже «на ноутбук».',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                children: [
                  for (final p in active) GoalCard(progress: p),
                  if (archived.isNotEmpty)
                    TextButton.icon(
                      onPressed: () =>
                          setState(() => _showArchive = !_showArchive),
                      icon: Icon(
                        _showArchive ? Icons.expand_less : Icons.expand_more,
                      ),
                      label: Text('Архів (${archived.length})'),
                    ),
                  if (_showArchive)
                    for (final p in archived)
                      Opacity(opacity: 0.6, child: GoalCard(progress: p)),
                ],
              ),
      ),
    );
  }
}

class GoalCard extends StatelessWidget {
  const GoalCard({super.key, required this.progress});
  final GoalProgress progress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = progress;
    final g = p.goal;
    final now = DateTime.now();
    final color = p.reached ? AppColors.income : scheme.primary;
    final perMonth = p.perMonthCents(now);
    final String status;
    if (p.reached) {
      status = 'Досягнуто!';
    } else if (p.overdue(now)) {
      status =
          'Термін минув ${_date(g.deadline!)} · лишилось ${formatMoney(p.leftCents, g.currency)}';
    } else if (perMonth != null) {
      status =
          'Лишилось ${formatMoney(p.leftCents, g.currency)} · ≈ ${formatMoney(perMonth, g.currency)} на місяць до ${_date(g.deadline!)}';
    } else {
      status = 'Лишилось ${formatMoney(p.leftCents, g.currency)}';
    }
    return Card(
      elevation: 0,
      color: scheme.surfaceContainerHigh,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => openGoal(context, g.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: p.reached
                    ? AppColors.income.withValues(alpha: 0.15)
                    : scheme.primaryContainer,
                child: Icon(
                  p.reached ? Icons.emoji_events_outlined : goalIcon(g.icon),
                  color: p.reached
                      ? AppColors.income
                      : scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            g.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Text(
                          '${(p.share * 100).floor()} %',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: p.share.clamp(0, 1).toDouble(),
                        minHeight: 8,
                        color: color,
                        backgroundColor: scheme.surfaceContainerHighest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${formatMoney(p.savedCents, g.currency)} з ${formatMoney(g.targetCents, g.currency)}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: p.overdue(now)
                            ? AppColors.expense
                            : (p.reached
                                  ? AppColors.income
                                  : scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Картка цілі ----------------

class GoalDetailScreen extends ConsumerWidget {
  const GoalDetailScreen({super.key, required this.goalId});
  final String goalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(goalProgressProvider)[goalId];
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Ціль не знайдено')),
      );
    }
    final g = p.goal;
    final scheme = Theme.of(context).colorScheme;
    final db = ref.read(databaseProvider);
    final history =
        (ref.watch(goalContributionsProvider).value ??
                const <GoalContribution>[])
            .where((c) => c.goalId == goalId)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(g.name),
        actions: [
          IconButton(
            tooltip: 'Редагувати',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => openGoalEditor(context, goal: g),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ще',
            onSelected: (v) async {
              if (v == 'archive') await db.setGoalArchived(g.id, !g.archived);
              if (v == 'delete' && context.mounted) {
                await _delete(context, db, g);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'archive',
                child: Text(g.archived ? 'Повернути з архіву' : 'В архів'),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Видалити ціль'),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            GoalCard(progress: p),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () =>
                        _contribute(context, ref, g, deposit: true),
                    icon: const Icon(Icons.add),
                    label: const Text('Відкласти'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: p.savedCents > 0
                        ? () => _contribute(context, ref, g, deposit: false)
                        : null,
                    icon: const Icon(Icons.remove),
                    label: const Text('Зняти'),
                  ),
                ),
              ],
            ),
            if (p.reached && !g.archived) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => db.setGoalArchived(g.id, true),
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Ціль досягнуто — перенести в архів'),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Гроші лишаються у твоїх гаманцях — внески лише позначають, скільки з них «на ${g.name}».',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Історія', style: Theme.of(context).textTheme.titleSmall),
            if (history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'Внесків ще немає',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ),
              ),
            for (final c in history)
              Dismissible(
                key: ValueKey('goal-c-${c.id}'),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: AppColors.expense,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 24),
                  child: const Icon(Icons.delete_outline, color: Colors.white),
                ),
                onDismissed: (_) async {
                  final messenger = ScaffoldMessenger.of(context);
                  await db.setGoalContributionDeleted(c.id, true);
                  messenger
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      SnackBar(
                        content: const Text('Внесок видалено'),
                        persist: false, // зникає сама, навіть з кнопкою
                        action: SnackBarAction(
                          label: 'Скасувати',
                          onPressed: () =>
                              db.setGoalContributionDeleted(c.id, false),
                        ),
                      ),
                    );
                },
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    c.amountCents >= 0 ? Icons.south_west : Icons.north_east,
                    color: c.amountCents >= 0
                        ? AppColors.income
                        : AppColors.expense,
                  ),
                  title: Text(dayLabel(c.date)),
                  subtitle: c.note == null ? null : Text(c.note!),
                  trailing: Text(
                    formatMoney(
                      c.amountCents,
                      g.currency,
                      sign: c.amountCents >= 0 ? 1 : -1,
                    ),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: c.amountCents >= 0
                          ? AppColors.income
                          : AppColors.expense,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _contribute(
    BuildContext context,
    WidgetRef ref,
    Goal g, {
    required bool deposit,
  }) async {
    final result = await showDialog<(int, String)>(
      context: context,
      builder: (_) => _ContributionDialog(goal: g, deposit: deposit),
    );
    if (result == null) return;
    await ref
        .read(databaseProvider)
        .addGoalContribution(
          goalId: g.id,
          amountCents: deposit ? result.$1 : -result.$1,
          date: DateTime.now(),
          note: result.$2,
        );
  }

  Future<void> _delete(BuildContext context, AppDatabase db, Goal g) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Видалити ціль «${g.name}»?'),
        content: const Text(
          'Гроші в гаманцях не зміняться — зникне лише ціль і її внески.',
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
    final messenger = ScaffoldMessenger.of(context);
    await db.setGoalDeleted(g.id, true);
    if (context.mounted) Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Ціль «${g.name}» видалено'),
        persist: false, // зникає сама, навіть з кнопкою
        action: SnackBarAction(
          label: 'Скасувати',
          onPressed: () => db.setGoalDeleted(g.id, false),
        ),
      ),
    );
  }
}

/// Діалог «Відкласти / Зняти»: сума й коментар. Контролери живуть у State —
/// інакше їх можна знищити під час анімації закриття.
class _ContributionDialog extends StatefulWidget {
  const _ContributionDialog({required this.goal, required this.deposit});
  final Goal goal;
  final bool deposit;

  @override
  State<_ContributionDialog> createState() => _ContributionDialogState();
}

class _ContributionDialogState extends State<_ContributionDialog> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _ok() {
    final cents = parseAmountToCents(_amount.text);
    if (cents == null || cents == 0) {
      setState(() => _error = 'Введи суму');
      return;
    }
    Navigator.pop(context, (cents, _note.text));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.deposit
            ? 'Відкласти на «${widget.goal.name}»'
            : 'Зняти з «${widget.goal.name}»',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
            ],
            decoration: InputDecoration(
              labelText: 'Сума',
              errorText: _error,
              suffixText: currencySymbol(widget.goal.currency),
            ),
            onChanged: (_) => setState(() => _error = null),
            onSubmitted: (_) => _ok(),
          ),
          TextField(
            controller: _note,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Коментар (необов\'язково)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Скасувати'),
        ),
        TextButton(
          onPressed: _ok,
          child: Text(widget.deposit ? 'Відкласти' : 'Зняти'),
        ),
      ],
    );
  }
}

// ---------------- Нова ціль / редагування ----------------

class GoalEditScreen extends ConsumerStatefulWidget {
  const GoalEditScreen({super.key, this.goal});
  final Goal? goal;

  @override
  ConsumerState<GoalEditScreen> createState() => _GoalEditScreenState();
}

class _GoalEditScreenState extends ConsumerState<GoalEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _target;
  late String _icon;
  late String _currency;
  DateTime? _deadline;
  String? _nameError;
  String? _targetError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final g = widget.goal;
    _name = TextEditingController(text: g?.name ?? '');
    _target = TextEditingController(
      text: g == null ? '' : centsToInput(g.targetCents),
    );
    _icon = g?.icon ?? 'savings';
    _currency = g?.currency ?? baseCurrency;
    _deadline = g?.deadline;
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasContributions =
        widget.goal != null &&
        (ref.watch(goalProgressProvider)[widget.goal!.id]?.savedCents ?? 0) !=
            0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.goal == null ? 'Нова ціль' : 'Ціль')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _name,
              autofocus: widget.goal == null,
              maxLength: 40,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'На що збираю',
                hintText: 'Наприклад, Ноутбук або Відпустка',
                errorText: _nameError,
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _nameError = null),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in goalIcons.entries)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => setState(() => _icon = e.key),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: e.key == _icon ? scheme.primaryContainer : null,
                        border: Border.all(
                          color: e.key == _icon
                              ? scheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        e.value,
                        color: e.key == _icon
                            ? scheme.onPrimaryContainer
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _target,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\s]')),
              ],
              style: text.titleLarge,
              decoration: InputDecoration(
                labelText: 'Скільки треба',
                errorText: _targetError,
                suffixText: currencySymbol(_currency),
                border: const OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _targetError = null),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final c in budgetCurrencyOptions(ref, _currency))
                  ChoiceChip(
                    label: Text(c),
                    selected: c == _currency,
                    // Внески записані у валюті цілі — після них валюту не міняємо.
                    onSelected: hasContributions
                        ? null
                        : (_) => setState(() => _currency = c),
                  ),
              ],
            ),
            if (hasContributions)
              Text(
                'Валюту не можна змінити, коли вже є внески',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Термін'),
              subtitle: Text(
                _deadline == null
                    ? 'Без терміну'
                    : 'До ${_date(_deadline!)} — покажу, скільки відкладати щомісяця',
              ),
              value: _deadline != null,
              onChanged: (on) async {
                if (!on) {
                  setState(() => _deadline = null);
                  return;
                }
                await _pickDeadline();
              },
            ),
            if (_deadline != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickDeadline,
                  icon: const Icon(Icons.event_outlined),
                  label: const Text('Змінити дату'),
                ),
              ),
            const SizedBox(height: 16),
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

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _deadline ?? DateTime(now.year, now.month + 6, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 30, 12, 31),
    );
    if (d != null) setState(() => _deadline = d);
  }

  Future<void> _save() async {
    final cents = parseAmountToCents(_target.text);
    setState(() {
      _nameError = _name.text.trim().isEmpty ? 'Введи, на що збираєш' : null;
      _targetError = (cents == null || cents == 0)
          ? 'Введи суму, напр. 1500'
          : null;
    });
    if (_nameError != null || _targetError != null) return;
    setState(() => _saving = true);
    await ref
        .read(databaseProvider)
        .saveGoal(
          id: widget.goal?.id,
          name: _name.text,
          icon: _icon,
          targetCents: cents!,
          currency: _currency,
          deadline: _deadline,
        );
    if (mounted) Navigator.of(context).pop();
  }
}
