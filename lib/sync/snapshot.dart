import 'dart:convert';

import 'package:drift/drift.dart';

import '../data/database.dart';

/// Вміст файлу `finance.json` на Google Drive.
///
/// Записи впорядковані за id, тому однакові дані завжди дають однаковий текст —
/// так легко зрозуміти, чи є що вивантажувати.
class FinanceSnapshot {
  const FinanceSnapshot({
    required this.transactions,
    required this.categories,
    required this.settings,
    this.wallets = const [],
    this.walletCurrencies = const [],
    this.transfers = const [],
    this.assets = const [],
    this.trades = const [],
    this.belongings = const [],
    this.budgets = const [],
    this.templates = const [],
    this.goals = const [],
    this.goalContributions = const [],
    this.activityCategories = const [],
    this.activities = const [],
    this.todos = const [],
    this.todoCompletions = const [],
  });

  static const formatName = 'mymanager-finance';

  /// 2 — етап 7: гаманці, валюти гаманців, перекази.
  /// 3 — етап 8: активи й операції з ними.
  /// 4 — етап 9: пасиви (речі).
  /// 5 — етап 11: бюджети.
  /// 6 — етап 12: шаблони й регулярні платежі.
  /// 7 — 1.15: цілі накопичення.
  /// 8 — етап 14: Activity.
  /// 9 — етап 16: To-Do.
  /// 10 — етап 17: повторення справ і ключові дати.
  /// 11 — етап 19: нагадування справ.
  /// 12 — етап 20: «не виконано». Старіші файли теж читаються.
  static const formatVersion = 14;

  final List<MoneyEntry> transactions;
  final List<Category> categories;
  final List<Setting> settings;
  final List<Wallet> wallets;
  final List<WalletCurrency> walletCurrencies;
  final List<Transfer> transfers;
  final List<Asset> assets;
  final List<AssetTrade> trades;
  final List<Belonging> belongings;
  final List<Budget> budgets;
  final List<EntryTemplate> templates;
  final List<Goal> goals;
  final List<GoalContribution> goalContributions;
  final List<ActivityCategory> activityCategories;
  final List<Activity> activities;
  final List<Todo> todos;
  final List<TodoCompletion> todoCompletions;

  /// Мітка повного видалення даних (див. [SettingKeys.dataResetId]).
  Setting? get resetMarker {
    for (final s in settings) {
      if (s.key == SettingKeys.dataResetId) return s;
    }
    return null;
  }

  String encode() {
    final json = {
      'format': formatName,
      'version': formatVersion,
      'transactions': [
        for (final t in _byId(transactions, (t) => t.id)) _txToJson(t),
      ],
      'categories': [
        for (final c in _byId(categories, (c) => c.id)) _catToJson(c),
      ],
      'settings': [
        for (final s in _byId(settings, (s) => s.key)) _setToJson(s),
      ],
      'wallets': [
        for (final w in _byId(wallets, (w) => w.id)) _walletToJson(w),
      ],
      'walletCurrencies': [
        for (final c in _byId(walletCurrencies, (c) => c.id)) _wcToJson(c),
      ],
      'transfers': [
        for (final t in _byId(transfers, (t) => t.id)) _transferToJson(t),
      ],
      'assets': [for (final a in _byId(assets, (a) => a.id)) _assetToJson(a)],
      'trades': [for (final t in _byId(trades, (t) => t.id)) _tradeToJson(t)],
      'belongings': [
        for (final b in _byId(belongings, (b) => b.id)) _belongingToJson(b),
      ],
      'budgets': [
        for (final b in _byId(budgets, (b) => b.id)) _budgetToJson(b),
      ],
      'templates': [
        for (final t in _byId(templates, (t) => t.id)) _templateToJson(t),
      ],
      'goals': [for (final g in _byId(goals, (g) => g.id)) _goalToJson(g)],
      'goalContributions': [
        for (final c in _byId(goalContributions, (c) => c.id))
          _contribToJson(c),
      ],
      'activityCategories': [
        for (final c in _byId(activityCategories, (c) => c.id))
          _actCatToJson(c),
      ],
      'activities': [
        for (final a in _byId(activities, (a) => a.id)) _activityToJson(a),
      ],
      'todos': [for (final t in _byId(todos, (t) => t.id)) _todoToJson(t)],
      'todoCompletions': [
        for (final c in _byId(todoCompletions, (c) => c.id))
          _completionToJson(c),
      ],
    };
    return const JsonEncoder.withIndent(' ').convert(json);
  }

  /// Розбирає файл з Drive. Кидає [FormatException], якщо файл не наш або пошкоджений.
  static FinanceSnapshot decode(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } on FormatException {
      throw const FormatException('Файл синхронізації пошкоджений');
    }
    if (raw is! Map<String, dynamic> || raw['format'] != formatName) {
      throw const FormatException('Це не файл MyManager');
    }
    final version = raw['version'];
    if (version is! int || version > formatVersion) {
      throw const FormatException(
        'Файл створено новішою версією MyManager — онови додаток',
      );
    }
    try {
      return FinanceSnapshot(
        transactions: [
          for (final j in raw['transactions'] as List) _txFromJson(j as Map),
        ],
        categories: [
          for (final j in raw['categories'] as List) _catFromJson(j as Map),
        ],
        settings: [
          for (final j in raw['settings'] as List) _setFromJson(j as Map),
        ],
        wallets: [
          for (final j in (raw['wallets'] as List?) ?? [])
            _walletFromJson(j as Map),
        ],
        walletCurrencies: [
          for (final j in (raw['walletCurrencies'] as List?) ?? [])
            _wcFromJson(j as Map),
        ],
        transfers: [
          for (final j in (raw['transfers'] as List?) ?? [])
            _transferFromJson(j as Map),
        ],
        assets: [
          for (final j in (raw['assets'] as List?) ?? [])
            _assetFromJson(j as Map),
        ],
        trades: [
          for (final j in (raw['trades'] as List?) ?? [])
            _tradeFromJson(j as Map),
        ],
        belongings: [
          for (final j in (raw['belongings'] as List?) ?? [])
            _belongingFromJson(j as Map),
        ],
        budgets: [
          for (final j in (raw['budgets'] as List?) ?? [])
            _budgetFromJson(j as Map),
        ],
        templates: [
          for (final j in (raw['templates'] as List?) ?? [])
            _templateFromJson(j as Map),
        ],
        goals: [
          for (final j in (raw['goals'] as List?) ?? [])
            _goalFromJson(j as Map),
        ],
        goalContributions: [
          for (final j in (raw['goalContributions'] as List?) ?? [])
            _contribFromJson(j as Map),
        ],
        activityCategories: [
          for (final j in (raw['activityCategories'] as List?) ?? [])
            _actCatFromJson(j as Map),
        ],
        activities: [
          for (final j in (raw['activities'] as List?) ?? [])
            _activityFromJson(j as Map),
        ],
        todos: [
          for (final j in (raw['todos'] as List?) ?? [])
            _todoFromJson(j as Map),
        ],
        todoCompletions: [
          for (final j in (raw['todoCompletions'] as List?) ?? [])
            _completionFromJson(j as Map),
        ],
      );
    } catch (_) {
      throw const FormatException('Файл синхронізації пошкоджений');
    }
  }

  static List<T> _byId<T>(List<T> list, String Function(T) id) =>
      [...list]..sort((a, b) => id(a).compareTo(id(b)));
}

// ---------- JSON ----------

String _day(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parseDay(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime(p[0], p[1], p[2]);
}

String _ts(DateTime d) => d.toUtc().toIso8601String();
DateTime _parseTs(Object? s) => DateTime.parse(s as String).toUtc();

Map<String, Object?> _txToJson(MoneyEntry t) => {
  'id': t.id,
  'type': t.type.name,
  'amountCents': t.amountCents,
  'currency': t.currency,
  'categoryId': t.categoryId,
  'date': _day(t.date),
  'note': t.note,
  'createdAt': _ts(t.createdAt),
  'updatedAt': _ts(t.updatedAt),
  'deleted': t.deleted,
  'walletId': t.walletId,
  'assetId': t.assetId,
  'assetUnits': t.assetUnits,
  'tradeId': t.tradeId,
  'belongingId': t.belongingId,
};

MoneyEntry _txFromJson(Map j) => MoneyEntry(
  walletId: (j['walletId'] as String?) ?? AppDatabase.mainWalletId,
  assetId: j['assetId'] as String?,
  assetUnits: j['assetUnits'] as int?,
  tradeId: j['tradeId'] as String?,
  belongingId: j['belongingId'] as String?,
  id: j['id'] as String,
  type: EntryType.values.byName(j['type'] as String),
  amountCents: j['amountCents'] as int,
  currency: j['currency'] as String,
  categoryId: j['categoryId'] as String,
  date: _parseDay(j['date'] as String),
  note: j['note'] as String?,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _catToJson(Category c) => {
  'id': c.id,
  'type': c.type.name,
  'name': c.name,
  'icon': c.icon,
  'color': c.color,
  'sortOrder': c.sortOrder,
  'hidden': c.hidden,
  'updatedAt': _ts(c.updatedAt),
  'deleted': c.deleted,
};

Category _catFromJson(Map j) => Category(
  id: j['id'] as String,
  type: EntryType.values.byName(j['type'] as String),
  name: j['name'] as String,
  icon: j['icon'] as String,
  color: j['color'] as int,
  sortOrder: j['sortOrder'] as int,
  hidden: j['hidden'] as bool,
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _setToJson(Setting s) => {
  'key': s.key,
  'value': s.value,
  'updatedAt': _ts(s.updatedAt),
};

Setting _setFromJson(Map j) => Setting(
  key: j['key'] as String,
  value: j['value'] as String,
  updatedAt: _parseTs(j['updatedAt']),
);

Map<String, Object?> _walletToJson(Wallet w) => {
  'id': w.id,
  'name': w.name,
  'icon': w.icon,
  'color': w.color,
  'sortOrder': w.sortOrder,
  'archived': w.archived,
  'updatedAt': _ts(w.updatedAt),
  'deleted': w.deleted,
};

Wallet _walletFromJson(Map j) => Wallet(
  id: j['id'] as String,
  name: j['name'] as String,
  icon: j['icon'] as String,
  color: j['color'] as int,
  sortOrder: j['sortOrder'] as int,
  archived: j['archived'] as bool,
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _wcToJson(WalletCurrency c) => {
  'id': c.id,
  'walletId': c.walletId,
  'currency': c.currency,
  'initialCents': c.initialCents,
  'updatedAt': _ts(c.updatedAt),
  'deleted': c.deleted,
};

WalletCurrency _wcFromJson(Map j) => WalletCurrency(
  id: j['id'] as String,
  walletId: j['walletId'] as String,
  currency: j['currency'] as String,
  initialCents: j['initialCents'] as int,
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _transferToJson(Transfer t) => {
  'id': t.id,
  'fromWalletId': t.fromWalletId,
  'fromCurrency': t.fromCurrency,
  'fromAmountCents': t.fromAmountCents,
  'toWalletId': t.toWalletId,
  'toCurrency': t.toCurrency,
  'toAmountCents': t.toAmountCents,
  'date': _day(t.date),
  'note': t.note,
  'createdAt': _ts(t.createdAt),
  'updatedAt': _ts(t.updatedAt),
  'deleted': t.deleted,
};

Transfer _transferFromJson(Map j) => Transfer(
  id: j['id'] as String,
  fromWalletId: j['fromWalletId'] as String,
  fromCurrency: j['fromCurrency'] as String,
  fromAmountCents: j['fromAmountCents'] as int,
  toWalletId: j['toWalletId'] as String,
  toCurrency: j['toCurrency'] as String,
  toAmountCents: j['toAmountCents'] as int,
  date: _parseDay(j['date'] as String),
  note: j['note'] as String?,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _assetToJson(Asset a) => {
  'id': a.id,
  'code': a.code,
  'name': a.name,
  'kind': a.kind.name,
  'basisCurrency': a.basisCurrency,
  'updatedAt': _ts(a.updatedAt),
  'deleted': a.deleted,
};

Asset _assetFromJson(Map j) => Asset(
  id: j['id'] as String,
  code: j['code'] as String,
  name: j['name'] as String,
  kind: AssetKind.values.byName(j['kind'] as String),
  basisCurrency: j['basisCurrency'] as String,
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _tradeToJson(AssetTrade t) => {
  'id': t.id,
  'type': t.type.name,
  'assetId': t.assetId,
  'units': t.units,
  'walletId': t.walletId,
  'toWalletId': t.toWalletId,
  'fiatWalletId': t.fiatWalletId,
  'fiatCurrency': t.fiatCurrency,
  'fiatCents': t.fiatCents,
  'basisCents': t.basisCents,
  'date': _day(t.date),
  'note': t.note,
  'createdAt': _ts(t.createdAt),
  'updatedAt': _ts(t.updatedAt),
  'deleted': t.deleted,
};

AssetTrade _tradeFromJson(Map j) => AssetTrade(
  id: j['id'] as String,
  type: TradeType.values.byName(j['type'] as String),
  assetId: j['assetId'] as String,
  units: j['units'] as int,
  walletId: j['walletId'] as String,
  toWalletId: j['toWalletId'] as String?,
  fiatWalletId: j['fiatWalletId'] as String?,
  fiatCurrency: j['fiatCurrency'] as String?,
  fiatCents: j['fiatCents'] as int?,
  basisCents: j['basisCents'] as int,
  date: _parseDay(j['date'] as String),
  note: j['note'] as String?,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _belongingToJson(Belonging b) => {
  'id': b.id,
  'name': b.name,
  'icon': b.icon,
  'priceCents': b.priceCents,
  'currency': b.currency,
  'purchaseDate': _day(b.purchaseDate),
  'walletId': b.walletId,
  'categoryId': b.categoryId,
  'recordExpense': b.recordExpense,
  'note': b.note,
  'saleCents': b.saleCents,
  'saleCurrency': b.saleCurrency,
  'saleDate': b.saleDate == null ? null : _day(b.saleDate!),
  'saleWalletId': b.saleWalletId,
  'createdAt': _ts(b.createdAt),
  'updatedAt': _ts(b.updatedAt),
  'deleted': b.deleted,
};

Belonging _belongingFromJson(Map j) => Belonging(
  id: j['id'] as String,
  name: j['name'] as String,
  icon: j['icon'] as String,
  priceCents: j['priceCents'] as int,
  currency: j['currency'] as String,
  purchaseDate: _parseDay(j['purchaseDate'] as String),
  walletId: j['walletId'] as String,
  categoryId: j['categoryId'] as String,
  recordExpense: j['recordExpense'] as bool,
  note: j['note'] as String?,
  saleCents: j['saleCents'] as int?,
  saleCurrency: j['saleCurrency'] as String?,
  saleDate: j['saleDate'] == null ? null : _parseDay(j['saleDate'] as String),
  saleWalletId: j['saleWalletId'] as String?,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _budgetToJson(Budget b) => {
  'id': b.id,
  'categoryId': b.categoryId,
  'limitCents': b.limitCents,
  'currency': b.currency,
  'updatedAt': _ts(b.updatedAt),
  'deleted': b.deleted,
};

Budget _budgetFromJson(Map j) => Budget(
  id: j['id'] as String,
  categoryId: j['categoryId'] as String?,
  limitCents: j['limitCents'] as int,
  currency: j['currency'] as String,
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _templateToJson(EntryTemplate t) => {
  'id': t.id,
  'type': t.type.name,
  'name': t.name,
  'amountCents': t.amountCents,
  'currency': t.currency,
  'categoryId': t.categoryId,
  'walletId': t.walletId,
  'note': t.note,
  'repeat': t.repeat.name,
  'startDate': t.startDate == null ? null : _day(t.startDate!),
  'createdAt': _ts(t.createdAt),
  'updatedAt': _ts(t.updatedAt),
  'deleted': t.deleted,
};

EntryTemplate _templateFromJson(Map j) => EntryTemplate(
  id: j['id'] as String,
  type: EntryType.values.byName(j['type'] as String),
  name: j['name'] as String,
  amountCents: j['amountCents'] as int,
  currency: j['currency'] as String,
  categoryId: j['categoryId'] as String,
  walletId: j['walletId'] as String,
  note: j['note'] as String?,
  repeat: RepeatKind.values.byName(j['repeat'] as String),
  startDate: j['startDate'] == null
      ? null
      : _parseDay(j['startDate'] as String),
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _goalToJson(Goal g) => {
  'id': g.id,
  'name': g.name,
  'icon': g.icon,
  'targetCents': g.targetCents,
  'currency': g.currency,
  'deadline': g.deadline == null ? null : _day(g.deadline!),
  'archived': g.archived,
  'createdAt': _ts(g.createdAt),
  'updatedAt': _ts(g.updatedAt),
  'deleted': g.deleted,
};

Goal _goalFromJson(Map j) => Goal(
  id: j['id'] as String,
  name: j['name'] as String,
  icon: j['icon'] as String,
  targetCents: j['targetCents'] as int,
  currency: j['currency'] as String,
  deadline: j['deadline'] == null ? null : _parseDay(j['deadline'] as String),
  archived: j['archived'] as bool,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _contribToJson(GoalContribution c) => {
  'id': c.id,
  'goalId': c.goalId,
  'amountCents': c.amountCents,
  'date': _day(c.date),
  'note': c.note,
  'createdAt': _ts(c.createdAt),
  'updatedAt': _ts(c.updatedAt),
  'deleted': c.deleted,
};

GoalContribution _contribFromJson(Map j) => GoalContribution(
  id: j['id'] as String,
  goalId: j['goalId'] as String,
  amountCents: j['amountCents'] as int,
  date: _parseDay(j['date'] as String),
  note: j['note'] as String?,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _actCatToJson(ActivityCategory c) => {
  'id': c.id,
  'name': c.name,
  'icon': c.icon,
  'color': c.color,
  'kind': c.kind.name,
  'sortOrder': c.sortOrder,
  'hidden': c.hidden,
  'updatedAt': _ts(c.updatedAt),
  'deleted': c.deleted,
};

ActivityCategory _actCatFromJson(Map j) => ActivityCategory(
  id: j['id'] as String,
  name: j['name'] as String,
  icon: j['icon'] as String,
  color: j['color'] as int,
  kind: ActivityKind.values.byName(j['kind'] as String),
  sortOrder: j['sortOrder'] as int,
  hidden: j['hidden'] as bool,
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

/// Час активності — точний момент (UTC у файлі, місцевий у додатку).
Map<String, Object?> _activityToJson(Activity a) => {
  'id': a.id,
  'categoryId': a.categoryId,
  'start': _ts(a.start),
  'end': a.end == null ? null : _ts(a.end!),
  'note': a.note,
  'createdAt': _ts(a.createdAt),
  'updatedAt': _ts(a.updatedAt),
  'deleted': a.deleted,
};

Activity _activityFromJson(Map j) => Activity(
  id: j['id'] as String,
  categoryId: j['categoryId'] as String,
  start: _parseTs(j['start']).toLocal(),
  end: j['end'] == null ? null : _parseTs(j['end']).toLocal(),
  note: j['note'] as String?,
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
);

Map<String, Object?> _todoToJson(Todo t) => {
  'id': t.id,
  'title': t.title,
  'note': t.note,
  'dueDate': t.dueDate == null ? null : _day(t.dueDate!),
  'dueMinutes': t.dueMinutes,
  'done': t.done,
  'doneAt': t.doneAt == null ? null : _ts(t.doneAt!),
  'createdAt': _ts(t.createdAt),
  'updatedAt': _ts(t.updatedAt),
  'deleted': t.deleted,
  'repeatUnit': t.repeatUnit.name,
  'repeatEvery': t.repeatEvery,
  'repeatWeekdays': t.repeatWeekdays,
  'repeatUntil': t.repeatUntil == null ? null : _day(t.repeatUntil!),
  'keyType': t.keyType,
  'countYears': t.countYears,
  'remindDays': t.remindDays,
  'remindBefore': t.remindBefore,
  'priority': t.priority,
  'failed': t.failed,
};

Map<String, Object?> _completionToJson(TodoCompletion c) => {
  'id': c.id,
  'todoId': c.todoId,
  'date': _day(c.date),
  'doneAt': _ts(c.doneAt),
  'updatedAt': _ts(c.updatedAt),
  'deleted': c.deleted,
  'failed': c.failed,
  'auto': c.isAuto,
};

TodoCompletion _completionFromJson(Map j) => TodoCompletion(
  id: j['id'] as String,
  todoId: j['todoId'] as String,
  date: _parseDay(j['date'] as String),
  doneAt: _parseTs(j['doneAt']).toLocal(),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
  failed: (j['failed'] as bool?) ?? false,
  isAuto: (j['auto'] as bool?) ?? false,
);

Todo _todoFromJson(Map j) => Todo(
  id: j['id'] as String,
  title: j['title'] as String,
  note: j['note'] as String?,
  dueDate: j['dueDate'] == null ? null : _parseDay(j['dueDate'] as String),
  dueMinutes: j['dueMinutes'] as int?,
  done: j['done'] as bool,
  doneAt: j['doneAt'] == null ? null : _parseTs(j['doneAt']).toLocal(),
  createdAt: _parseTs(j['createdAt']),
  updatedAt: _parseTs(j['updatedAt']),
  deleted: j['deleted'] as bool,
  // Файли етапу 16 цих полів не мають.
  repeatUnit: TodoRepeat.values.byName((j['repeatUnit'] as String?) ?? 'none'),
  repeatEvery: (j['repeatEvery'] as int?) ?? 1,
  repeatWeekdays: j['repeatWeekdays'] as String?,
  repeatUntil: j['repeatUntil'] == null
      ? null
      : _parseDay(j['repeatUntil'] as String),
  keyType: j['keyType'] as String?,
  countYears: (j['countYears'] as bool?) ?? false,
  remindDays: (j['remindDays'] as int?) ?? 0,
  remindBefore: (j['remindBefore'] as int?) ?? 0,
  priority: (j['priority'] as int?) ?? TodoPriority.should,
  failed: (j['failed'] as bool?) ?? false,
);

// ---------- База ↔ знімок ----------

/// Скільки рядків прийшло з Drive під час злиття.
class MergeResult {
  const MergeResult(
    this.transactions,
    this.categories,
    this.settings, [
    this.other = 0,
  ]);
  final int transactions;
  final int categories;
  final int settings;

  /// Гаманці, їхні валюти й перекази.
  final int other;
  int get total => transactions + categories + settings + other;
}

extension SnapshotDb on AppDatabase {
  /// Усі дані для синхронізації, включно з позначками видалення.
  Future<FinanceSnapshot> exportSnapshot() async {
    return FinanceSnapshot(
      transactions: await select(transactions).get(),
      categories: await select(categories).get(),
      settings: await (select(
        settings,
      )..where((s) => s.key.like('${AppDatabase.localPrefix}%').not())).get(),
      wallets: await select(wallets).get(),
      walletCurrencies: await select(walletCurrencies).get(),
      transfers: await select(transfers).get(),
      assets: await select(assets).get(),
      trades: await select(assetTrades).get(),
      belongings: await select(belongings).get(),
      budgets: await select(budgets).get(),
      templates: await select(templates).get(),
      goals: await select(goals).get(),
      goalContributions: await select(goalContributions).get(),
      activityCategories: await select(activityCategories).get(),
      activities: await select(activities).get(),
      todos: await select(todos).get(),
      todoCompletions: await select(todoCompletions).get(),
    );
  }

  /// Зливає дані з Drive у локальну базу: для кожного запису перемагає версія
  /// з пізнішим `updatedAt`. Повторне злиття того самого знімка нічого не змінює.
  Future<MergeResult> mergeSnapshot(FinanceSnapshot remote) {
    return transaction(() async {
      final localTx = {
        for (final t in await select(transactions).get()) t.id: t,
      };
      final localCat = {
        for (final c in await select(categories).get()) c.id: c,
      };
      final localSet = {for (final s in await select(settings).get()) s.key: s};
      final localW = {for (final w in await select(wallets).get()) w.id: w};
      final localWc = {
        for (final c in await select(walletCurrencies).get()) c.id: c,
      };
      final localTr = {for (final t in await select(transfers).get()) t.id: t};
      var other = 0;
      for (final r in remote.wallets) {
        final l = localW[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(wallets).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      for (final r in remote.walletCurrencies) {
        final l = localWc[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(walletCurrencies)
              .insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      for (final r in remote.transfers) {
        final l = localTr[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(transfers).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localA = {for (final a in await select(assets).get()) a.id: a};
      for (final r in remote.assets) {
        final l = localA[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(assets).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localT = {for (final t in await select(assetTrades).get()) t.id: t};
      for (final r in remote.trades) {
        final l = localT[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(assetTrades).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localTc = {
        for (final c in await select(todoCompletions).get()) c.id: c,
      };
      for (final r in remote.todoCompletions) {
        final l = localTc[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(todoCompletions)
              .insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localTd = {for (final t in await select(todos).get()) t.id: t};
      for (final r in remote.todos) {
        final l = localTd[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(todos).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localAc = {
        for (final c in await select(activityCategories).get()) c.id: c,
      };
      for (final r in remote.activityCategories) {
        final l = localAc[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(activityCategories)
              .insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localAct = {
        for (final a in await select(activities).get()) a.id: a,
      };
      for (final r in remote.activities) {
        final l = localAct[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(activities).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localGo = {for (final g in await select(goals).get()) g.id: g};
      for (final r in remote.goals) {
        final l = localGo[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(goals).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localGc = {
        for (final c in await select(goalContributions).get()) c.id: c,
      };
      for (final r in remote.goalContributions) {
        final l = localGc[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(goalContributions)
              .insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localTe = {for (final t in await select(templates).get()) t.id: t};
      for (final r in remote.templates) {
        final l = localTe[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(templates).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localBu = {for (final b in await select(budgets).get()) b.id: b};
      for (final r in remote.budgets) {
        final l = localBu[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(budgets).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }
      final localB = {for (final b in await select(belongings).get()) b.id: b};
      for (final r in remote.belongings) {
        final l = localB[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(belongings).insertOnConflictUpdate(r.toCompanion(false));
          other++;
        }
      }

      var tx = 0, cat = 0, set = 0;
      for (final r in remote.transactions) {
        final l = localTx[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(transactions).insertOnConflictUpdate(r.toCompanion(false));
          tx++;
        }
      }
      for (final r in remote.categories) {
        final l = localCat[r.id];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(categories).insertOnConflictUpdate(r.toCompanion(false));
          cat++;
        }
      }
      for (final r in remote.settings) {
        if (r.key.startsWith(AppDatabase.localPrefix)) continue;
        final l = localSet[r.key];
        if (l == null || r.updatedAt.isAfter(l.updatedAt)) {
          await into(settings).insertOnConflictUpdate(r.toCompanion(false));
          set++;
        }
      }
      return MergeResult(tx, cat, set, other);
    });
  }
}
