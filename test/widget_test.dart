import 'package:my_manager/features/settings/backup.dart';
import 'package:my_manager/core/version.dart';

import 'dart:typed_data';
import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:my_manager/app.dart';
import 'package:my_manager/features/notifications/notification_plan.dart';
import 'package:my_manager/features/notifications/notifications.dart';
import 'package:my_manager/features/todo/todo_screen.dart';
import 'package:my_manager/features/activity/activity_screen.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/ledger.dart';
import 'package:my_manager/data/rates_service.dart';
import 'package:my_manager/features/finance/finance_providers.dart';
import 'package:my_manager/features/onboarding/welcome_screen.dart';
import 'package:my_manager/sync/snapshot.dart';
import 'package:my_manager/features/security/lock.dart';
import 'package:my_manager/sync/sync_controller.dart';

import 'helpers/fake_notifications.dart';
import 'helpers/fake_net.dart';
import 'helpers/memory_cloud.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  setUpAll(() => initializeDateFormatting('uk'));

  Future<AppDatabase> pumpApp(
    WidgetTester tester, {
    bool online = true,
    bool onboarded = true,
    MemoryCloudStore? cloud,
    BackupFiles? backup,
    List<dynamic> extra = const [],
    Future<void> Function(AppDatabase db)? before,
    NotificationBackend? notifications,
  }) async {
    // Екран типового Android-телефона (411×914 dp).
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);

    final db = AppDatabase(NativeDatabase.memory());
    if (onboarded) {
      await tester.runAsync(() => db.setSetting(onboardingDoneKey, '1'));
    }
    if (before != null) await tester.runAsync(() => before(db));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ...extra.cast(),
          ratesServiceProvider.overrideWithValue(
            RatesService(
              db,
              client: fakeNet(ecb: online, nbu: online),
            ),
          ),
          syncAuthProvider.overrideWithValue(FakeSyncAuth()),
          notificationBackendProvider.overrideWithValue(
            notifications ?? FakeNotificationBackend(),
          ),
          cloudStoreProvider.overrideWithValue(cloud ?? MemoryCloudStore()),
          if (backup != null) backupFilesProvider.overrideWithValue(backup),
        ],
        child: const MyManagerApp(),
      ),
    );
    // Перший екран чекає на базу (чи показувати вітання).
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
    return db;
  }

  Future<void> settle(WidgetTester tester) async {
    // База відповідає в реальному часі, а анімації — у тестовому.
    // Чергуємо обидва, поки екран не встановиться (переходи ~300 мс).
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
    }
    await tester.pump();
  }

  /// Прибираємо екран і закриваємо базу в тестовому часі — інакше drift
  /// чекає на таймери, які ніхто не прокручує.
  Future<void> closeDb(WidgetTester tester, AppDatabase db) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    final closing = db.close();
    await tester.pump(const Duration(seconds: 1));
    await closing;
  }

  String norm(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');
  Finder textNorm(String s) => find.byWidgetPredicate(
    (w) => w is Text && w.data != null && norm(w.data!) == s,
  );

  testWidgets('Головне меню показує три модулі й відкриває Finance', (
    tester,
  ) async {
    final db = await pumpApp(tester);

    expect(find.text('Finance'), findsOneWidget);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('To-do'), findsOneWidget);

    await tester.tap(find.text('Finance'));
    await settle(tester);

    expect(find.text('Загальний баланс'), findsOneWidget);
    expect(textNorm('0,00 €'), findsOneWidget);

    await closeDb(tester, db);
  });

  testWidgets('Додавання витрати змінює баланс', (tester) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Finance'));
    await settle(tester);

    await tester.tap(find.text('− Витрати'));
    await settle(tester);
    expect(find.textContaining('Витрат ще немає'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);

    await tester.enterText(find.byType(TextField).first, '12,50');
    await tester.tap(find.text('Продукти'));
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);

    // Повернулись до списку — запис є.
    expect(find.text('Продукти'), findsOneWidget);
    expect(
      textNorm('− 12,50 €'),
      findsNWidgets(2),
    ); // запис + «Разом за період»
    expect(find.text('Разом за період'), findsOneWidget);
    expect(find.text('Сьогодні'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(
      textNorm('− 12,50 €'),
      findsOneWidget,
    ); // баланс на головному екрані Finance

    await closeDb(tester, db);
  });

  testWidgets('Форма не зберігає без суми й категорії', (tester) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('+ Надходження'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);

    await tester.tap(find.text('Зберегти'));
    await tester.pump();
    expect(find.textContaining('Введи суму'), findsOneWidget);
    expect(find.text('Вибери категорію'), findsOneWidget);

    await closeDb(tester, db);
  });

  testWidgets('Витрата в гривнях перераховується в EUR', (tester) async {
    final db = await pumpApp(tester);
    await tester.runAsync(
      () => db.setWalletCurrency(AppDatabase.mainWalletId, 'UAH', 0),
    );
    await tester.tap(find.text('Finance'));
    await settle(tester);
    expect(
      find.textContaining('50,58 ₴'),
      findsOneWidget,
    ); // курси завантажились

    await tester.tap(find.text('− Витрати'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '505,77');
    await tester.tap(find.text('UAH'));
    await tester.pump();
    expect(
      find.textContaining(RegExp(r'≈ 10,00\s€ за поточним курсом')),
      findsOneWidget,
    );

    await tester.tap(find.text('Продукти'));
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(textNorm('− 505,77 ₴'), findsOneWidget);
    expect(textNorm('≈ 10,00 €'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(textNorm('− 10,00 €'), findsOneWidget); // баланс

    await closeDb(tester, db);
  });

  testWidgets('Без інтернету: запис у гривнях не губиться, є попередження', (
    tester,
  ) async {
    final db = await pumpApp(tester, online: false);
    await tester.runAsync(
      () => db.addEntry(
        type: EntryType.expense,
        amountCents: 30000,
        currency: 'UAH',
        categoryId: 'exp-phone',
        date: DateTime.now(),
      ),
    );
    await tester.tap(find.text('Finance'));
    await settle(tester);

    expect(find.text('Курсів валют ще немає'), findsOneWidget);
    expect(
      find.textContaining('немає курсу, потрібен інтернет'),
      findsOneWidget,
    );

    await closeDb(tester, db);
  });

  testWidgets('Натискання на баланс відкриває статистику', (tester) async {
    final db = await pumpApp(tester);
    final today = DateTime.now();
    await tester.runAsync(() async {
      await db.addEntry(
        type: EntryType.income,
        amountCents: 100000,
        currency: 'EUR',
        categoryId: 'inc-salary',
        date: today,
      );
      await db.addEntry(
        type: EntryType.expense,
        amountCents: 2500,
        currency: 'EUR',
        categoryId: 'exp-groceries',
        date: today,
      );
    });
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Загальний баланс'));
    await settle(tester);

    expect(find.text('Статистика'), findsWidgets);
    expect(find.text('Місяць'), findsOneWidget);
    expect(textNorm('+ 1 000,00 €'), findsOneWidget);
    expect(textNorm('− 25,00 €'), findsOneWidget);
    expect(find.text('За категоріями'), findsOneWidget);
    expect(find.text('Продукти'), findsOneWidget);

    // Перемикання на рік не ламає екран.
    await tester.tap(find.text('Рік'));
    await settle(tester);
    expect(find.text('${today.year}'), findsOneWidget);

    await closeDb(tester, db);
  });

  testWidgets('Налаштування: вхід у Google і статус синхронізації', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await settle(tester);
    await tester.tap(find.byTooltip('Налаштування'));
    await settle(tester);
    expect(find.text('Увійти через Google'), findsOneWidget);

    await tester.tap(find.text('Увійти через Google'));
    await settle(tester);
    expect(find.text('me@example.com'), findsOneWidget);
    expect(find.textContaining('Синхронізовано'), findsOneWidget);
    expect(find.text('Синхронізувати зараз'), findsOneWidget);

    await closeDb(tester, db);
  });

  // ---------------- Етап 6 і побажання ----------------

  Future<void> addRaw(
    WidgetTester tester,
    AppDatabase db,
    EntryType type,
    int cents,
    String currency,
    String cat,
  ) {
    return tester.runAsync(
      () => db.addEntry(
        type: type,
        amountCents: cents,
        currency: currency,
        categoryId: cat,
        date: DateTime.now(),
      ),
    );
  }

  testWidgets('Під балансом — сума в гривнях і доларах', (tester) async {
    final db = await pumpApp(tester);
    await addRaw(tester, db, EntryType.income, 10000, 'EUR', 'inc-salary');
    await tester.tap(find.text('Finance'));
    await settle(tester);
    expect(textNorm('100,00 €'), findsOneWidget);
    // 100 € × 50,5766 = 5057,66 ₴; × 1,1193 = 111,93 $
    expect(textNorm('≈ 5 057,66 ₴ · 111,93 \$'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('Статистика: фільтр валюти й записи категорії', (tester) async {
    final db = await pumpApp(tester);
    await addRaw(tester, db, EntryType.expense, 10000, 'EUR', 'exp-groceries');
    await addRaw(tester, db, EntryType.expense, 50577, 'UAH', 'exp-groceries');
    await addRaw(tester, db, EntryType.expense, 30000, 'UAH', 'exp-transport');
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Загальний баланс'));
    await settle(tester);

    // Усі валюти: 100 € + 10 € (505,77 ₴) + 5,93 € (300 ₴)
    expect(textNorm('− 115,93 €'), findsNWidgets(2)); // витрати й різниця

    await tester.tap(find.text('UAH'));
    await settle(tester);
    expect(
      find.text('Лише записи в UAH, суми без перерахунку'),
      findsOneWidget,
    );
    expect(textNorm('− 805,77 ₴'), findsNWidgets(2));
    expect(textNorm('505,77 ₴'), findsOneWidget); // Продукти лише гривнями

    await tester.tap(find.text('Продукти'));
    await settle(tester);
    expect(find.text('Записів у UAH: 1'), findsOneWidget);
    expect(textNorm('− 505,77 ₴'), findsNWidgets(2)); // підсумок + запис

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('Усі'));
    await settle(tester);
    await tester.tap(find.text('Продукти'));
    await settle(tester);
    expect(find.text('Записів: 2'), findsOneWidget);
    expect(textNorm('− 110,00 €'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('Список витрат за категоріями', (tester) async {
    final db = await pumpApp(tester);
    await addRaw(tester, db, EntryType.expense, 1000, 'EUR', 'exp-groceries');
    await addRaw(tester, db, EntryType.expense, 2000, 'EUR', 'exp-groceries');
    await addRaw(tester, db, EntryType.expense, 500, 'EUR', 'exp-fun');
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('− Витрати'));
    await settle(tester);

    await tester.tap(find.text('За категоріями'));
    await settle(tester);
    expect(find.text('2 записи'), findsOneWidget);
    expect(textNorm('30,00 €'), findsOneWidget);
    expect(find.text('1 запис'), findsOneWidget);
    expect(textNorm('− 10,00 €'), findsNothing); // ще згорнуто

    await tester.tap(find.text('Продукти'));
    await settle(tester);
    expect(textNorm('− 10,00 €'), findsOneWidget);
    expect(textNorm('− 20,00 €'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets(
    'Нова категорія з налаштувань з\'являється у формі; прихована — ні',
    (tester) async {
      final db = await pumpApp(tester);
      await tester.tap(find.byTooltip('Налаштування'));
      await settle(tester);
      await tester.tap(find.text('Категорії'));
      await settle(tester);
      await tester.tap(find.byTooltip('Нова категорія'));
      await settle(tester);
      await tester.enterText(find.byType(TextField), 'Кава');
      await tester.tap(find.byIcon(Icons.local_cafe_outlined));
      await tester.ensureVisible(find.text('Зберегти'));
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('Кава'), findsOneWidget);

      // Приховуємо «Одяг».
      await tester.tap(find.text('Одяг'));
      await settle(tester);
      await tester.ensureVisible(find.text('Приховати'));
      await tester.pump();
      await tester.tap(find.text('Приховати'));
      await tester.pump();
      await tester.ensureVisible(find.text('Зберегти'));
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('Прихована'), findsOneWidget);

      final all = await tester.runAsync(() => db.select(db.categories).get());
      final visible = [
        for (final c
            in all!..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
          if (c.type == EntryType.expense && !c.hidden) c.name,
      ];
      expect(visible, contains('Кава'));
      expect(visible, isNot(contains('Одяг')));
      expect(visible.last, 'Кава'); // нова — в кінці
      await closeDb(tester, db);
    },
  );

  testWidgets('Початковий баланс гаманця (з мінусом)', (tester) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Гаманці'));
    await settle(tester);
    await tester.tap(find.text('Готівка'));
    await settle(tester);
    await tester.tap(find.byTooltip('Редагувати гаманець'));
    await settle(tester);
    await tester.tap(find.textContaining('EUR · Євро'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '-150');
    await tester.tap(find.text('Зберегти').last);
    await settle(tester);
    await tester.ensureVisible(find.text('Зберегти'));
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(textNorm('− 150,00 €'), findsOneWidget); // баланс гаманця
    expect(
      await tester.runAsync(
        () => db.getInitialCents(AppDatabase.mainWalletId, 'EUR'),
      ),
      -15000,
    );
    await closeDb(tester, db);
  });

  testWidgets('Перший запуск: пропустити вхід, ввести баланс', (tester) async {
    final db = await pumpApp(tester, onboarded: false);
    expect(find.text('Вітаю в MyManager'), findsOneWidget);
    await tester.tap(find.text('Пропустити'));
    await settle(tester);
    expect(find.text('Почати'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '200');
    await tester.tap(find.text('Почати'));
    await settle(tester);
    expect(find.text('Finance'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => db.getInitialCents(AppDatabase.mainWalletId, 'EUR'),
      ),
      20000,
    );
    await closeDb(tester, db);
  });

  testWidgets('Перший запуск: вхід у Google відновлює записи з Drive', (
    tester,
  ) async {
    // На «Drive» уже є дані з іншого телефона.
    final cloud = MemoryCloudStore();
    final other = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(() async {
      await other.addEntry(
        type: EntryType.expense,
        amountCents: 4242,
        currency: 'EUR',
        categoryId: 'exp-fun',
        date: DateTime.now(),
      );
      cloud.files['finance.json'] = (await other.exportSnapshot()).encode();
      await other.close();
    });

    final db = await pumpApp(tester, onboarded: false, cloud: cloud);
    await tester.tap(find.text('Увійти через Google'));
    await settle(tester);
    await settle(tester);
    expect(
      find.text('Finance'),
      findsOneWidget,
    ); // одразу в меню, без кроку балансу
    expect(await tester.runAsync(() => db.countEntries()), 1);
    await closeDb(tester, db);
  });

  testWidgets('Наявний користувач після оновлення не бачить вітання', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    await tester.runAsync(
      () => db.addEntry(
        type: EntryType.expense,
        amountCents: 1,
        currency: 'EUR',
        categoryId: 'exp-other',
        date: DateTime.now(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          ratesServiceProvider.overrideWithValue(
            RatesService(db, client: fakeNet()),
          ),
          syncAuthProvider.overrideWithValue(FakeSyncAuth()),
          notificationBackendProvider.overrideWithValue(
            FakeNotificationBackend(),
          ),
          cloudStoreProvider.overrideWithValue(MemoryCloudStore()),
        ],
        child: const MyManagerApp(),
      ),
    );
    await settle(tester);
    expect(find.text('Вітаю в MyManager'), findsNothing);
    expect(find.text('Finance'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('Вихід із незбереженої форми питає підтвердження', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('− Витрати'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '5');
    await tester.pump();

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Вийти без збереження?'), findsOneWidget);
    await tester.tap(find.text('Залишитись'));
    await settle(tester);
    expect(find.text('Нова витрата'), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('Вийти'));
    await settle(tester);
    expect(find.text('Нова витрата'), findsNothing);
    expect(find.text('Витрати'), findsWidgets);
    await closeDb(tester, db);
  });

  // ---------------- Етап 7: гаманці ----------------

  testWidgets('Новий гаманець з гривнею, переказ з обміном, витрата з картки', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.runAsync(
      () => db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 20000),
    );
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Гаманці'));
    await settle(tester);

    // Новий гаманець «Картка» з EUR (стандартно) і UAH.
    await tester.tap(find.text('Гаманець'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'Картка');
    await tester.tap(find.text('Додати валюту'));
    await settle(tester);
    await tester.tap(find.text('Гривня'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).last, '1000');
    await tester.tap(find.text('Зберегти').last); // діалог початкового балансу
    await settle(tester);
    await tester.ensureVisible(find.text('Зберегти'));
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('Картка'), findsOneWidget);
    expect(textNorm('1 000,00 ₴'), findsOneWidget);

    // Переказ: 100 € з «Готівки» → 4 900 ₴ на «Картку».
    await tester.tap(find.byTooltip('Переказ між гаманцями'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).at(0), '100');
    await tester.tap(find.text('UAH'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(1), '4900');
    await tester.pump();
    expect(find.text('Курс: 1 EUR = 49,00 UAH'), findsOneWidget);
    await tester.ensureVisible(find.text('Зберегти'));
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(textNorm('100,00 €'), findsOneWidget); // готівка: 200 − 100
    expect(textNorm('5 900,00 ₴'), findsOneWidget); // картка: 1000 + 4900

    // Історія картки показує переказ.
    await tester.tap(find.text('Картка'));
    await settle(tester);
    expect(find.text('Переказ ← Готівка'), findsOneWidget);
    expect(textNorm('+ 4 900,00 ₴'), findsOneWidget);

    final transfers = await tester.runAsync(
      () => db.select(db.transfers).get(),
    );
    expect(transfers!.single.fromAmountCents, 10000);
    expect(transfers.single.toAmountCents, 490000);
    await closeDb(tester, db);
  });

  testWidgets(
    'Форма витрати: вибір гаманця й валюти; фільтр гаманця в списку',
    (tester) async {
      final db = await pumpApp(tester);
      final card = await tester.runAsync(
        () => db.addWallet(
          name: 'Картка',
          icon: 'card',
          color: 0xFF1E88E5,
          currencies: {'EUR': 0, 'PLN': 0},
        ),
      );
      await tester.tap(find.text('Finance'));
      await settle(tester);
      await tester.tap(find.text('− Витрати'));
      await settle(tester);
      await tester.tap(find.byIcon(Icons.add));
      await settle(tester);

      expect(find.text('Звідки (гаманець)'), findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Картка'));
      await tester.pump();
      await tester.tap(find.widgetWithText(ChoiceChip, 'PLN'));
      await tester.pump();
      await tester.enterText(find.byType(TextField).first, '42');
      await tester.tap(find.text('Продукти'));
      await tester.ensureVisible(find.text('Зберегти'));
      await tester.tap(find.text('Зберегти'));
      await settle(tester);

      final e = (await tester.runAsync(() => db.select(db.transactions).get()))!
          .single;
      expect(e.walletId, card);
      expect(e.currency, 'PLN');

      // Фільтр «Готівка» ховає запис з картки.
      await tester.tap(find.text('Усі гаманці'));
      await settle(tester);
      await tester.tap(find.text('Готівка').last);
      await settle(tester);
      expect(find.textContaining('витрат немає'), findsOneWidget);
      await closeDb(tester, db);
    },
  );

  testWidgets('Активи: купівля BTC, продаж з прибутком, куртка за BTC', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.runAsync(
      () => db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 100000),
    );
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Активи та пасиви'));
    await settle(tester);
    expect(find.textContaining('Активів ще немає'), findsOneWidget);

    // Купівля: 0,1 BTC за 100 € з «Готівки».
    await tester.tap(find.text('Купити'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Тікер'), 'btc');
    await tester.enterText(find.widgetWithText(TextField, 'Назва'), 'Bitcoin');
    await tester.enterText(find.widgetWithText(TextField, 'Кількість'), '0,1');
    await tester.enterText(find.widgetWithText(TextField, 'Сплачено'), '100');
    await tester.pump();
    expect(textNorm('Ціна: 1 000,00 € за 1 BTC'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('BTC · Bitcoin'), findsOneWidget);
    expect(textNorm('0,1 BTC'), findsWidgets);

    // Продаж половини за 80 € → прибуток 30 €.
    await tester.tap(find.text('BTC · Bitcoin'));
    await settle(tester);
    await tester.tap(find.text('Продати'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Кількість'), '0,05');
    await tester.enterText(find.widgetWithText(TextField, 'Отримано'), '80');
    await tester.pump();
    expect(textNorm('Прибуток: + 30,00 € → у надходження'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);

    final pnl = (await tester.runAsync(() => db.select(db.transactions).get()))!
        .single;
    expect(pnl.categoryId, 'inc-invest');
    expect(pnl.amountCents, 3000);

    // Витрата: куртка за 0,01 BTC → 10 € за ціною купівлі.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('− Витрати'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'BTC'));
    await tester.pump();
    expect(find.widgetWithText(TextField, 'Кількість'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '0,01');
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            norm(w.data!).startsWith('≈ 10,00 € за ціною купівлі'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Одяг'));
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(textNorm('− 0,01 BTC'), findsOneWidget);

    final spend = (await tester.runAsync(
      () => db.select(db.transactions).get(),
    ))!.firstWhere((e) => e.categoryId == 'exp-clothes');
    expect(spend.amountCents, 1000);
    expect(spend.currency, 'EUR');
    expect(spend.assetUnits, 1000000);

    // Більше, ніж є, витратити не можна.
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'BTC'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).first, '1');
    await tester.tap(find.text('Одяг'));
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            norm(w.data!) == 'У гаманці лише 0,04 BTC',
      ),
      findsOneWidget,
    );

    // Баланс: 1000 − 100 + 80 = 980 € (прибуток і куртка — лише в статистиці).
    final m = buildMovements(
      entries: (await tester.runAsync(() => db.select(db.transactions).get()))!,
      walletCurrencies: (await tester.runAsync(
        () => db.select(db.walletCurrencies).get(),
      ))!,
      trades: (await tester.runAsync(() => db.select(db.assetTrades).get()))!,
    );
    expect(walletBalances(m)[AppDatabase.mainWalletId]!['EUR'], 98000);
    await closeDb(tester, db);
  });

  testWidgets(
    'Пасиви: купівля речі (витрата), продаж (надходження), річ без витрати',
    (tester) async {
      final db = await pumpApp(tester);
      await tester.runAsync(
        () => db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 100000),
      );
      await tester.tap(find.text('Finance'));
      await settle(tester);
      await tester.tap(find.text('Активи та пасиви'));
      await settle(tester);
      await tester.tap(find.text('Пасиви'));
      await settle(tester);
      expect(find.textContaining('Речей ще немає'), findsOneWidget);

      // Телефон за 500 € — витрата з «Готівки».
      await tester.tap(find.text('Додати річ'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Назва'),
        'Телефон',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Ціна купівлі'),
        '500',
      );
      await tester.scrollUntilVisible(
        find.text('Зберегти'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('Телефон'), findsOneWidget);
      expect(find.text('Речей на суму'), findsOneWidget);

      // Велосипед, куплений раніше, — без витрати.
      await tester.tap(find.text('Додати річ'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Назва'),
        'Велосипед',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Ціна купівлі'),
        '300',
      );
      await tester.tap(find.text('Записати витрату'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Зберегти'),
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView).last,
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(textNorm('800,00 €'), findsOneWidget); // речей на суму

      // Продаж телефону за 300 €.
      await tester.tap(find.text('Телефон'));
      await settle(tester);
      await tester.tap(find.text('Продати'));
      await settle(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Отримано'), '300');
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is Text &&
              w.data != null &&
              norm(w.data!) == 'Різниця з ціною купівлі: − 200,00 €',
        ),
        findsOneWidget,
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Продати'));
      await settle(tester);
      expect(find.text('Скасувати продаж'), findsOneWidget);

      final entries = (await tester.runAsync(
        () => db.select(db.transactions).get(),
      ))!.where((e) => !e.deleted).toList();
      expect(entries.length, 2);
      expect(
        entries.firstWhere((e) => e.type == EntryType.income).categoryId,
        'inc-sale',
      );
      expect(
        entries.firstWhere((e) => e.type == EntryType.expense).amountCents,
        50000,
      );

      // Баланс: 1000 − 500 + 300.
      final m = buildMovements(
        entries: (await tester.runAsync(
          () => db.select(db.transactions).get(),
        ))!,
        walletCurrencies: (await tester.runAsync(
          () => db.select(db.walletCurrencies).get(),
        ))!,
      );
      expect(walletBalances(m)[AppDatabase.mainWalletId]!['EUR'], 80000);
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'Історія гаманця: інвестиційний прибуток сірий, баланс не змінює',
    (tester) async {
      final db = await pumpApp(tester);
      await tester.runAsync(() async {
        await db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 100000);
        final btc = await db.addAsset(
          code: 'BTC',
          name: 'Bitcoin',
          kind: AssetKind.crypto,
          basisCurrency: 'EUR',
        );
        await db.saveTrade(
          type: TradeType.buy,
          assetId: btc,
          units: unitsScale,
          walletId: AppDatabase.mainWalletId,
          fiatWalletId: AppDatabase.mainWalletId,
          fiatCurrency: 'EUR',
          fiatCents: 2000,
          basisCents: 2000,
          date: DateTime.now(),
        );
        await db.saveTrade(
          type: TradeType.sell,
          assetId: btc,
          units: unitsScale,
          walletId: AppDatabase.mainWalletId,
          fiatWalletId: AppDatabase.mainWalletId,
          fiatCurrency: 'EUR',
          fiatCents: 2500,
          basisCents: 2000,
          pnlCents: 500,
          date: DateTime.now(),
          pnlNote: 'Продаж 1 BTC',
        );
      });
      await tester.tap(find.text('Finance'));
      await settle(tester);
      await tester.tap(find.text('Гаманці'));
      await settle(tester);
      await tester.tap(find.text('Готівка'));
      await settle(tester);
      expect(
        find.text('Продаж 1 BTC\nне змінює баланс (лише статистика)'),
        findsOneWidget,
      );
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'Резервна копія: зберегти у файл і відновити; версія в налаштуваннях',
    (tester) async {
      final files = _FakeBackupFiles();
      final db = await pumpApp(tester, backup: files);
      await addRaw(tester, db, EntryType.expense, 1250, 'EUR', 'exp-fun');
      await tester.tap(find.byTooltip('Налаштування'));
      await settle(tester);
      Future<void> tapItem(String text) async {
        await tester.scrollUntilVisible(
          find.text(text),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pump();
        await tester.tap(find.text(text));
        await settle(tester);
      }

      await tapItem('Зберегти копію у файл');
      expect(find.text('Копію збережено'), findsOneWidget);
      expect(files.savedName, endsWith('-mymanager-backup.json'));
      final saved = FinanceSnapshot.decode(utf8.decode(files.saved!));
      expect(saved.transactions.single.amountCents, 1250);

      // Копія з іншого телефона: ще один запис.
      final other = AppDatabase(NativeDatabase.memory());
      final otherBytes = await tester.runAsync(() async {
        await other.mergeSnapshot(saved);
        await other.addEntry(
          type: EntryType.income,
          amountCents: 99900,
          currency: 'EUR',
          categoryId: 'inc-salary',
          date: DateTime(2026, 10, 1),
        );
        return utf8.encode((await other.exportSnapshot()).encode());
      });
      files.toPick = Uint8List.fromList(otherBytes!);

      await tapItem('Відновити з файлу');
      expect(find.textContaining('записів — 2'), findsOneWidget);
      await tester.tap(find.text('Відновити'));
      await settle(tester);
      expect(find.textContaining('Відновлено'), findsOneWidget);
      expect(await tester.runAsync(() => db.countEntries()), 2);

      // Чужий файл — зрозуміла помилка.
      files.toPick = Uint8List.fromList(utf8.encode('{"hello": 1}'));
      await tapItem('Відновити з файлу');
      expect(find.text('Це не файл MyManager'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('MyManager $appVersion'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('MyManager $appVersion'), findsOneWidget);
      await tester.runAsync(other.close);
      await closeDb(tester, db);
    },
  );

  testWidgets('Резервна копія в браузері: без «Надіслати копію»', (
    tester,
  ) async {
    final db = await pumpApp(
      tester,
      backup: _FakeBackupFiles(),
      extra: [backupCanShareProvider.overrideWithValue(false)],
    );
    await tester.tap(find.byTooltip('Налаштування'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Відновити з файлу'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    expect(find.text('Зберегти копію у файл'), findsOneWidget);
    expect(find.text('Надіслати копію'), findsNothing);
    await closeDb(tester, db);
  });

  testWidgets('Бюджети: ліміт категорії, смужка, попередження у формі', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await addRaw(tester, db, EntryType.expense, 15000, 'EUR', 'exp-restaurant');
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Бюджети та цілі'));
    await settle(tester);
    expect(
      find.textContaining('Бюджетів для категорій ще немає'),
      findsOneWidget,
    );

    await tester.tap(find.text('Бюджет категорії'));
    await settle(tester);
    await tester.tap(find.text('Кафе й ресторани'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '200');
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(textNorm('150,00 € / 200,00 €'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            w.data != null &&
            norm(w.data!).startsWith('Залишилось 50,00 €'),
      ),
      findsOneWidget,
    );

    // Загальний бюджет у гривнях.
    await tester.tap(find.text('Задати загальний бюджет'));
    await settle(tester);
    await tester.enterText(find.byType(TextField), '50000');
    await tester.tap(find.widgetWithText(ChoiceChip, 'UAH'));
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('Загальний бюджет'), findsOneWidget);

    // Нова витрата 80 € у кафе → попередження про перевищення.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('− Витрати'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '80');
    await tester.tap(find.text('Кафе й ресторани'));
    await tester.pump();
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.data != null && norm(w.data!) == 'Бюджет «Кафе й ресторани»: буде 230,00 € з 200,00 € — перевищення на 30,00 €',
      ),
      findsOneWidget,
    );
    // Інша категорія — без попередження.
    await tester.tap(find.text('Продукти'));
    await tester.pump();
    expect(find.textContaining('перевищення'), findsNothing);
    await tester.tap(find.text('Кафе й ресторани'));
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);

    // На головному екрані Finance — підсумок.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.textContaining('перевищено: 1'), findsOneWidget);
    await closeDb(tester, db);
  });

  testWidgets('Шаблони: зберегти з форми, записати одним дотиком', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('− Витрати'));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '3,50');
    await tester.enterText(
      find.widgetWithText(TextField, "Коментар (необов'язково)"),
      'Кава',
    );
    await tester.tap(find.text('Кафе й ресторани'));
    await tester.pump();
    await tester.tap(find.byTooltip('Зберегти як шаблон'));
    await settle(tester);
    expect(find.text('Шаблон «Кава» збережено'), findsOneWidget);
    // Вийти з форми без збереження запису.
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.tap(find.text('Вийти'));
    await settle(tester);
    expect(await tester.runAsync(() => db.countEntries()), 0);

    // Тепер у формі є шаблон: дотик — одразу записано.
    await tester.tap(find.byIcon(Icons.add));
    await settle(tester);
    expect(textNorm('Кава · 3,50 €'), findsOneWidget);
    await tester.tap(textNorm('Кава · 3,50 €'));
    await settle(tester);
    expect(find.text('Нова витрата'), findsNothing); // форма закрилась
    final e = (await tester.runAsync(() => db.select(db.transactions).get()))!
        .single;
    expect(e.amountCents, 350);
    expect(e.categoryId, 'exp-restaurant');
    expect(e.note, 'Кава');
    await closeDb(tester, db);
  });

  testWidgets(
    'Регулярний платіж: створити, підтвердити на екрані Finance, пропустити',
    (tester) async {
      final db = await pumpApp(tester);
      await tester.tap(find.text('Finance'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Шаблони й регулярні платежі'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Шаблони й регулярні платежі'));
      await settle(tester);
      await tester.tap(find.text('Новий'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Назва'),
        'Netflix',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Сума'), '12,99');
      await settle(tester);
      await tester.ensureVisible(find.widgetWithText(ChoiceChip, 'Підписки'));
      await settle(tester);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Підписки'));
      await tester.pump();
      await tester.ensureVisible(find.text('Щомісяця'));
      await tester.pump();
      await tester.tap(find.text('Щомісяця'));
      await tester.pump();
      expect(
        find.text('Перший платіж'),
        findsOneWidget,
      ); // стандартно — сьогодні
      await tester.scrollUntilVisible(
        find.text('Зберегти'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('Регулярні платежі'), findsOneWidget);
      expect(find.textContaining('Щомісяця · '), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await settle(tester);
      expect(find.text('Очікують підтвердження (1)'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Записати'));
      await settle(tester);
      expect(find.textContaining('Очікують підтвердження'), findsNothing);
      final e = (await tester.runAsync(() => db.select(db.transactions).get()))!
          .single;
      expect(e.id, startsWith('rec:'));
      expect(e.amountCents, 1299);
      expect(e.categoryId, 'exp-subscriptions');

      // Шаблон з минулою датою: 2 платежі чекають — пропускаємо один.
      await tester.runAsync(
        () => db.saveTemplate(
          type: EntryType.expense,
          name: 'Спортзал',
          amountCents: 3000,
          currency: 'EUR',
          categoryId: 'exp-health',
          walletId: AppDatabase.mainWalletId,
          repeat: RepeatKind.weekly,
          startDate: DateTime.now().subtract(const Duration(days: 8)),
        ),
      );
      await settle(tester);
      expect(find.text('Очікують підтвердження (2)'), findsOneWidget);
      await tester.tap(find.byTooltip('Ще').first);
      await settle(tester);
      await tester.tap(find.text('Пропустити'));
      await settle(tester);
      expect(find.text('Очікують підтвердження (1)'), findsOneWidget);
      await closeDb(tester, db);
    },
  );

  group('Захист PIN-кодом', () {
    late DateTime now;
    late _FakeBiometrics bio;
    List<dynamic> lockOverrides() => [
      lockClockProvider.overrideWithValue(() => now),
      biometricsProvider.overrideWithValue(bio),
    ];
    setUp(() {
      now = DateTime(2026, 10, 28, 10);
      bio = _FakeBiometrics();
    });

    Future<void> enterPin(WidgetTester tester, String pin) async {
      for (final d in pin.split('')) {
        await tester.tap(
          find.widgetWithText(TextButton, d),
          warnIfMissed: false,
        );
        await tester.pump();
      }
      await settle(tester);
    }

    Future<void> withPin(
      AppDatabase db, {
      bool biometric = false,
      String? email,
    }) async {
      const salt = 'test-salt';
      await db.setSetting(pinKey, '$salt:${hashPin('1234', salt)}');
      if (biometric) await db.setSetting(biometricKey, '1');
      if (email != null) await db.setSetting(SyncController.emailKey, email);
    }

    Future<void> background(WidgetTester tester, Duration d) async {
      for (final st in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      now = now.add(d);
      for (final st in [
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(st);
      }
      await settle(tester);
    }

    testWidgets('увімкнути в налаштуваннях; замикає після хвилини у фоні', (
      tester,
    ) async {
      final db = await pumpApp(tester, extra: lockOverrides());
      await settle(tester);
      await tester.tap(find.byTooltip('Налаштування'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Блокування PIN-кодом'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('Блокування PIN-кодом'));
      await settle(tester);
      expect(find.text('Придумай PIN з 4 цифр'), findsOneWidget);
      await enterPin(tester, '1234');
      expect(find.text('Повтори PIN'), findsOneWidget);
      await enterPin(tester, '1243');
      expect(find.text('PIN не збігся — спробуй ще раз'), findsOneWidget);
      await enterPin(tester, '1234');
      await enterPin(tester, '1234');
      expect(find.text('Змінити PIN'), findsOneWidget);
      final stored = await tester.runAsync(() => db.getSetting(pinKey));
      expect(stored, isNot(contains('1234'))); // лише сіль і хеш

      // 30 с у фоні — не замикає; 2 хв — замикає.
      await background(tester, const Duration(seconds: 30));
      expect(find.text('Введи PIN'), findsNothing);
      await background(tester, const Duration(minutes: 2));
      expect(find.text('Введи PIN'), findsOneWidget);
      expect(find.text('Захист'), findsNothing); // налаштування сховані

      await enterPin(tester, '0000');
      expect(find.text('Невірний PIN. Залишилось спроб: 4'), findsOneWidget);
      await enterPin(tester, '1234');
      expect(find.text('Введи PIN'), findsNothing);
      expect(find.text('Захист'), findsOneWidget); // той самий екран, що й був
      await closeDb(tester, db);
    });

    testWidgets('при запуску питає PIN; 5 помилок — пауза 30 с', (
      tester,
    ) async {
      final db = await pumpApp(
        tester,
        extra: lockOverrides(),
        before: (db) => withPin(db),
      );
      await settle(tester);
      expect(find.text('Введи PIN'), findsOneWidget);
      expect(find.text('Finance'), findsNothing);
      expect(find.byTooltip('Відбиток пальця'), findsNothing);
      for (var i = 0; i < 5; i++) {
        await enterPin(tester, '9999');
      }
      expect(find.textContaining('Забагато спроб'), findsOneWidget);
      await enterPin(tester, '1234'); // кнопки вимкнені
      expect(find.text('Введи PIN'), findsOneWidget);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 1));
      await enterPin(tester, '1234');
      expect(find.text('Finance'), findsOneWidget);
      await closeDb(tester, db);
    });

    testWidgets('відбиток пальця розблоковує одразу', (tester) async {
      bio.result = true;
      final db = await pumpApp(
        tester,
        extra: lockOverrides(),
        before: (db) => withPin(db, biometric: true),
      );
      await settle(tester);
      expect(bio.calls, 1);
      expect(find.text('Finance'), findsOneWidget);
      await closeDb(tester, db);
    });

    testWidgets('відбиток не підійшов — лишається PIN', (tester) async {
      bio.result = false;
      final db = await pumpApp(
        tester,
        extra: lockOverrides(),
        before: (db) => withPin(db, biometric: true),
      );
      await settle(tester);
      expect(find.text('Введи PIN'), findsOneWidget);
      expect(find.byTooltip('Відбиток пальця'), findsOneWidget);
      await enterPin(tester, '1234');
      expect(find.text('Finance'), findsOneWidget);
      await closeDb(tester, db);
    });

    testWidgets(
      'забув PIN: вхід у той самий Google вимикає PIN, інший акаунт — ні',
      (tester) async {
        final db = await pumpApp(
          tester,
          extra: lockOverrides(),
          before: (db) => withPin(db, email: 'other@example.com'),
        );
        await settle(tester);
        await tester.tap(find.text('Забув PIN?'));
        await settle(tester);
        await tester.tap(find.text('Увійти через Google'));
        await settle(tester);
        // FakeSyncAuth входить як me@example.com — це інший акаунт.
        expect(find.textContaining('Це інший акаунт'), findsOneWidget);
        expect(find.text('Finance'), findsNothing);

        await tester.runAsync(
          () => db.setSetting(SyncController.emailKey, 'ME@example.com'),
        );
        await tester.tap(find.text('Увійти через Google'));
        await settle(tester);
        expect(find.text('Finance'), findsOneWidget);
        expect(await tester.runAsync(() => db.getSetting(pinKey)), isNull);
        await closeDb(tester, db);
      },
    );

    testWidgets('забув PIN без входу в Google — пояснення, як бути', (
      tester,
    ) async {
      final db = await pumpApp(
        tester,
        extra: lockOverrides(),
        before: (db) => withPin(db),
      );
      await settle(tester);
      await tester.tap(find.text('Забув PIN?'));
      await settle(tester);
      await tester.tap(find.text('Увійти через Google'));
      await settle(tester);
      expect(find.textContaining('не було входу в Google'), findsOneWidget);
      await closeDb(tester, db);
    });
  });

  testWidgets('Наявний актив через форму; свайп балансу: + активи, + пасиви', (
    tester,
  ) async {
    final db = await pumpApp(
      tester,
      before: (db) async {
        await db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 100000);
        await db.saveBelonging(
          name: 'Велосипед',
          icon: 'bike',
          priceCents: 30000,
          currency: 'EUR',
          purchaseDate: DateTime(2025, 5, 1),
          walletId: AppDatabase.mainWalletId,
          categoryId: 'exp-other',
          recordExpense: false,
        );
      },
    );
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.tap(find.text('Активи та пасиви'));
    await settle(tester);
    await tester.tap(find.text('Купити'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Тікер'), 'eth');
    await tester.enterText(find.widgetWithText(TextField, 'Кількість'), '2');
    await tester.scrollUntilVisible(
      find.text('Уже маю — купив раніше'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Уже маю — купив раніше'));
    await settle(tester);
    expect(find.text('За скільки купував'), findsOneWidget);
    expect(find.text('З гаманця'), findsNothing);
    await tester.enterText(
      find.widgetWithText(TextField, 'Ціна купівлі (усього)'),
      '4000',
    );
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    final t = (await tester.runAsync(() => db.select(db.assetTrades).get()))!
        .single;
    expect(t.fiatWalletId, isNull);
    expect(t.basisCents, 400000);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Загальний баланс'), findsOneWidget);
    expect(textNorm('1 000,00 €'), findsOneWidget); // гроші не списано
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await settle(tester);
    expect(find.text('Баланс + активи'), findsOneWidget);
    expect(textNorm('5 000,00 €'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-400, 0));
    await settle(tester);
    expect(find.text('Баланс + активи + пасиви'), findsOneWidget);
    expect(textNorm('5 300,00 €'), findsOneWidget);
    // Дотик по будь-якій сторінці — статистика.
    await tester.tap(find.text('Баланс + активи + пасиви'));
    await settle(tester);
    expect(find.text('Статистика'), findsWidgets);
    await closeDb(tester, db);
  });

  testWidgets('Цілі: створити, відкласти, зняти, прогрес і архів', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await tester.tap(find.text('Finance'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Бюджети та цілі'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Бюджети та цілі'));
    await settle(tester);
    await tester.tap(find.text('Цілі'));
    await settle(tester);
    expect(find.textContaining('Цілей ще немає'), findsOneWidget);

    await tester.tap(find.text('Нова ціль'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'На що збираю'),
      'Ноутбук',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Скільки треба'),
      '1500',
    );
    await tester.scrollUntilVisible(
      find.text('Зберегти'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Зберегти'));
    await settle(tester);
    expect(find.text('Ноутбук'), findsOneWidget);
    expect(textNorm('0,00 € з 1 500,00 €'), findsOneWidget);

    await tester.tap(find.text('Ноутбук'));
    await settle(tester);
    await tester.tap(find.text('Відкласти'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Сума'), '600');
    await tester.tap(find.widgetWithText(TextButton, 'Відкласти'));
    await settle(tester);
    expect(textNorm('600,00 € з 1 500,00 €'), findsOneWidget);
    expect(find.text('40 %'), findsOneWidget);

    await tester.tap(find.text('Зняти'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Сума'), '100');
    await tester.tap(find.widgetWithText(TextButton, 'Зняти'));
    await settle(tester);
    expect(textNorm('500,00 € з 1 500,00 €'), findsOneWidget);
    expect(textNorm('− 100,00 €'), findsOneWidget);

    // Добираємо до 100 % — «Досягнуто» і кнопка в архів.
    await tester.tap(find.text('Відкласти'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Сума'), '1000');
    await tester.tap(find.widgetWithText(TextButton, 'Відкласти'));
    await settle(tester);
    expect(find.text('Досягнуто!'), findsOneWidget);
    await tester.tap(find.text('Ціль досягнуто — перенести в архів'));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect(find.text('Архів (1)'), findsOneWidget);
    expect(find.text('Ноутбук'), findsNothing);

    // Баланс гаманців не змінився — внески лише позначки.
    expect(await tester.runAsync(() => db.countEntries()), 0);
    await closeDb(tester, db);
  });

  testWidgets(
    'Activity: сон 1–8, «Додати» — сніданок з 8:00 до зараз; таймер; прогалина',
    (tester) async {
      var now = DateTime(2026, 10, 28, 8, 30);
      final db = await pumpApp(
        tester,
        extra: [activityClockProvider.overrideWithValue(() => now)],
        before: (db) => db.saveActivity(
          categoryId: 'act-sleep',
          start: DateTime(2026, 10, 28, 1),
          end: DateTime(2026, 10, 28, 8),
        ),
      );
      await tester.tap(find.text('Activity'));
      await settle(tester);
      expect(find.text('Сон'), findsOneWidget);
      expect(find.text('01:00 – 08:00'), findsOneWidget);
      expect(find.text('7 год'), findsOneWidget);
      expect(find.textContaining('Не записано 30 хв'), findsOneWidget);

      await tester.tap(find.text('Додати активність'));
      await settle(tester);
      expect(find.text('з кінця попередньої'), findsOneWidget);
      expect(find.text('Тривалість: 30 хв'), findsOneWidget);
      await tester.tap(find.text('Сніданок'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Зберегти'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('08:00 – 08:30'), findsOneWidget);
      expect(find.text('30 хв'), findsOneWidget);
      expect(find.textContaining('Не записано'), findsNothing);

      // Таймер: Робота з 9:00 до 10:15.
      now = DateTime(2026, 10, 28, 9);
      await tester.tap(find.text('Таймер'));
      await settle(tester);
      await tester.tap(find.text('Робота').last);
      await settle(tester);
      expect(find.text('Завершити'), findsOneWidget);
      expect(find.text('триває'), findsOneWidget);
      now = DateTime(2026, 10, 28, 10, 15);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Завершити'));
      await settle(tester);
      expect(find.text('Завершити'), findsNothing);
      expect(find.text('1 год 15 хв'), findsOneWidget);
      // Між сніданком і роботою — 30 хв не записано; дотик заповнює саме цей проміжок.
      expect(
        find.textContaining('Не записано 30 хв · 08:30 – 09:00'),
        findsOneWidget,
      );
      await tester.tap(
        find.textContaining('Не записано 30 хв · 08:30 – 09:00'),
      );
      await settle(tester);
      expect(find.text('Тривалість: 30 хв'), findsOneWidget);
      await tester.tap(find.text('Дорога'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Зберегти'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('Записано 9 год 15 хв'), findsOneWidget);

      final rows = (await tester.runAsync(
        () => db.select(db.activities).get(),
      ))!;
      expect(rows.length, 4);
      final bf = rows.firstWhere((a) => a.categoryId == 'act-breakfast');
      expect(bf.start, DateTime(2026, 10, 28, 8));
      expect(bf.end, DateTime(2026, 10, 28, 8, 30));
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'Статистика Activity: продуктивність, категорії, порівняння, записи категорії',
    (tester) async {
      final now = DateTime(2026, 10, 28, 18);
      final db = await pumpApp(
        tester,
        extra: [activityClockProvider.overrideWithValue(() => now)],
        before: (db) async {
          DateTime t(int d, int h) => DateTime(2026, 10, d, h);
          await db.saveActivity(
            categoryId: 'act-work',
            start: t(26, 9),
            end: t(26, 17),
          );
          await db.saveActivity(
            categoryId: 'act-youtube',
            start: t(26, 20),
            end: t(26, 22),
          );
          await db.saveActivity(
            categoryId: 'act-work',
            start: t(27, 9),
            end: t(27, 13),
          );
          await db.saveActivity(
            categoryId: 'act-youtube',
            start: t(20, 20),
            end: t(20, 23),
          ); // мин. тиждень, пн
          await db.saveActivity(
            categoryId: 'act-youtube',
            start: t(23, 20),
            end: t(23, 23),
          ); // мин. пт — після «зараз», не рахується
        },
      );
      await tester.tap(find.text('Activity'));
      await settle(tester);
      await tester.tap(find.byTooltip('Статистика'));
      await settle(tester);
      expect(find.text('Записано 14 год'), findsOneWidget);
      expect(find.text('12 год · 86 %'), findsOneWidget); // корисне
      expect(find.text('2 год · 14 %'), findsOneWidget); // марнування
      expect(find.text('По днях'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Робота'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('−1 год'), findsOneWidget); // YouTube: 2 год проти 3 год
      await tester.tap(find.text('Робота'));
      await settle(tester);
      expect(find.textContaining('2 записів · 12 год'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);

      // День без записів.
      await tester.scrollUntilVisible(
        find.text('День'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('День'));
      await settle(tester);
      expect(find.text('За цей період нічого не записано'), findsOneWidget);
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'To-Do: додати на сьогодні й на дату, виконати, прострочена, без дати',
    (tester) async {
      final now = DateTime(2026, 10, 28, 10);
      final db = await pumpApp(
        tester,
        extra: [todoClockProvider.overrideWithValue(() => now)],
        before: (db) => db.saveTodo(
          title: 'Оплатити рахунок',
          dueDate: DateTime(2026, 10, 26),
        ),
      );
      expect(
        find.text('Сьогодні: 1 справа'),
        findsOneWidget,
      ); // прострочена рахується
      await tester.tap(find.text('To-do'));
      await settle(tester);
      expect(find.text('Прострочені'), findsOneWidget);
      expect(find.text('Оплатити рахунок'), findsOneWidget);

      // Нова справа з вкладки «Сьогодні» — одразу на сьогодні.
      await tester.tap(find.text('Справа'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Що зробити'),
        'Подзвонити мамі',
      );
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tab-today')),
          matching: find.text('2'),
        ),
        findsOneWidget,
      );

      // Справа без дати.
      await tester.tap(find.text('Справа'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Що зробити'),
        'Прочитати книгу',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Без дати'));
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tab-nodate')));
      await settle(tester);
      expect(find.text('Прочитати книгу'), findsOneWidget);

      // Виконати прострочену галочкою — зникає з «Сьогодні», є у «Виконані».
      await tester.tap(find.byKey(const ValueKey('tab-today')));
      await settle(tester);
      final row = find.ancestor(
        of: find.text('Оплатити рахунок'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await settle(tester);
      expect(find.text('Виконано: Оплатити рахунок'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('tab-today')),
          matching: find.text('1'),
        ),
        findsOneWidget,
      );
      expect(find.text('Прострочені'), findsNothing);
      await tester.tap(find.text('Завершені'));
      await settle(tester);
      expect(find.text('Оплатити рахунок'), findsOneWidget);

      final rows = (await tester.runAsync(() => db.select(db.todos).get()))!;
      expect(
        rows.firstWhere((t) => t.title == 'Подзвонити мамі').dueDate,
        DateTime(2026, 10, 28),
      );
      expect(
        rows.firstWhere((t) => t.title == 'Прочитати книгу').dueDate,
        isNull,
      );
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'To-Do: повторювана справа (виконати повтор) і день народження з нагадуванням',
    (tester) async {
      final now = DateTime(2026, 10, 28, 10); // середа
      final db = await pumpApp(
        tester,
        extra: [todoClockProvider.overrideWithValue(() => now)],
      );
      await tester.tap(find.text('To-do'));
      await settle(tester);

      // Спортзал: щотижня пн, ср, пт.
      await tester.tap(find.text('Справа'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Що зробити'),
        'Спортзал',
      );
      await tester.scrollUntilVisible(
        find.text('Щотижня'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Щотижня'));
      await tester.pump();
      expect(find.text('Перший раз'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.widgetWithText(FilterChip, 'пн'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.widgetWithText(FilterChip, 'пн'));
      await tester.tap(find.widgetWithText(FilterChip, 'пт'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('Зберегти'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tester.tap(find.text('Зберегти'));
      await settle(tester);
      expect(find.text('Спортзал'), findsOneWidget);
      expect(find.textContaining('↻ щотижня: пн, ср, пт'), findsOneWidget);

      // Виконати сьогоднішній повтор — наступний (пт) лишається у «Далі».
      final row = find.ancestor(
        of: find.text('Спортзал'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await settle(tester);
      expect(find.text('Спортзал'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tab-planned')));
      await settle(tester);
      expect(find.textContaining('30 жовтня'), findsOneWidget);
      expect(find.text('Спортзал'), findsOneWidget);

      // День народження через 4 дні з нагадуванням за тиждень.
      await tester.pump(const Duration(seconds: 5)); // «Виконано» зникає
      await settle(tester);
      await tester.tap(find.byTooltip('Ключові дати'));
      await settle(tester);
      await tester.tap(find.text('Дата'));
      await settle(tester);
      await tester.enterText(
        find.widgetWithText(TextField, 'Назва'),
        'ДН мами',
      );
      await settle(tester);
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Зберегти'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Зберегти'));
      await tester.pump();
      expect(find.text('Вибери дату'), findsOneWidget); // без дати не зберігає
      // Дату ставимо через базу (діалог календаря в тестах незручний).
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      await tester.runAsync(
        () => db.saveTodo(
          title: 'ДН мами',
          dueDate: DateTime(1971, 11, 1),
          keyType: 'birthday',
          countYears: true,
          remindDays: 7,
        ),
      );
      await settle(tester);
      expect(find.text('ДН мами'), findsOneWidget);
      expect(find.textContaining('виповнюється 55'), findsOneWidget);
      expect(find.text('через 4 дні'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('tab-today')));
      await settle(tester);
      expect(find.text('ДН мами'), findsOneWidget); // нагадування в «Сьогодні»
      expect(
        find.textContaining('через 4 дні · 1 листопада · виповнюється 55'),
        findsOneWidget,
      );
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'Календар: позначки днів, вибір дня, місяці, активності, справа на день',
    (tester) async {
      final now = DateTime(2026, 10, 28, 20); // середа
      final db = await pumpApp(
        tester,
        extra: [
          todoClockProvider.overrideWithValue(() => now),
          activityClockProvider.overrideWithValue(() => now),
        ],
        before: (db) async {
          await db.saveTodo(
            title: 'Купити подарунок',
            dueDate: DateTime(2026, 10, 30),
          );
          await db.saveTodo(
            title: 'Спортзал',
            dueDate: DateTime(2026, 10, 26),
            dueMinutes: 18 * 60,
            repeat: TodoRepeat.week,
            weekdays: [1, 3, 5],
          );
          await db.saveTodo(
            title: 'ДН мами',
            dueDate: DateTime(1970, 11, 1),
            keyType: 'birthday',
            countYears: true,
          );
          await db.saveActivity(
            categoryId: 'act-work',
            start: DateTime(2026, 10, 28, 9),
            end: DateTime(2026, 10, 28, 13, 30),
          );
        },
      );
      await tester.tap(find.text('To-do'));
      await settle(tester);
      await tester.tap(find.byTooltip('Календар'));
      await settle(tester);

      expect(find.text('Жовтень 2026'), findsOneWidget);
      expect(find.text('Середа, 28 жовтня · сьогодні'), findsOneWidget);
      expect(find.text('Спортзал'), findsOneWidget);
      expect(find.text('Сьогодні'), findsNothing); // уже на сьогодні

      // П'ятниця: повтор і разова справа.
      await tester.tap(find.byKey(const ValueKey('day-2026-10-30')));
      await settle(tester);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('calendar-day-title')))
            .data,
        endsWith('ятниця, 30 жовтня'),
      );
      expect(find.text('Спортзал'), findsOneWidget);
      expect(find.text('Купити подарунок'), findsOneWidget);

      // Неділя 1 листопада (з сусіднього місяця в сітці) — день народження.
      await tester.tap(find.byKey(const ValueKey('day-2026-11-01')));
      await settle(tester);
      expect(find.text('Листопад 2026'), findsOneWidget);
      expect(find.text('ДН мами'), findsOneWidget);
      expect(find.textContaining('виповнюється 56'), findsOneWidget);

      // Місяці стрілками й кнопка «Сьогодні».
      await tester.tap(find.byTooltip('Наступний місяць'));
      await settle(tester);
      expect(find.text('Грудень 2026'), findsOneWidget);
      expect(find.text('Вівторок, 1 грудня'), findsOneWidget);
      await tester.tap(find.text('Сьогодні'));
      await settle(tester);
      expect(find.text('Жовтень 2026'), findsOneWidget);
      expect(find.text('Середа, 28 жовтня · сьогодні'), findsOneWidget);

      // Активності вмикаються кнопкою (і запам'ятовуються).
      expect(find.textContaining('Активності ·'), findsNothing);
      await tester.tap(find.byTooltip('Показати активності'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.textContaining('Активності ·'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Активності · 4 год 30 хв'), findsOneWidget);
      expect(find.text('Робота'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.getSetting('calendar_show_activities')),
        '1',
      );

      // Справа на вибраний день: форма відкривається з цією датою.
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('day-2026-10-29')),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('day-2026-10-29')));
      await settle(tester);
      expect(find.text('Справ цього дня не було'), findsNothing);
      expect(
        find.text('Нічого не заплановано. Натисни «Справа», щоб додати.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Справа'));
      await settle(tester);
      expect(find.widgetWithText(ChoiceChip, 'Завтра'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Завтра'))
            .selected,
        isTrue,
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Що зробити'),
        'Забрати посилку',
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Зберегти'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Зберегти'));
      await settle(tester);
      expect(find.text('Четвер, 29 жовтня · завтра'), findsOneWidget);
      expect(find.text('Забрати посилку'), findsOneWidget);
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'Сповіщення: перший запуск, «Нагадати» у справі, розклад, налаштування',
    (tester) async {
      final now = DateTime(2026, 10, 28, 12); // середа
      final fake = FakeNotificationBackend(exact: false);
      final db = await pumpApp(
        tester,
        notifications: fake,
        extra: [todoClockProvider.overrideWithValue(() => now)],
        before: (db) async {
          await db.saveTodo(
            title: 'Спортзал',
            dueDate: DateTime(2026, 10, 28),
            dueMinutes: 18 * 60,
          );
        },
      );
      await settle(tester);

      // Перший запуск: дозвіл на сповіщення й пояснення про точний час.
      expect(fake.permissionRequests, 0); // уже дозволено
      expect(find.text('Нагадування вчасно'), findsOneWidget);
      await tester.tap(find.text('Дозволити'));
      await settle(tester);
      expect(fake.exactRequests, 1);

      // Розклад: нагадування о 18:00; далі щоранку — зведення (справа стане простроченою).
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      List<PlannedNotification> reminders() => fake.planned
          .where((n) => n.kind == NotificationKind.reminder)
          .toList();
      expect(fake.planned[1].body, '1 справа (1 прострочено)');
      expect(fake.planned[1].at, DateTime(2026, 10, 29, 9));
      expect(reminders().map((n) => (n.at, n.body)), [
        (DateTime(2026, 10, 28, 18), 'Зараз · 18:00'),
      ]);
      expect(fake.plannedExact, isFalse);

      // «Нагадати за 30 хв» у формі справи.
      await tester.tap(find.text('To-do'));
      await settle(tester);
      await tester.tap(find.text('Спортзал'));
      await settle(tester);
      expect(find.text('Нагадати'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Вчасно'))
            .selected,
        isTrue,
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'За 30 хв'));
      await settle(tester);
      // Форма довша (етап 26: важливість) — кнопку треба докрутити.
      await tester.scrollUntilVisible(
        find.widgetWithText(FilledButton, 'Зберегти'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Зберегти'));
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Зберегти'));
      await settle(tester);
      expect(
        (await tester.runAsync(() => db.watchTodos().first))!
            .single
            .remindBefore,
        30,
      );
      await tester.pump(const Duration(seconds: 2));
      await settle(tester);
      expect(reminders().single.at, DateTime(2026, 10, 28, 17, 30));
      expect(reminders().single.body, 'Через 30 хв · о 18:00');

      // Налаштування → Сповіщення.
      await tester.tap(find.byType(BackButton));
      await settle(tester);
      await tester.tap(find.byTooltip('Налаштування'));
      await settle(tester);
      await tester.scrollUntilVisible(
        find.text('Надіслати тестове'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      expect(find.text('Можуть запізнюватися'), findsOneWidget);
      expect(
        find.text('Заплановано на 2 тижні: ${fake.planned.length}'),
        findsOneWidget,
      );
      expect(
        find.text('О 09:00: справи на день і ключові дати'),
        findsOneWidget,
      );
      await tester.tap(find.text('Надіслати тестове'));
      await settle(tester);
      expect(fake.tests, 1);
      // Вимкнути все — розклад порожній, налаштування запам'ятовано.
      await tester.ensureVisible(find.text('Нагадування про справи'));
      await settle(tester);
      await tester.tap(find.text('Нагадування про справи'));
      await settle(tester);
      expect(fake.planned, isEmpty);
      expect(find.text('Ранкове зведення'), findsNothing);
      expect(await tester.runAsync(() => db.getSetting(notifEnabledKey)), '0');
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'To-Do: «не виконано» свайпом, «Завершені» по днях, виконано із запізненням',
    (tester) async {
      final now = DateTime(2026, 10, 28, 12); // середа
      final db = await pumpApp(
        tester,
        extra: [todoClockProvider.overrideWithValue(() => now)],
        before: (db) async {
          db.clock = () => now;
          await db.saveTodo(
            title: 'Купити квитки',
            dueDate: DateTime(2026, 10, 28),
          );
          await db.saveTodo(title: 'Банк', dueDate: DateTime(2026, 10, 27));
          await db.saveTodo(
            title: 'Подзвонити',
            dueDate: DateTime(2026, 10, 28),
          );
          // Давня справа: виконана вчасно 20-го.
          final old = await db.saveTodo(
            title: 'Давня',
            dueDate: DateTime(2026, 10, 20),
          );
          db.clock = () => DateTime(2026, 10, 20, 18);
          await db.setTodoDone(old, true);
          db.clock = () => now;
        },
      );
      await tester.tap(find.text('To-do'));
      await settle(tester);

      // Свайп управо — «не виконано».
      await tester.drag(find.text('Купити квитки'), const Offset(500, 0));
      await settle(tester);
      expect(find.text('Не виконано: Купити квитки'), findsOneWidget);
      expect(find.text('Купити квитки'), findsNothing);
      var t = (await tester.runAsync(() => db.watchTodos().first))!
          .firstWhere((t) => t.title == 'Купити квитки');
      expect((t.failed, t.done), (true, false));
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);

      // Прострочений «Банк» (на вчора) виконуємо сьогодні.
      final row = find.ancestor(
        of: find.text('Банк'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byType(Checkbox)),
      );
      await settle(tester);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);

      // «Не виконано» з форми справи.
      await tester.tap(find.text('Подзвонити'));
      await settle(tester);
      await tester.ensureVisible(find.text('Не виконано'));
      await settle(tester);
      await tester.tap(find.text('Не виконано'));
      await settle(tester);
      expect(
        find.text('На сьогодні справ немає 🎉\nНатисни «Справа», щоб додати.'),
        findsOneWidget,
      );

      // «Завершені»: сьогодні розгорнуто, решта днів згорнуті.
      await tester.tap(find.byKey(const ValueKey('tab-done')));
      await settle(tester);
      final todayKey = find.byKey(const ValueKey('history-2026-10-28'));
      expect(
        find.descendant(of: todayKey, matching: find.text('Сьогодні')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: todayKey,
          matching: find.text('✓ 1   ✕ 2', findRichText: true),
        ),
        findsOneWidget,
      );
      expect(find.text('не виконано'), findsNWidgets(2));
      expect(find.text('із запізненням · з вчора'), findsOneWidget);
      // Вчорашній день згорнутий: «Банк» там — «не вчасно».
      expect(find.text('не вчасно · виконано сьогодні'), findsNothing);
      await tester.tap(find.text('Вчора'));
      await settle(tester);
      expect(find.text('не вчасно · виконано сьогодні'), findsOneWidget);
      expect(find.text('Давня'), findsNothing);
      await tester.scrollUntilVisible(
        find.textContaining('20 жовтня'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.textContaining('20 жовтня'));
      await settle(tester);
      expect(find.text('Давня'), findsOneWidget);

      // Відкрити знову: тап по ✕.
      await tester.scrollUntilVisible(
        find.text('Купити квитки'),
        -200,
        scrollable: find.byType(Scrollable).last,
      );
      final failedRow = find.ancestor(
        of: find.text('Купити квитки'),
        matching: find.byType(ListTile),
      );
      await tester.tap(
        find.descendant(
          of: failedRow,
          matching: find.byTooltip('Відкрити знову'),
        ),
      );
      await settle(tester);
      t = (await tester.runAsync(() => db.watchTodos().first))!
          .firstWhere((t) => t.title == 'Купити квитки');
      expect(t.failed, isFalse);

      // Календар: вівторок — ✕ «не вчасно», середа — «із запізненням».
      await tester.tap(find.byTooltip('Календар'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('day-2026-10-27')));
      await settle(tester);
      expect(find.text('не вчасно · виконано вчора'), findsNothing);
      expect(find.text('не вчасно · виконано сьогодні'), findsOneWidget);
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'To-Do (етап 24): учорашній пропуск — у «Завершених»; видалена серія лишає історію',
    (tester) async {
      final now = DateTime(2026, 10, 28, 12); // середа
      final db = await pumpApp(
        tester,
        extra: [todoClockProvider.overrideWithValue(() => now)],
        before: (db) async {
          db.clock = () => now;
          final z = await db.saveTodo(
            title: 'Чистити зуби',
            dueDate: DateTime(2026, 10, 27),
            repeat: TodoRepeat.day,
          );
          // Створено вчора (у базі дату ставить реальний годинник).
          await (db.update(db.todos)..where((t) => t.id.equals(z))).write(
            TodosCompanion(createdAt: Value(DateTime(2026, 10, 27).toUtc())),
          );
        },
      );
      await tester.tap(find.text('To-do'));
      await settle(tester);

      // Вчорашній повтор не у «Прострочених» — він у «Завершених» як «не виконано».
      expect(find.text('Прострочені'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('tab-done')));
      await settle(tester);
      expect(find.text('Чистити зуби'), findsOneWidget);
      expect(find.textContaining('не виконано'), findsOneWidget);

      // Позначити виконаним пізніше.
      await tester.tap(find.byTooltip('Виконано пізніше'));
      await settle(tester);
      expect(
        find.text('Виконано із запізненням: Чистити зуби'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(find.textContaining('із запізненням'), findsOneWidget);

      // Видалити серію з «Сьогодні»: у діалозі — що історія лишиться.
      await tester.tap(find.byKey(const ValueKey('tab-today')));
      await settle(tester);
      await tester.drag(find.text('Чистити зуби'), const Offset(-500, 0));
      await settle(tester);
      expect(
        find.textContaining('Виконані й невиконані дні лишаться'),
        findsOneWidget,
      );
      await tester.tap(find.text('Видалити'));
      await settle(tester);
      await tester.pump(const Duration(seconds: 5));
      await settle(tester);
      expect(find.text('Чистити зуби'), findsNothing);

      // Історія на місці, лише для перегляду.
      await tester.tap(find.byKey(const ValueKey('tab-done')));
      await settle(tester);
      expect(find.text('Чистити зуби'), findsOneWidget);
      expect(find.textContaining('серію видалено'), findsOneWidget);
      final row = find.ancestor(
        of: find.text('Чистити зуби'),
        matching: find.byType(ListTile),
      );
      expect(tester.widget<ListTile>(row).onTap, isNull);
      await closeDb(tester, db);
    },
  );

  testWidgets(
    'To-Do (етап 26): важливість у формі, смужка й порядок у списку',
    (tester) async {
      final now = DateTime(2026, 10, 28, 9);
      final db = await pumpApp(
        tester,
        extra: [todoClockProvider.overrideWithValue(() => now)],
        before: (db) async {
          await db.saveTodo(
            title: 'Прогулянка',
            dueDate: DateTime(2026, 10, 28),
          );
          await db.saveTodo(
            title: 'Податки',
            dueDate: DateTime(2026, 10, 28),
            dueMinutes: 18 * 60,
          );
        },
      );
      await tester.tap(find.text('To-do'));
      await settle(tester);

      Color stripe(String title) {
        final box = tester.widget<DecoratedBox>(
          find
              .ancestor(
                of: find.text(title),
                matching: find.byWidgetPredicate(
                  (w) =>
                      w is DecoratedBox &&
                      w.key is ValueKey<String> &&
                      (w.key! as ValueKey<String>).value.startsWith(
                        'priority-',
                      ),
                ),
              )
              .first,
        );
        return ((box.decoration as BoxDecoration).border! as Border).left.color;
      }

      // Обидві «бажано»: смужка жовто-помаранчева; порядок — за часом.
      expect(stripe('Податки'), priorityColor(TodoPriority.should));
      expect(
        tester.getTopLeft(find.text('Податки')).dy,
        lessThan(tester.getTopLeft(find.text('Прогулянка')).dy),
      );

      // «Податки» → «як вийде», «Прогулянка» → «обов'язково».
      Future<void> setPriority(String title, int p) async {
        await tester.tap(find.text(title));
        await settle(tester);
        expect(find.text('Важливість'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('priority-chip-$p')));
        await settle(tester);
        expect(
          tester
              .widget<ChoiceChip>(find.byKey(ValueKey('priority-chip-$p')))
              .selected,
          isTrue,
        );
        await tester.scrollUntilVisible(
          find.widgetWithText(FilledButton, 'Зберегти'),
          200,
          scrollable: find.byType(Scrollable).last,
        );
        await tester.tap(find.widgetWithText(FilledButton, 'Зберегти'));
        await settle(tester);
      }

      await setPriority('Податки', TodoPriority.could);
      await setPriority('Прогулянка', TodoPriority.must);
      expect(stripe('Прогулянка'), priorityColor(TodoPriority.must));
      expect(stripe('Податки'), priorityColor(TodoPriority.could));
      // Тепер «обов'язкова» вище, хоч і без часу.
      expect(
        tester.getTopLeft(find.text('Прогулянка')).dy,
        lessThan(tester.getTopLeft(find.text('Податки')).dy),
      );
      final saved = {
        for (final t in (await tester.runAsync(() => db.watchTodos().first))!)
          t.title: t.priority,
      };
      expect(saved, {
        'Прогулянка': TodoPriority.must,
        'Податки': TodoPriority.could,
      });
      await closeDb(tester, db);
    },
  );

  testWidgets('Видалити всі дані: потрібне слово ВИДАЛИТИ, далі — вітання', (
    tester,
  ) async {
    final db = await pumpApp(tester);
    await addRaw(tester, db, EntryType.expense, 1000, 'EUR', 'exp-fun');
    await tester.tap(find.byTooltip('Налаштування'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('Видалити всі дані'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pump();
    await tester.tap(find.text('Видалити всі дані'));
    await settle(tester);

    final button = find.widgetWithText(TextButton, 'Видалити все');
    expect(tester.widget<TextButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'видалити');
    await tester.pump();
    expect(tester.widget<TextButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await settle(tester);
    await settle(tester);

    expect(find.text('Вітаю в MyManager'), findsOneWidget);
    expect(await tester.runAsync(() => db.countEntries()), 0);
    await closeDb(tester, db);
  });
}

class _FakeBackupFiles implements BackupFiles {
  Uint8List? saved;
  String? savedName;
  Uint8List? toPick;

  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    savedName = fileName;
    saved = bytes;
    return true;
  }

  @override
  Future<void> share(String fileName, Uint8List bytes) async {}

  @override
  Future<Uint8List?> pick() async => toPick;
}

class _FakeBiometrics implements Biometrics {
  bool result = true;
  int calls = 0;

  @override
  Future<bool> available() async => true;

  @override
  Future<bool> authenticate() async {
    calls++;
    return result;
  }
}
