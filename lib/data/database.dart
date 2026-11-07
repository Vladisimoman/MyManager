import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'default_categories.dart';

part 'database.g.dart';

enum EntryType { income, expense }

/// Надходження й витрати. Кожен запис має UUID, час останньої зміни
/// та позначку видалення — це потрібно для синхронізації (етап 5).
@DataClassName('MoneyEntry')
class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EntryType>()();
  IntColumn get amountCents =>
      integer()(); // сума в оригінальній валюті, у центах
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get categoryId => text()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Гаманець, з якого витрата / куди надходження (етап 7).
  TextColumn get walletId =>
      text().withDefault(const Constant(AppDatabase.mainWalletId))();

  /// Витрата активом (етап 8): що й скільки списано з гаманця.
  /// Сума запису ([amountCents]) — ціна купівлі цієї кількості, в обліковій валюті активу.
  TextColumn get assetId => text().nullable()();
  IntColumn get assetUnits => integer().nullable()(); // кількість × 10^8

  /// Запис створено автоматично операцією з активом (прибуток / збиток від продажу).
  TextColumn get tradeId => text().nullable()();

  /// Запис купівлі / продажу речі (етап 9).
  TextColumn get belongingId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('Category')
class Categories extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EntryType>()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer()();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Налаштування у форматі ключ — значення.
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Кеш курсів: скільки одиниць валюти за 1 EUR. Без інтернету
/// використовується останній збережений курс.
class ExchangeRates extends Table {
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  RealColumn get perEur => real()();
  TextColumn get rateDate => text()(); // дата курсу від банку, YYYY-MM-DD
  TextColumn get source => text()(); // 'ECB' або 'NBU'
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {currency};
}

/// Курси за минулі дні (етап 10): щоб записи перераховувались за курсом дати
/// запису, а не сьогоднішнім. Лише кеш цього пристрою — не синхронізується,
/// за потреби завантажується знову.
@DataClassName('HistoricalRate')
class HistoricalRates extends Table {
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get day => text()(); // YYYY-MM-DD
  RealColumn get perEur => real()();
  TextColumn get source => text()(); // 'ECB' або 'NBU'

  @override
  Set<Column> get primaryKey => {currency, day};
}

/// Справа To-Do (етап 16). [dueDate] == null — без дати;
/// [dueMinutes] — час (хвилин від півночі), необов'язково.
@DataClassName('Todo')
class Todos extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get dueMinutes => integer().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  DateTimeColumn get doneAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Повторення (етап 17): кожні [repeatEvery] днів / тижнів / місяців / років
  /// від [dueDate]; для тижнів — у дні [repeatWeekdays] («1,3,5», пн = 1).
  TextColumn get repeatUnit =>
      textEnum<TodoRepeat>().withDefault(Constant(TodoRepeat.none.name))();
  IntColumn get repeatEvery => integer().withDefault(const Constant(1))();
  TextColumn get repeatWeekdays => text().nullable()();
  DateTimeColumn get repeatUntil => dateTime().nullable()();

  /// Ключова дата (день народження, річниця…): не null — це не справа, а подія
  /// щороку в день [dueDate]. [countYears] — показувати «виповнюється N».
  TextColumn get keyType => text().nullable()();
  BoolColumn get countYears => boolean().withDefault(const Constant(false))();

  /// За скільки днів до ключової дати показувати її в «Сьогодні».
  IntColumn get remindDays => integer().withDefault(const Constant(0))();

  /// Сповіщення (етап 19): за скільки хвилин до [dueMinutes] нагадати;
  /// 0 — вчасно, [noReminder] — не нагадувати.
  IntColumn get remindBefore => integer().withDefault(const Constant(0))();

  /// Етап 20: справу закрито як «не виконано» ([doneAt] — коли закрито).
  BoolColumn get failed => boolean().withDefault(const Constant(false))();

  /// Етап 26: важливість — [TodoPriority].
  IntColumn get priority =>
      integer().withDefault(const Constant(TodoPriority.should))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Важливість справи (етап 26). Менше число — важливіше (так і сортується).
abstract final class TodoPriority {
  static const must = 0; // обов'язково
  static const should = 1; // бажано
  static const could = 2; // як вийде
  static const all = [must, should, could];
}

enum TodoRepeat { none, day, week, month, year }

/// Виконання одного повтору повторюваної справи (етап 17).
/// id = «todoId:YYYY-MM-DD» — однаковий на всіх пристроях.
@DataClassName('TodoCompletion')
class TodoCompletions extends Table {
  TextColumn get id => text()();
  TextColumn get todoId => text()();
  DateTimeColumn get date => dateTime()();
  DateTimeColumn get doneAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  /// Етап 20: повтор закрито як «не виконано».
  BoolColumn get failed => boolean().withDefault(const Constant(false))();

  /// Етап 25: «не виконано» записано автоматично — день минув без позначки.
  BoolColumn get isAuto => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Наскільки корисна активність (етап 14): для оцінки продуктивності.
enum ActivityKind { useful, neutral, waste }

/// Категорія активності (етап 14): Сон, Сніданок, Робота, YouTube…
@DataClassName('ActivityCategory')
class ActivityCategories extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  TextColumn get kind => textEnum<ActivityKind>()();
  IntColumn get sortOrder => integer()();
  BoolColumn get hidden => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Активність (етап 14): що робив і з котрої до котрої.
/// [end] == null — запущений таймер (триває зараз).
@DataClassName('Activity')
class Activities extends Table {
  TextColumn get id => text()();
  TextColumn get categoryId => text()();
  DateTimeColumn get start => dateTime()();
  DateTimeColumn get end => dateTime().nullable()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Ціль накопичення (після етапу 13): «Ноутбук — 1 500 € до 1 березня».
/// Скільки зібрано — сума внесків [GoalContributions]; гроші лишаються в гаманцях.
@DataClassName('Goal')
class Goals extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get targetCents => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get deadline => dateTime().nullable()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Внесок у ціль (+ відклав, − зняв) у валюті цілі.
@DataClassName('GoalContribution')
class GoalContributions extends Table {
  TextColumn get id => text()();
  TextColumn get goalId => text()();
  IntColumn get amountCents => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Як часто повторюється регулярний платіж (етап 12).
enum RepeatKind { none, weekly, monthly, yearly }

/// Шаблон запису (етап 12): «Кава 3,50 € з картки». З [repeat] != none —
/// регулярний платіж: у день платежу додаток пропонує його записати.
@DataClassName('EntryTemplate')
class Templates extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<EntryType>()();
  TextColumn get name => text()();
  IntColumn get amountCents => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  TextColumn get categoryId => text()();
  TextColumn get walletId => text()();
  TextColumn get note => text().nullable()();
  TextColumn get repeat =>
      textEnum<RepeatKind>().withDefault(Constant(RepeatKind.none.name))();

  /// Перший платіж; далі — кожен тиждень / місяць / рік від цієї дати.
  DateTimeColumn get startDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Бюджет на місяць (етап 11): ліміт витрат для категорії або загальний.
/// id — сталий ('total' або id категорії), тож один бюджет на категорію на всіх пристроях.
@DataClassName('Budget')
class Budgets extends Table {
  TextColumn get id => text()();

  /// null — загальний бюджет на всі витрати.
  TextColumn get categoryId => text().nullable()();
  IntColumn get limitCents => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Гаманці: готівка, картки, рахунки (етап 7).
@DataClassName('Wallet')
class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get color => integer()();
  IntColumn get sortOrder => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Валюти, які тримає гаманець, і їхній початковий баланс.
/// id = `<walletId>:<валюта>` — однаковий на всіх пристроях.
@DataClassName('WalletCurrency')
class WalletCurrencies extends Table {
  TextColumn get id => text()();
  TextColumn get walletId => text()();
  TextColumn get currency => text()();
  IntColumn get initialCents => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Перекази між гаманцями (і обмін валют). Не є ні витратою, ні надходженням.
@DataClassName('Transfer')
class Transfers extends Table {
  TextColumn get id => text()();
  TextColumn get fromWalletId => text()();
  TextColumn get fromCurrency => text()();
  IntColumn get fromAmountCents => integer()();
  TextColumn get toWalletId => text()();
  TextColumn get toCurrency => text()();
  IntColumn get toAmountCents => integer()();
  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

enum AssetKind { crypto, stock, other }

/// Активи: криптовалюти, акції тощо (етап 8). Не входять у загальний баланс.
@DataClassName('Asset')
class Assets extends Table {
  TextColumn get id => text()();
  TextColumn get code => text()(); // BTC, ETH, AAPL…
  TextColumn get name => text()();
  TextColumn get kind => textEnum<AssetKind>()();

  /// Валюта, у якій ведеться ціна купівлі (зазвичай валюта першої купівлі).
  TextColumn get basisCurrency => text()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

enum TradeType { buy, sell, move }

/// Операції з активами: купівля (гроші → актив), продаж (актив → гроші),
/// переказ активу між гаманцями.
@DataClassName('AssetTrade')
class AssetTrades extends Table {
  TextColumn get id => text()();
  TextColumn get type => textEnum<TradeType>()();
  TextColumn get assetId => text()();
  IntColumn get units => integer()(); // кількість × 10^8

  /// Гаманець, де лежить актив: купівля — куди, продаж і переказ — звідки.
  TextColumn get walletId => text()();

  /// Переказ: куди.
  TextColumn get toWalletId => text().nullable()();

  /// Гроші: купівля — звідки й скільки сплачено, продаж — куди й скільки отримано.
  TextColumn get fiatWalletId => text().nullable()();
  TextColumn get fiatCurrency => text().nullable()();
  IntColumn get fiatCents => integer().nullable()();

  /// Ціна купівлі в обліковій валюті активу: купівля — скільки додалось,
  /// продаж — скільки списалось (за середньою ціною на момент продажу).
  IntColumn get basisCents => integer().withDefault(const Constant(0))();

  DateTimeColumn get date => dateTime()();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Кількість активу зберігається цілим числом з 8 знаками після коми.
const unitsScale = 100000000;

class SettingKeys {
  /// До етапу 7 — загальний початковий баланс (тепер — у валютах гаманців).
  static const legacyInitialBalanceCents = 'initial_balance_cents';

  /// Мітка «дані повністю видалено»: інші пристрої, побачивши нову, теж очищаються.
  static const dataResetId = 'data_reset_id';
}

/// Річ, якою володієш (пасив, етап 9): купівля — витрата, продаж — надходження.
/// Ціна купівлі лише довідкова: у загальний баланс речі не входять.
@DataClassName('Belonging')
class Belongings extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get icon => text()();
  IntColumn get priceCents => integer()();
  TextColumn get currency => text().withLength(min: 3, max: 3)();
  DateTimeColumn get purchaseDate => dateTime()();
  TextColumn get walletId => text()();
  TextColumn get categoryId => text()();

  /// false — річ куплена раніше, витрату не записуємо.
  BoolColumn get recordExpense => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();

  /// Продаж: усі поля або нічого.
  IntColumn get saleCents => integer().nullable()();
  TextColumn get saleCurrency => text().nullable()();
  DateTimeColumn get saleDate => dateTime().nullable()();
  TextColumn get saleWalletId => text().nullable()();

  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
  BoolColumn get deleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Transactions,
    Categories,
    Settings,
    ExchangeRates,
    Wallets,
    WalletCurrencies,
    Transfers,
    Assets,
    AssetTrades,
    Belongings,
    HistoricalRates,
    Budgets,
    Templates,
    Goals,
    GoalContributions,
    ActivityCategories,
    Activities,
    Todos,
    TodoCompletions,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(
        executor ??
            driftDatabase(
              name: 'mymanager',
              // Кнопка «Виконано» в сповіщенні працює у фоновому ізоляті —
              // він підключається до тієї ж бази.
              native: const DriftNativeOptions(shareAcrossIsolates: true),
              // Браузер (етап 21): SQLite у WebAssembly, дані — у сховищі браузера.
              web: DriftWebOptions(
                sqlite3Wasm: Uri.parse('sqlite3.wasm'),
                driftWorker: Uri.parse('drift_worker.js'),
              ),
            ),
      );

  /// [Todo.remindBefore]: не нагадувати.
  static const noReminder = -1;

  /// Годинник для позначок «виконано / не виконано» (у тестах — свій час).
  DateTime Function() clock = DateTime.now;

  static const _uuid = Uuid();

  /// Час «створення» стартових даних для злиття під час синхронізації.
  static final seedTimestamp = DateTime.utc(2000);

  /// Основний гаманець «Готівка» — однаковий id на всіх пристроях.
  static const mainWalletId = 'wallet-cash';

  @override
  int get schemaVersion => 16;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      // v2 (етап 3): кеш курсів валют. Наявні записи не змінюються.
      if (from < 2) await m.createTable(exchangeRates);
      // v3 (етап 7): гаманці й перекази. Наявні записи переходять у «Готівку».
      if (from < 3) {
        await m.createTable(wallets);
        await m.createTable(walletCurrencies);
        await m.createTable(transfers);
        await m.addColumn(transactions, transactions.walletId);
        await _migrateToWallets();
      }
      // v4 (етап 8): активи; витрата активом і запис прибутку / збитку в записах.
      if (from < 4) {
        await m.createTable(assets);
        await m.createTable(assetTrades);
        await m.addColumn(transactions, transactions.assetId);
        await m.addColumn(transactions, transactions.assetUnits);
        await m.addColumn(transactions, transactions.tradeId);
        await _seedInvestCategories();
      }
      // v5 (етап 9): пасиви — речі, якими володієш.
      if (from < 5) {
        await m.createTable(belongings);
        await m.addColumn(transactions, transactions.belongingId);
        await _seedSaleCategory();
      }
      // v6 (етап 10): курси на дату запису.
      if (from < 6) await m.createTable(historicalRates);
      // v7 (етап 11): бюджети.
      if (from < 7) await m.createTable(budgets);
      // v8 (етап 12): шаблони й регулярні платежі.
      if (from < 8) await m.createTable(templates);
      // v9 (1.15): цілі накопичення.
      if (from < 9) {
        await m.createTable(goals);
        await m.createTable(goalContributions);
      }
      // v10 (етап 14): Activity.
      if (from < 10) {
        await m.createTable(activityCategories);
        await m.createTable(activities);
        await _seedActivityCategories();
      }
      // v11 (етап 16): To-Do.
      if (from < 11) await m.createTable(todos);
      // v12 (етап 17): повторення й ключові дати.
      if (from >= 11 && from < 12) {
        await m.addColumn(todos, todos.repeatUnit);
        await m.addColumn(todos, todos.repeatEvery);
        await m.addColumn(todos, todos.repeatWeekdays);
        await m.addColumn(todos, todos.repeatUntil);
        await m.addColumn(todos, todos.keyType);
        await m.addColumn(todos, todos.countYears);
        await m.addColumn(todos, todos.remindDays);
      }
      if (from < 12) await m.createTable(todoCompletions);
      // v13 (етап 19): нагадування.
      if (from >= 11 && from < 13) await m.addColumn(todos, todos.remindBefore);
      // v14 (етап 20): «не виконано».
      if (from >= 11 && from < 14) await m.addColumn(todos, todos.failed);
      if (from >= 12 && from < 14) {
        await m.addColumn(todoCompletions, todoCompletions.failed);
      }
      // v15 (етап 25): збережені пропуски повторів.
      if (from >= 12 && from < 15) {
        await m.addColumn(todoCompletions, todoCompletions.isAuto);
      }
      // v16 (етап 26): важливість справ.
      if (from >= 11 && from < 16) await m.addColumn(todos, todos.priority);
    },
    beforeOpen: (details) async {
      if (details.wasCreated) {
        await _seedCategories();
        await _seedMainWallet();
        await _seedActivityCategories();
      }
    },
  );

  /// Категорії для прибутку / збитку від продажу активів (етап 8).
  Future<void> _seedInvestCategories() async {
    var order = 100;
    for (final c in defaultCategories.where((c) => c.id.endsWith('-invest'))) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: c.id,
          type: c.type,
          name: c.name,
          icon: c.icon,
          color: c.color,
          sortOrder: order++,
          updatedAt: seedTimestamp,
          hidden: const Value(true),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  /// Категорія «Продаж речей» (етап 9).
  Future<void> _seedSaleCategory() async {
    for (final c in defaultCategories.where((c) => c.id == 'inc-sale')) {
      await into(categories).insert(
        CategoriesCompanion.insert(
          id: c.id,
          type: c.type,
          name: c.name,
          icon: c.icon,
          color: c.color,
          sortOrder: 50,
          updatedAt: seedTimestamp,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Future<void> _seedMainWallet() async {
    await into(wallets).insert(
      WalletsCompanion.insert(
        id: mainWalletId,
        name: 'Готівка',
        icon: 'cash',
        color: 0xFF43A047,
        sortOrder: 0,
        updatedAt: seedTimestamp,
      ),
      mode: InsertMode.insertOrIgnore,
    );
    await into(walletCurrencies).insert(
      WalletCurrenciesCompanion.insert(
        id: walletCurrencyId(mainWalletId, 'EUR'),
        walletId: mainWalletId,
        currency: 'EUR',
        updatedAt: seedTimestamp,
      ),
      mode: InsertMode.insertOrIgnore,
    );
  }

  /// Записи до етапу 7 → «Готівка»; загальний початковий баланс → EUR у «Готівці»;
  /// кожна валюта, що траплялась у записах, додається в «Готівку».
  Future<void> _migrateToWallets() async {
    await _seedMainWallet();
    final legacy =
        await (select(settings)..where(
              (s) => s.key.equals(SettingKeys.legacyInitialBalanceCents),
            ))
            .getSingleOrNull();
    final initial = int.tryParse(legacy?.value ?? '') ?? 0;
    if (initial != 0) {
      await (update(walletCurrencies)
            ..where((c) => c.id.equals(walletCurrencyId(mainWalletId, 'EUR'))))
          .write(
            WalletCurrenciesCompanion(
              initialCents: Value(initial),
              updatedAt: Value(DateTime.now().toUtc()),
            ),
          );
    }
    final used = await customSelect(
      'SELECT DISTINCT currency FROM transactions',
    ).get();
    for (final row in used) {
      final c = row.read<String>('currency');
      await into(walletCurrencies).insert(
        WalletCurrenciesCompanion.insert(
          id: walletCurrencyId(mainWalletId, c),
          walletId: mainWalletId,
          currency: c,
          updatedAt: DateTime.now().toUtc(),
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  static String walletCurrencyId(String walletId, String currency) =>
      '$walletId:$currency';

  /// Стартові категорії мають фіксовані id, щоб при синхронізації двох
  /// пристроїв вони не продублювались.
  Future<void> _seedCategories() async {
    // Старий фіксований час: будь-яка реальна зміна категорії на іншому
    // пристрої (етап 6) завжди буде новішою за стартовий набір.
    final now = seedTimestamp;
    await batch((b) {
      for (final (i, c) in defaultCategories.indexed) {
        b.insert(
          categories,
          CategoriesCompanion.insert(
            id: c.id,
            type: c.type,
            name: c.name,
            icon: c.icon,
            color: c.color,
            sortOrder: i,
            updatedAt: now,
            // Інвестиційні — лише для автоматичних записів, у формі не показуємо.
            hidden: Value(c.id.endsWith('-invest')),
          ),
        );
      }
    });
  }

  // ---------- Категорії ----------

  Stream<List<Category>> watchCategories(EntryType type) {
    return (select(categories)
          ..where(
            (c) => c.type.equalsValue(type) & c.deleted.not() & c.hidden.not(),
          )
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }

  /// Усі категорії, включно з прихованими, — щоб старі записи завжди мали назву й іконку.
  Stream<Map<String, Category>> watchCategoryMap() {
    return select(categories)
        .watch()
        .map((rows) => {for (final c in rows) c.id: c});
  }

  /// Категорії для екрана керування: включно з прихованими (крім видалених).
  Stream<List<Category>> watchManageableCategories(EntryType type) {
    return (select(categories)
          ..where((c) => c.type.equalsValue(type) & c.deleted.not())
          ..orderBy([(c) => OrderingTerm.asc(c.sortOrder)]))
        .watch();
  }

  Future<String> addCategory({
    required EntryType type,
    required String name,
    required String icon,
    required int color,
  }) async {
    final id = _uuid.v4();
    final maxOrder = categories.sortOrder.max();
    final row = await (selectOnly(
      categories,
    )..addColumns([maxOrder])).getSingle();
    await into(categories).insert(
      CategoriesCompanion.insert(
        id: id,
        type: type,
        name: name.trim(),
        icon: icon,
        color: color,
        sortOrder: (row.read(maxOrder) ?? -1) + 1,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return id;
  }

  Future<void> updateCategory(
    String id, {
    required String name,
    required String icon,
    required int color,
    required bool hidden,
  }) {
    return (update(categories)..where((c) => c.id.equals(id))).write(
      CategoriesCompanion(
        name: Value(name.trim()),
        icon: Value(icon),
        color: Value(color),
        hidden: Value(hidden),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<int> countEntries() async {
    final count = transactions.id.count();
    final row =
        await (selectOnly(transactions)
              ..addColumns([count])
              ..where(transactions.deleted.not()))
            .getSingle();
    return row.read(count) ?? 0;
  }

  // ---------- Записи ----------

  Stream<List<MoneyEntry>> watchEntries(EntryType type) {
    return (select(transactions)
          ..where((t) => t.type.equalsValue(type) & t.deleted.not())
          ..orderBy([
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Stream<List<MoneyEntry>> watchAllEntries() {
    return (select(transactions)..where((t) => t.deleted.not())).watch();
  }

  Future<String> addEntry({
    required EntryType type,
    required int amountCents,
    required String currency,
    required String categoryId,
    required DateTime date,
    String? note,
    String walletId = mainWalletId,
    String? assetId,
    int? assetUnits,
    String? id,
  }) async {
    final now = DateTime.now().toUtc();
    final fixedId = id != null;
    id ??= _uuid.v4();
    // Сталий id (регулярний платіж): той самий запис на всіх пристроях,
    // повторне підтвердження просто перезаписує його.
    await into(transactions).insert(
      mode: fixedId ? InsertMode.insertOrReplace : InsertMode.insert,
      TransactionsCompanion.insert(
        id: id,
        type: type,
        amountCents: amountCents,
        currency: currency,
        categoryId: categoryId,
        date: _dayOnly(date),
        note: Value(_cleanNote(note)),
        createdAt: now,
        updatedAt: now,
        walletId: Value(walletId),
        assetId: Value(assetId),
        assetUnits: Value(assetUnits),
      ),
    );
    return id;
  }

  Future<void> updateEntry(
    String id, {
    required int amountCents,
    required String currency,
    required String categoryId,
    required DateTime date,
    String? note,
    String? walletId,
    String? assetId,
    int? assetUnits,
  }) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        walletId: walletId == null ? const Value.absent() : Value(walletId),
        assetId: Value(assetId),
        assetUnits: Value(assetUnits),
        amountCents: Value(amountCents),
        currency: Value(currency),
        categoryId: Value(categoryId),
        date: Value(_dayOnly(date)),
        note: Value(_cleanNote(note)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// М'яке видалення: запис лишається в базі з позначкою, щоб видалення
  /// дійшло на інші пристрої. Повторний виклик з `false` — «Скасувати».
  Future<void> setEntryDeleted(String id, bool deleted) {
    return (update(transactions)..where((t) => t.id.equals(id))).write(
      TransactionsCompanion(
        deleted: Value(deleted),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---------- Курси валют ----------

  Stream<Map<String, ExchangeRate>> watchRates() {
    return select(exchangeRates)
        .watch()
        .map((rows) => {for (final r in rows) r.currency: r});
  }

  Future<DateTime?> lastRatesFetch() async {
    final rows = await select(exchangeRates).get();
    if (rows.isEmpty) return null;
    return rows.map((r) => r.fetchedAt).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<void> saveRates(List<ExchangeRatesCompanion> rates) {
    return batch((b) => b.insertAllOnConflictUpdate(exchangeRates, rates));
  }

  Stream<List<HistoricalRate>> watchRateHistory() =>
      select(historicalRates).watch();

  Future<List<HistoricalRate>> getRateHistory() =>
      select(historicalRates).get();

  Future<void> saveRateHistory(List<HistoricalRatesCompanion> rows) {
    return batch((b) => b.insertAllOnConflictUpdate(historicalRates, rows));
  }

  // ---------- Налаштування ----------

  /// Ключі з префіксом `local.` стосуються лише цього пристрою й не синхронізуються.
  static const localPrefix = 'local.';

  Future<String?> getSetting(String key) async {
    final row = await (select(
      settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Stream<String?> watchSetting(String key) {
    return (select(settings)..where((s) => s.key.equals(key)))
        .watchSingleOrNull()
        .map((r) => r?.value);
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await (delete(settings)..where((s) => s.key.equals(key))).go();
      return;
    }
    await into(settings).insertOnConflictUpdate(
      SettingsCompanion.insert(
        key: key,
        value: value,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
  }

  // ---------- Гаманці ----------

  Stream<List<Wallet>> watchWallets() {
    return (select(wallets)
          ..where((w) => w.deleted.not())
          ..orderBy([(w) => OrderingTerm.asc(w.sortOrder)]))
        .watch();
  }

  Stream<List<WalletCurrency>> watchWalletCurrencies() {
    return (select(walletCurrencies)..where((c) => c.deleted.not())).watch();
  }

  Future<String> addWallet({
    required String name,
    required String icon,
    required int color,
    Map<String, int> currencies = const {'EUR': 0},
  }) {
    return transaction(() async {
      final id = _uuid.v4();
      final maxOrder = wallets.sortOrder.max();
      final row = await (selectOnly(
        wallets,
      )..addColumns([maxOrder])).getSingle();
      await into(wallets).insert(
        WalletsCompanion.insert(
          id: id,
          name: name.trim(),
          icon: icon,
          color: color,
          sortOrder: (row.read(maxOrder) ?? -1) + 1,
          updatedAt: DateTime.now().toUtc(),
        ),
      );
      for (final e in currencies.entries) {
        await setWalletCurrency(id, e.key, e.value);
      }
      return id;
    });
  }

  Future<void> updateWallet(
    String id, {
    required String name,
    required String icon,
    required int color,
    required bool archived,
  }) {
    return (update(wallets)..where((w) => w.id.equals(id))).write(
      WalletsCompanion(
        name: Value(name.trim()),
        icon: Value(icon),
        color: Value(color),
        archived: Value(archived),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Додає валюту в гаманець або змінює її початковий баланс.
  Future<void> setWalletCurrency(
    String walletId,
    String currency,
    int initialCents,
  ) {
    return into(walletCurrencies).insertOnConflictUpdate(
      WalletCurrenciesCompanion.insert(
        id: walletCurrencyId(walletId, currency),
        walletId: walletId,
        currency: currency,
        initialCents: Value(initialCents),
        updatedAt: DateTime.now().toUtc(),
        deleted: const Value(false),
      ),
    );
  }

  Future<void> removeWalletCurrency(String walletId, String currency) {
    return (update(
      walletCurrencies,
    )..where((c) => c.id.equals(walletCurrencyId(walletId, currency)))).write(
      WalletCurrenciesCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Чи є записи або перекази в цьому гаманці (і, за потреби, у цій валюті).
  Future<bool> isWalletUsed(String walletId, {String? currency}) async {
    final tx =
        await (select(transactions)
              ..where(
                (t) =>
                    t.deleted.not() &
                    t.walletId.equals(walletId) &
                    (currency == null
                        ? const Constant(true)
                        : t.currency.equals(currency)),
              )
              ..limit(1))
            .get();
    if (tx.isNotEmpty) return true;
    final tr =
        await (select(transfers)
              ..where((t) {
                final from =
                    t.fromWalletId.equals(walletId) &
                    (currency == null
                        ? const Constant(true)
                        : t.fromCurrency.equals(currency));
                final to =
                    t.toWalletId.equals(walletId) &
                    (currency == null
                        ? const Constant(true)
                        : t.toCurrency.equals(currency));
                return t.deleted.not() & (from | to);
              })
              ..limit(1))
            .get();
    if (tr.isNotEmpty) return true;
    // Операції з активами: гроші за купівлю / продаж або сам актив у гаманці.
    final at =
        await (select(assetTrades)
              ..where((t) {
                final fiat =
                    t.fiatWalletId.equals(walletId) &
                    (currency == null
                        ? const Constant(true)
                        : t.fiatCurrency.equals(currency));
                final asset = currency == null
                    ? (t.walletId.equals(walletId) |
                          t.toWalletId.equals(walletId))
                    : const Constant(false);
                return t.deleted.not() & (fiat | asset);
              })
              ..limit(1))
            .get();
    return at.isNotEmpty;
  }

  Future<int> getInitialCents(String walletId, String currency) async {
    final row =
        await (select(walletCurrencies)
              ..where((c) => c.id.equals(walletCurrencyId(walletId, currency))))
            .getSingleOrNull();
    return row == null || row.deleted ? 0 : row.initialCents;
  }

  /// Видаляє порожній гаманець разом з його валютами (основний видалити не можна).
  Future<void> deleteWallet(String id) {
    assert(id != mainWalletId);
    return transaction(() async {
      final now = DateTime.now().toUtc();
      await (update(wallets)..where((w) => w.id.equals(id))).write(
        WalletsCompanion(deleted: const Value(true), updatedAt: Value(now)),
      );
      await (update(
        walletCurrencies,
      )..where((c) => c.walletId.equals(id))).write(
        WalletCurrenciesCompanion(
          deleted: const Value(true),
          updatedAt: Value(now),
        ),
      );
    });
  }

  // ---------- Перекази ----------

  Stream<List<Transfer>> watchTransfers() {
    return (select(transfers)
          ..where((t) => t.deleted.not())
          ..orderBy([
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  Future<String> addTransfer({
    required String fromWalletId,
    required String fromCurrency,
    required int fromAmountCents,
    required String toWalletId,
    required String toCurrency,
    required int toAmountCents,
    required DateTime date,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await into(transfers).insert(
      TransfersCompanion.insert(
        id: id,
        fromWalletId: fromWalletId,
        fromCurrency: fromCurrency,
        fromAmountCents: fromAmountCents,
        toWalletId: toWalletId,
        toCurrency: toCurrency,
        toAmountCents: toAmountCents,
        date: _dayOnly(date),
        note: Value(_cleanNote(note)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> updateTransfer(
    String id, {
    required String fromWalletId,
    required String fromCurrency,
    required int fromAmountCents,
    required String toWalletId,
    required String toCurrency,
    required int toAmountCents,
    required DateTime date,
    String? note,
  }) {
    return (update(transfers)..where((t) => t.id.equals(id))).write(
      TransfersCompanion(
        fromWalletId: Value(fromWalletId),
        fromCurrency: Value(fromCurrency),
        fromAmountCents: Value(fromAmountCents),
        toWalletId: Value(toWalletId),
        toCurrency: Value(toCurrency),
        toAmountCents: Value(toAmountCents),
        date: Value(_dayOnly(date)),
        note: Value(_cleanNote(note)),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Future<void> setTransferDeleted(String id, bool deleted) {
    return (update(transfers)..where((t) => t.id.equals(id))).write(
      TransfersCompanion(
        deleted: Value(deleted),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---------- Активи (етап 8) ----------

  Stream<List<Asset>> watchAssets() {
    return (select(assets)
          ..where((a) => a.deleted.not())
          ..orderBy([(a) => OrderingTerm.asc(a.code)]))
        .watch();
  }

  Future<String> addAsset({
    required String code,
    required String name,
    required AssetKind kind,
    required String basisCurrency,
  }) async {
    final id = _uuid.v4();
    await into(assets).insert(
      AssetsCompanion.insert(
        id: id,
        code: code.trim().toUpperCase(),
        name: name.trim(),
        kind: kind,
        basisCurrency: basisCurrency,
        updatedAt: DateTime.now().toUtc(),
      ),
    );
    return id;
  }

  Future<void> updateAsset(
    String id, {
    required String code,
    required String name,
    required AssetKind kind,
  }) {
    return (update(assets)..where((a) => a.id.equals(id))).write(
      AssetsCompanion(
        code: Value(code.trim().toUpperCase()),
        name: Value(name.trim()),
        kind: Value(kind),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  Stream<List<AssetTrade>> watchTrades() {
    return (select(assetTrades)
          ..where((t) => t.deleted.not())
          ..orderBy([
            (t) => OrderingTerm.desc(t.date),
            (t) => OrderingTerm.desc(t.createdAt),
          ]))
        .watch();
  }

  /// Додає або оновлює операцію ([id] == null — нова). Для продажу [pnlCents]
  /// (у валюті отриманих грошей) стає записом «Інвестиційний прибуток» або «… збиток»,
  /// пов'язаним з операцією; він не змінює баланс гаманця (гроші вже в сумі продажу).
  Future<String> saveTrade({
    String? id,
    required TradeType type,
    required String assetId,
    required int units,
    required String walletId,
    String? toWalletId,
    String? fiatWalletId,
    String? fiatCurrency,
    int? fiatCents,
    int basisCents = 0,
    int pnlCents = 0,
    required DateTime date,
    String? note,
    String? pnlNote,
  }) {
    return transaction(() async {
      final now = DateTime.now().toUtc();
      final tradeId = id ?? _uuid.v4();
      final companion = AssetTradesCompanion(
        id: Value(tradeId),
        type: Value(type),
        assetId: Value(assetId),
        units: Value(units),
        walletId: Value(walletId),
        toWalletId: Value(toWalletId),
        fiatWalletId: Value(fiatWalletId),
        fiatCurrency: Value(fiatCurrency),
        fiatCents: Value(fiatCents),
        basisCents: Value(basisCents),
        date: Value(_dayOnly(date)),
        note: Value(_cleanNote(note)),
        updatedAt: Value(now),
        deleted: const Value(false),
      );
      if (id == null) {
        await into(assetTrades)
            .insert(companion.copyWith(createdAt: Value(now)));
      } else {
        await (update(
          assetTrades,
        )..where((t) => t.id.equals(id))).write(companion);
      }

      // Запис прибутку / збитку від продажу.
      final linked = await (select(
        transactions,
      )..where((t) => t.tradeId.equals(tradeId))).get();
      final needPnl =
          type == TradeType.sell &&
          pnlCents != 0 &&
          fiatWalletId != null &&
          fiatCurrency != null;
      if (!needPnl) {
        for (final l in linked) {
          await setEntryDeleted(l.id, true);
        }
      } else {
        final income = pnlCents > 0;
        final pnl = TransactionsCompanion(
          type: Value(income ? EntryType.income : EntryType.expense),
          amountCents: Value(pnlCents.abs()),
          currency: Value(fiatCurrency),
          categoryId: Value(income ? 'inc-invest' : 'exp-invest'),
          date: Value(_dayOnly(date)),
          note: Value(_cleanNote(pnlNote)),
          walletId: Value(fiatWalletId),
          tradeId: Value(tradeId),
          updatedAt: Value(now),
          deleted: const Value(false),
        );
        if (linked.isEmpty) {
          await into(
            transactions,
          ).insert(pnl.copyWith(id: Value(_uuid.v4()), createdAt: Value(now)));
        } else {
          await (update(
            transactions,
          )..where((t) => t.id.equals(linked.first.id))).write(pnl);
          for (final extra in linked.skip(1)) {
            await setEntryDeleted(extra.id, true);
          }
        }
      }
      return tradeId;
    });
  }

  /// Видалення операції разом з її записом прибутку / збитку (і відновлення — «Скасувати»).
  Future<void> setTradeDeleted(String id, bool deleted) {
    return transaction(() async {
      final now = DateTime.now().toUtc();
      await (update(assetTrades)..where((t) => t.id.equals(id))).write(
        AssetTradesCompanion(deleted: Value(deleted), updatedAt: Value(now)),
      );
      await (update(transactions)..where((t) => t.tradeId.equals(id))).write(
        TransactionsCompanion(deleted: Value(deleted), updatedAt: Value(now)),
      );
    });
  }

  // ---------- Повне очищення ----------

  /// Видаляє всі фінансові дані й налаштування (крім `local.*` цього пристрою, окрім
  /// позначки «вітання пройдено»), повертає стартові категорії й «Готівку».
  /// Записує нову [SettingKeys.dataResetId], щоб інші пристрої теж очистились.
  Future<void> wipeAllData({required String resetId}) {
    return transaction(() async {
      await delete(transactions).go();
      await delete(transfers).go();
      await delete(assetTrades).go();
      await delete(assets).go();
      await delete(belongings).go();
      await delete(budgets).go();
      await delete(templates).go();
      await delete(goalContributions).go();
      await delete(goals).go();
      await delete(activities).go();
      await delete(activityCategories).go();
      await delete(todos).go();
      await delete(todoCompletions).go();
      await delete(walletCurrencies).go();
      await delete(wallets).go();
      await delete(categories).go();
      await (delete(
        settings,
      )..where((s) => s.key.like('$localPrefix%').not())).go();
      await (delete(
        settings,
      )..where((s) => s.key.equals('${localPrefix}onboarding_done'))).go();
      await _seedCategories();
      await _seedMainWallet();
      await _seedActivityCategories();
      await setSetting(SettingKeys.dataResetId, resetId);
    });
  }

  // ---------- To-Do (етап 16) ----------

  Stream<List<Todo>> watchTodos() =>
      (select(todos)
            ..where((t) => t.deleted.not())
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .watch();

  /// Видалені повторювані справи — лише для історії: їхні минулі виконання
  /// й пропуски лишаються в «Завершених» і календарі (етап 24).
  Stream<List<Todo>> watchDeletedSeries() =>
      (select(todos)..where(
            (t) =>
                t.deleted &
                t.keyType.isNull() &
                t.repeatUnit.equalsValue(TodoRepeat.none).not(),
          ))
          .watch();

  Future<String> saveTodo({
    String? id,
    required String title,
    String? note,
    DateTime? dueDate,
    int? dueMinutes,
    TodoRepeat repeat = TodoRepeat.none,
    int repeatEvery = 1,
    List<int>? weekdays,
    DateTime? repeatUntil,
    String? keyType,
    bool countYears = false,
    int remindDays = 0,
    int remindBefore = 0,
    int priority = TodoPriority.should,
  }) async {
    final now = DateTime.now().toUtc();
    final tId = id ?? _uuid.v4();
    // Ключова дата — завжди щороку; повторення без дати неможливе.
    final rep = keyType != null
        ? TodoRepeat.year
        : (dueDate == null ? TodoRepeat.none : repeat);
    final data = TodosCompanion(
      id: Value(tId),
      title: Value(title.trim()),
      note: Value(_cleanNote(note)),
      dueDate: Value(dueDate == null ? null : _dayOnly(dueDate)),
      dueMinutes: Value(dueDate == null || keyType != null ? null : dueMinutes),
      repeatUnit: Value(rep),
      repeatEvery: Value(
        rep == TodoRepeat.none || keyType != null
            ? 1
            : repeatEvery.clamp(1, 999),
      ),
      repeatWeekdays: Value(
        rep == TodoRepeat.week && weekdays != null && weekdays.isNotEmpty
            ? (weekdays.toSet().toList()..sort()).join(',')
            : null,
      ),
      repeatUntil: Value(
        rep == TodoRepeat.none || repeatUntil == null || keyType != null
            ? null
            : _dayOnly(repeatUntil),
      ),
      keyType: Value(keyType),
      countYears: Value(keyType != null && countYears),
      remindDays: Value(keyType == null ? 0 : remindDays),
      remindBefore: Value(keyType == null ? remindBefore : 0),
      // Ключові дати важливості не мають.
      priority: Value(
        keyType == null
            ? priority.clamp(TodoPriority.must, TodoPriority.could)
            : TodoPriority.should,
      ),
      updatedAt: Value(now),
    );
    if (id == null) {
      await into(todos).insert(data.copyWith(createdAt: Value(now)));
    } else {
      await (update(todos)..where((t) => t.id.equals(id))).write(data);
    }
    return tId;
  }

  Future<void> setTodoDone(String id, bool done) =>
      (update(todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          done: Value(done),
          failed: const Value(false),
          doneAt: Value(done ? clock() : null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  /// Закрити разову справу як «не виконано» (або відкрити знову).
  Future<void> setTodoFailed(String id, bool failed) =>
      (update(todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          done: const Value(false),
          failed: Value(failed),
          doneAt: Value(failed ? clock() : null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Stream<List<TodoCompletion>> watchTodoCompletions() =>
      (select(todoCompletions)..where((c) => c.deleted.not())).watch();

  static String completionId(String todoId, DateTime date) =>
      '$todoId:${_dayOnly(date).toIso8601String().substring(0, 10)}';

  /// Позначити виконаним / невиконаним один повтор повторюваної справи.
  Future<void> setOccurrenceDone(String todoId, DateTime date, bool done) =>
      _closeOccurrence(todoId, date, closed: done, failed: false);

  /// Закрити один повтор як «не виконано» (або відкрити знову).
  Future<void> setOccurrenceFailed(String todoId, DateTime date, bool failed) =>
      _closeOccurrence(todoId, date, closed: failed, failed: true);

  Future<void> _closeOccurrence(
    String todoId,
    DateTime date, {
    required bool closed,
    required bool failed,
  }) {
    return into(todoCompletions).insertOnConflictUpdate(
      TodoCompletionsCompanion.insert(
        id: completionId(todoId, date),
        todoId: todoId,
        date: _dayOnly(date),
        doneAt: clock(),
        updatedAt: DateTime.now().toUtc(),
        deleted: Value(!closed),
        failed: Value(closed && failed),
        // Будь-яка позначка вручну — вже не автоматичний пропуск (етап 25).
        isAuto: const Value(false),
      ),
    );
  }

  /// Час зміни автоматичного пропуску (етап 25): найменший, тож при злитті
  /// будь-яка справжня позначка з іншого пристрою перемагає.
  static final autoMissUpdatedAt = DateTime.utc(2000);

  /// Усі записи повторів, разом із «відкритими знову» (deleted).
  Future<List<TodoCompletion>> allTodoCompletions() =>
      select(todoCompletions).get();

  /// Записати пропуски повторів ([todoId], день). Наявні записи (навіть
  /// «відкриті знову») не чіпаються.
  Future<void> recordAutoMisses(Iterable<(String, DateTime)> misses) =>
      batch((b) {
        for (final (todoId, date) in misses) {
          final day = _dayOnly(date);
          b.insert(
            todoCompletions,
            TodoCompletionsCompanion.insert(
              id: completionId(todoId, day),
              todoId: todoId,
              date: day,
              doneAt: DateTime(day.year, day.month, day.day, 23, 59),
              updatedAt: autoMissUpdatedAt,
              failed: const Value(true),
              isAuto: const Value(true),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });

  Future<void> setTodoDeleted(String id, bool deleted) =>
      (update(todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          deleted: Value(deleted),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  // ---------- Activity (етап 14) ----------

  /// Стартові категорії активностей (сталі id — однакові на всіх пристроях).
  static const defaultActivityCategories = [
    ('act-sleep', 'Сон', 'sleep', 0xFF5C6BC0, ActivityKind.neutral),
    (
      'act-breakfast',
      'Сніданок',
      'breakfast',
      0xFFFFA726,
      ActivityKind.neutral,
    ),
    ('act-lunch', 'Обід', 'lunch', 0xFFFB8C00, ActivityKind.neutral),
    ('act-dinner', 'Вечеря', 'dinner', 0xFFEF6C00, ActivityKind.neutral),
    ('act-work', 'Робота', 'work', 0xFF1E88E5, ActivityKind.useful),
    ('act-study', 'Навчання', 'study', 0xFF00897B, ActivityKind.useful),
    ('act-sport', 'Спорт', 'sport', 0xFF43A047, ActivityKind.useful),
    ('act-commute', 'Дорога', 'commute', 0xFF757575, ActivityKind.neutral),
    ('act-youtube', 'YouTube', 'youtube', 0xFFE53935, ActivityKind.waste),
    ('act-social', 'Соцмережі', 'social', 0xFFD81B60, ActivityKind.waste),
    ('act-rest', 'Відпочинок', 'rest', 0xFF8E24AA, ActivityKind.neutral),
    ('act-chores', 'Домашні справи', 'chores', 0xFF6D4C41, ActivityKind.useful),
  ];

  Future<void> _seedActivityCategories() async {
    for (final (i, c) in defaultActivityCategories.indexed) {
      await into(activityCategories).insert(
        ActivityCategoriesCompanion.insert(
          id: c.$1,
          name: c.$2,
          icon: c.$3,
          color: c.$4,
          kind: c.$5,
          sortOrder: i,
          updatedAt: seedTimestamp,
        ),
        mode: InsertMode.insertOrIgnore,
      );
    }
  }

  Stream<List<ActivityCategory>> watchActivityCategories() =>
      (select(activityCategories)
            ..where((c) => c.deleted.not())
            ..orderBy([
              (c) => OrderingTerm.asc(c.sortOrder),
              (c) => OrderingTerm.asc(c.name),
            ]))
          .watch();

  Future<String> saveActivityCategory({
    String? id,
    required String name,
    required String icon,
    required int color,
    required ActivityKind kind,
    bool hidden = false,
  }) async {
    final now = DateTime.now().toUtc();
    if (id == null) {
      final newId = _uuid.v4();
      final maxOrder =
          await (selectOnly(activityCategories)
                ..addColumns([activityCategories.sortOrder.max()]))
              .map((r) => r.read(activityCategories.sortOrder.max()))
              .getSingle();
      await into(activityCategories).insert(
        ActivityCategoriesCompanion.insert(
          id: newId,
          name: name.trim(),
          icon: icon,
          color: color,
          kind: kind,
          sortOrder: (maxOrder ?? 0) + 1,
          updatedAt: now,
        ),
      );
      return newId;
    }
    await (update(activityCategories)..where((c) => c.id.equals(id))).write(
      ActivityCategoriesCompanion(
        name: Value(name.trim()),
        icon: Value(icon),
        color: Value(color),
        kind: Value(kind),
        hidden: Value(hidden),
        updatedAt: Value(now),
      ),
    );
    return id;
  }

  Stream<List<Activity>> watchActivities() =>
      (select(activities)
            ..where((a) => a.deleted.not())
            ..orderBy([(a) => OrderingTerm.asc(a.start)]))
          .watch();

  /// Нова ([id] == null) або змінена активність. [end] == null — таймер.
  Future<String> saveActivity({
    String? id,
    required String categoryId,
    required DateTime start,
    DateTime? end,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final aId = id ?? _uuid.v4();
    final data = ActivitiesCompanion(
      id: Value(aId),
      categoryId: Value(categoryId),
      start: Value(start),
      end: Value(end),
      note: Value(_cleanNote(note)),
      updatedAt: Value(now),
      deleted: const Value(false),
    );
    if (id == null) {
      await into(activities).insert(data.copyWith(createdAt: Value(now)));
    } else {
      await (update(activities)..where((a) => a.id.equals(id))).write(data);
    }
    return aId;
  }

  /// Зупинити таймер.
  Future<void> stopActivity(String id, DateTime end) =>
      (update(activities)..where((a) => a.id.equals(id))).write(
        ActivitiesCompanion(
          end: Value(end),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> setActivityDeleted(String id, bool deleted) =>
      (update(activities)..where((a) => a.id.equals(id))).write(
        ActivitiesCompanion(
          deleted: Value(deleted),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  // ---------- Цілі (1.15) ----------

  Stream<List<Goal>> watchGoals() =>
      (select(goals)
            ..where((g) => g.deleted.not())
            ..orderBy([(g) => OrderingTerm.asc(g.createdAt)]))
          .watch();

  Stream<List<GoalContribution>> watchGoalContributions() =>
      (select(goalContributions)
            ..where((c) => c.deleted.not())
            ..orderBy([
              (c) => OrderingTerm.desc(c.date),
              (c) => OrderingTerm.desc(c.createdAt),
            ]))
          .watch();

  Future<String> saveGoal({
    String? id,
    required String name,
    required String icon,
    required int targetCents,
    required String currency,
    DateTime? deadline,
  }) async {
    final now = DateTime.now().toUtc();
    final gId = id ?? _uuid.v4();
    final data = GoalsCompanion(
      id: Value(gId),
      name: Value(name.trim()),
      icon: Value(icon),
      targetCents: Value(targetCents),
      currency: Value(currency),
      deadline: Value(deadline == null ? null : _dayOnly(deadline)),
      updatedAt: Value(now),
    );
    if (id == null) {
      await into(goals).insert(data.copyWith(createdAt: Value(now)));
    } else {
      await (update(goals)..where((g) => g.id.equals(id))).write(data);
    }
    return gId;
  }

  Future<void> setGoalArchived(String id, bool archived) =>
      (update(goals)..where((g) => g.id.equals(id))).write(
        GoalsCompanion(
          archived: Value(archived),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  Future<void> setGoalDeleted(String id, bool deleted) =>
      (update(goals)..where((g) => g.id.equals(id))).write(
        GoalsCompanion(
          deleted: Value(deleted),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  /// Внесок: [amountCents] > 0 — відклав, < 0 — зняв.
  Future<String> addGoalContribution({
    required String goalId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    await into(goalContributions).insert(
      GoalContributionsCompanion.insert(
        id: id,
        goalId: goalId,
        amountCents: amountCents,
        date: _dayOnly(date),
        note: Value(_cleanNote(note)),
        createdAt: now,
        updatedAt: now,
      ),
    );
    return id;
  }

  Future<void> setGoalContributionDeleted(String id, bool deleted) =>
      (update(goalContributions)..where((c) => c.id.equals(id))).write(
        GoalContributionsCompanion(
          deleted: Value(deleted),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );

  // ---------- Шаблони й регулярні платежі (етап 12) ----------

  Stream<List<EntryTemplate>> watchTemplates() =>
      (select(templates)
            ..where((t) => t.deleted.not())
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch();

  /// id записів регулярних платежів, які вже записано або пропущено
  /// (пропуск — видалений запис з тим самим id, щоб дійшов на інші пристрої).
  Stream<Set<String>> watchHandledOccurrences() =>
      (select(transactions)..where((t) => t.id.like('rec:%'))).watch().map(
        (rows) => {for (final r in rows) r.id},
      );

  Future<String> saveTemplate({
    String? id,
    required EntryType type,
    required String name,
    required int amountCents,
    required String currency,
    required String categoryId,
    required String walletId,
    String? note,
    RepeatKind repeat = RepeatKind.none,
    DateTime? startDate,
  }) async {
    final now = DateTime.now().toUtc();
    final tId = id ?? _uuid.v4();
    final data = TemplatesCompanion(
      id: Value(tId),
      type: Value(type),
      name: Value(name.trim()),
      amountCents: Value(amountCents),
      currency: Value(currency),
      categoryId: Value(categoryId),
      walletId: Value(walletId),
      note: Value(_cleanNote(note)),
      repeat: Value(repeat),
      startDate: Value(
        repeat == RepeatKind.none || startDate == null
            ? null
            : _dayOnly(startDate),
      ),
      updatedAt: Value(now),
      deleted: const Value(false),
    );
    if (id == null) {
      await into(templates).insert(data.copyWith(createdAt: Value(now)));
    } else {
      await (update(templates)..where((t) => t.id.equals(id))).write(data);
    }
    return tId;
  }

  Future<void> setTemplateDeleted(String id, bool deleted) {
    return (update(templates)..where((t) => t.id.equals(id))).write(
      TemplatesCompanion(
        deleted: Value(deleted),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// Повністю прибрати рядок запису (скасування «Пропустити»).
  Future<void> deleteEntryRow(String id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Пропустити платіж: запис-«заглушка» з позначкою видалення.
  Future<void> skipOccurrence(
    EntryTemplate t,
    String occurrenceId,
    DateTime date,
  ) async {
    await addEntry(
      id: occurrenceId,
      type: t.type,
      amountCents: t.amountCents,
      currency: t.currency,
      categoryId: t.categoryId,
      date: date,
      note: t.note ?? t.name,
      walletId: t.walletId,
    );
    await setEntryDeleted(occurrenceId, true);
  }

  // ---------- Бюджети (етап 11) ----------

  static const totalBudgetId = 'total';

  Stream<List<Budget>> watchBudgets() =>
      (select(budgets)..where((b) => b.deleted.not())).watch();

  /// Створює або змінює бюджет. [categoryId] == null — загальний.
  Future<void> setBudget({
    String? categoryId,
    required int limitCents,
    required String currency,
  }) {
    return into(budgets).insertOnConflictUpdate(
      BudgetsCompanion.insert(
        id: categoryId ?? totalBudgetId,
        categoryId: Value(categoryId),
        limitCents: limitCents,
        currency: currency,
        updatedAt: DateTime.now().toUtc(),
        deleted: const Value(false),
      ),
    );
  }

  Future<void> deleteBudget(String id) {
    return (update(budgets)..where((b) => b.id.equals(id))).write(
      BudgetsCompanion(
        deleted: const Value(true),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  // ---------- Пасиви (етап 9) ----------

  Stream<List<Belonging>> watchBelongings() =>
      (select(belongings)
            ..where((b) => b.deleted.not())
            ..orderBy([
              (b) => OrderingTerm.desc(b.purchaseDate),
              (b) => OrderingTerm.desc(b.createdAt),
            ]))
          .watch();

  /// Сталі id записів речі: однакові на всіх пристроях, тож злиття не створює дублів.
  static String belongingBuyEntryId(String id) => 'belonging:$id:buy';
  static String belongingSaleEntryId(String id) => 'belonging:$id:sale';

  /// Нова річ ([id] == null) або редагування. Повертає id.
  Future<String> saveBelonging({
    String? id,
    required String name,
    required String icon,
    required int priceCents,
    required String currency,
    required DateTime purchaseDate,
    required String walletId,
    required String categoryId,
    bool recordExpense = true,
    String? note,
  }) {
    return transaction(() async {
      final now = DateTime.now().toUtc();
      final bId = id ?? _uuid.v4();
      final companion = BelongingsCompanion(
        id: Value(bId),
        name: Value(name.trim()),
        icon: Value(icon),
        priceCents: Value(priceCents),
        currency: Value(currency),
        purchaseDate: Value(_dayOnly(purchaseDate)),
        walletId: Value(walletId),
        categoryId: Value(categoryId),
        recordExpense: Value(recordExpense),
        note: Value(_cleanNote(note)),
        updatedAt: Value(now),
        deleted: const Value(false),
      );
      if (id == null) {
        await into(belongings)
            .insert(companion.copyWith(createdAt: Value(now)));
      } else {
        await (update(
          belongings,
        )..where((b) => b.id.equals(id))).write(companion);
      }
      await _syncBelongingEntries(bId);
      return bId;
    });
  }

  /// Продаж речі: гроші надходять у гаманець («Продаж речей»).
  Future<void> sellBelonging(
    String id, {
    required int saleCents,
    required String currency,
    required String walletId,
    required DateTime date,
  }) {
    return transaction(() async {
      await (update(belongings)..where((b) => b.id.equals(id))).write(
        BelongingsCompanion(
          saleCents: Value(saleCents),
          saleCurrency: Value(currency),
          saleWalletId: Value(walletId),
          saleDate: Value(_dayOnly(date)),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _syncBelongingEntries(id);
    });
  }

  /// Скасувати продаж: річ знову «є», надходження прибирається.
  Future<void> cancelBelongingSale(String id) {
    return transaction(() async {
      await (update(belongings)..where((b) => b.id.equals(id))).write(
        BelongingsCompanion(
          saleCents: const Value(null),
          saleCurrency: const Value(null),
          saleWalletId: const Value(null),
          saleDate: const Value(null),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _syncBelongingEntries(id);
    });
  }

  /// Видалення / відновлення речі разом з її записами.
  Future<void> setBelongingDeleted(String id, bool deleted) {
    return transaction(() async {
      await (update(belongings)..where((b) => b.id.equals(id))).write(
        BelongingsCompanion(
          deleted: Value(deleted),
          updatedAt: Value(DateTime.now().toUtc()),
        ),
      );
      await _syncBelongingEntries(id);
    });
  }

  /// Приводить записи витрати / надходження у відповідність до стану речі.
  Future<void> _syncBelongingEntries(String id) async {
    final b = await (select(
      belongings,
    )..where((t) => t.id.equals(id))).getSingle();
    final now = DateTime.now().toUtc();

    Future<void> upsert(
      String entryId,
      bool needed,
      TransactionsCompanion data,
    ) async {
      final existing = await (select(
        transactions,
      )..where((t) => t.id.equals(entryId))).getSingleOrNull();
      if (!needed) {
        if (existing != null && !existing.deleted) {
          await (update(
            transactions,
          )..where((t) => t.id.equals(entryId))).write(
            TransactionsCompanion(
              deleted: const Value(true),
              updatedAt: Value(now),
            ),
          );
        }
        return;
      }
      final row = data.copyWith(
        belongingId: Value(id),
        updatedAt: Value(now),
        deleted: const Value(false),
      );
      if (existing == null) {
        await into(transactions)
            .insert(row.copyWith(id: Value(entryId), createdAt: Value(now)));
      } else {
        await (update(
          transactions,
        )..where((t) => t.id.equals(entryId))).write(row);
      }
    }

    await upsert(
      belongingBuyEntryId(id),
      !b.deleted && b.recordExpense,
      TransactionsCompanion(
        type: const Value(EntryType.expense),
        amountCents: Value(b.priceCents),
        currency: Value(b.currency),
        categoryId: Value(b.categoryId),
        date: Value(b.purchaseDate),
        walletId: Value(b.walletId),
        note: Value(b.name),
      ),
    );
    final sold =
        b.saleCents != null &&
        b.saleCurrency != null &&
        b.saleWalletId != null &&
        b.saleDate != null;
    await upsert(
      belongingSaleEntryId(id),
      !b.deleted && sold,
      TransactionsCompanion(
        type: const Value(EntryType.income),
        amountCents: Value(b.saleCents ?? 0),
        currency: Value(b.saleCurrency ?? b.currency),
        categoryId: const Value('inc-sale'),
        date: Value(b.saleDate ?? b.purchaseDate),
        walletId: Value(b.saleWalletId ?? b.walletId),
        note: Value(b.name),
      ),
    );
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static String? _cleanNote(String? note) {
    final t = note?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}
