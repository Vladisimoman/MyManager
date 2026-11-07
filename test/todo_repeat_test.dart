import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/todo/todo_logic.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 17: повторювані справи й ключові дати.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  // «Виконано» ставиться в той самий «сьогодні», що й у тестах.
  setUp(
    () =>
        db = AppDatabase(NativeDatabase.memory())
          ..clock = () => DateTime(2026, 10, 28, 12),
  );
  tearDown(() => db.close());

  DateTime d(int m, int day, [int y = 2026]) => DateTime(y, m, day);
  final now = DateTime(2026, 10, 28, 12); // середа

  Future<Todo> todo(String id) async =>
      (await db.watchTodos().first).firstWhere((t) => t.id == id);
  Future<TodoGroups> groups([DateTime? at]) async => groupTodos(
    await db.watchTodos().first,
    at ?? now,
    completions: await db.watchTodoCompletions().first,
  );

  List<DateTime> occ(Todo t, DateTime from, DateTime to) =>
      occurrencesBetween(t, from, to);

  test('щодня й кожні 3 дні', () async {
    final a = await todo(
      await db.saveTodo(
        title: 'Зарядка',
        dueDate: d(10, 26),
        repeat: TodoRepeat.day,
      ),
    );
    expect(occ(a, d(10, 20), d(10, 29)), [
      d(10, 26),
      d(10, 27),
      d(10, 28),
      d(10, 29),
    ]);
    final b = await todo(
      await db.saveTodo(
        title: 'Полити квіти',
        dueDate: d(10, 20),
        repeat: TodoRepeat.day,
        repeatEvery: 3,
      ),
    );
    expect(occ(b, d(10, 20), d(10, 31)), [
      d(10, 20),
      d(10, 23),
      d(10, 26),
      d(10, 29),
    ]);
    expect(repeatText(b), 'кожні 3 дні');
    expect(repeatText(a), 'щодня');
  });

  test('щотижня в пн/ср/пт і кожні 2 тижні в сб; через перехід часу', () async {
    final a = await todo(
      await db.saveTodo(
        title: 'Спортзал',
        dueDate: d(10, 21),
        repeat: TodoRepeat.week,
        weekdays: [5, 1, 3],
      ),
    );
    expect(occ(a, d(10, 21), d(11, 2)), [
      d(10, 21),
      d(10, 23),
      d(10, 26),
      d(10, 28),
      d(10, 30),
      d(11, 2),
    ]);
    expect(repeatText(a), 'щотижня: пн, ср, пт');
    final b = await todo(
      await db.saveTodo(
        title: 'Прибирання',
        dueDate: d(10, 17),
        repeat: TodoRepeat.week,
        repeatEvery: 2,
        weekdays: [6],
      ),
    );
    expect(occ(b, d(10, 1), d(11, 30)), [
      d(10, 17),
      d(10, 31),
      d(11, 14),
      d(11, 28),
    ]);
  });

  test('щомісяця 31-го, щороку 29 лютого, до дати', () async {
    final a = await todo(
      await db.saveTodo(
        title: 'Оренда',
        dueDate: d(1, 31),
        repeat: TodoRepeat.month,
      ),
    );
    expect(occ(a, d(1, 1), d(5, 31)), [
      d(1, 31),
      d(2, 28),
      d(3, 31),
      d(4, 30),
      d(5, 31),
    ]);
    final b = await todo(
      await db.saveTodo(
        title: 'Страховка',
        dueDate: DateTime(2028, 2, 29),
        repeat: TodoRepeat.year,
      ),
    );
    expect(occ(b, DateTime(2028), DateTime(2032, 12)), [
      DateTime(2028, 2, 29),
      DateTime(2029, 2, 28),
      DateTime(2030, 2, 28),
      DateTime(2031, 2, 28),
      DateTime(2032, 2, 29),
    ]);
    final c = await todo(
      await db.saveTodo(
        title: 'Курс',
        dueDate: d(10, 1),
        repeat: TodoRepeat.week,
        repeatUntil: d(10, 20),
      ),
    );
    expect(occ(c, d(10, 1), d(12, 31)), [d(10, 1), d(10, 8), d(10, 15)]);
    expect(nextOccurrenceFrom(c, d(10, 21)), isNull);
  });

  test('вкладки: сьогоднішній повтор, наступний — у «Далі», виконання одного повтору', () async {
    final id = await db.saveTodo(
      title: 'Зарядка',
      dueDate: d(10, 20),
      repeat: TodoRepeat.day,
    );
    var g = await groups();
    expect(g.today.single.date, d(10, 28));
    expect(g.planned.single.date, d(10, 29));
    expect(g.overdue, isEmpty); // щоденні пропуски не накопичуються

    await db.setOccurrenceDone(id, d(10, 28), true);
    g = await groups();
    expect(g.today, isEmpty);
    expect(g.history.single.item.date, d(10, 28));
    expect(g.planned.single.date, d(10, 29)); // серія триває
    // Наступного дня — новий повтор.
    expect(
      (await groups(DateTime(2026, 10, 29, 9))).today.single.date,
      d(10, 29),
    );
    // Скасувати виконання.
    await db.setOccurrenceDone(id, d(10, 28), false);
    expect((await groups()).today.length, 1);
  });

  test(
    'пропущений щомісячний — прострочений, доки не настав наступний',
    () async {
      final id = await db.saveTodo(
        title: 'Рахунок',
        dueDate: d(9, 25),
        repeat: TodoRepeat.month,
      );
      var g = await groups();
      expect(g.overdue.single.date, d(10, 25));
      expect(g.planned.single.date, d(11, 25));
      expect(
        todayLeft(
          await db.watchTodos().first,
          now,
          completions: await db.watchTodoCompletions().first,
        ),
        1,
      );
      await db.setOccurrenceDone(id, d(10, 25), true);
      g = await groups();
      expect(g.overdue, isEmpty);
    },
  );

  test('ключові дати: роки, нагадування за N днів, не справи', () async {
    await db.saveTodo(
      title: 'ДН мами',
      dueDate: DateTime(1971, 11, 1),
      keyType: 'birthday',
      countYears: true,
      remindDays: 7,
    );
    await db.saveTodo(
      title: 'Річниця',
      dueDate: DateTime(2016, 12, 20),
      keyType: 'anniversary',
      countYears: true,
      remindDays: 3,
    );
    await db.saveTodo(
      title: 'Новий рік',
      dueDate: DateTime(2026, 1, 1),
      keyType: 'holiday',
    );
    final g = await groups();
    expect(g.keyDates.single.todo.title, 'ДН мами');
    expect(g.keyDates.single.daysLeft, 4);
    expect(yearsText(g.keyDates.single), 'виповнюється 55');
    expect(g.today, isEmpty);
    expect(g.planned, isEmpty);

    final all = upcomingKeyDates(await db.watchTodos().first, now);
    expect(all.map((k) => k.todo.title), ['ДН мами', 'Річниця', 'Новий рік']);
    expect(yearsText(all[1]), '10 років');
    expect(all[2].date, DateTime(2027, 1, 1));
    expect(yearsText(all[2]), '');
    expect(daysLeftText(4), 'через 4 дні');
    expect(daysLeftText(65), 'через 65 днів');

    // У сам день — «сьогодні».
    final day = groupTodos(await db.watchTodos().first, DateTime(2026, 11, 1));
    expect(day.keyDates.single.daysLeft, 0);
  });

  test('синхронізація повторів і виконань; файл етапу 16 читається', () async {
    final id = await db.saveTodo(
      title: 'Зарядка',
      dueDate: d(10, 20),
      repeat: TodoRepeat.week,
      weekdays: [1, 3],
    );
    await db.setOccurrenceDone(id, d(10, 28), true);
    final text = (await db.exportSnapshot()).encode();
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.mergeSnapshot(FinanceSnapshot.decode(text));
    final t = (await other.watchTodos().first).single;
    expect(t.repeatUnit, TodoRepeat.week);
    expect(t.repeatWeekdays, '1,3');
    expect((await other.watchTodoCompletions().first).single.date, d(10, 28));
    // Той самий повтор на двох телефонах — один запис.
    await other.setOccurrenceDone(id, d(10, 28), true);
    await db.mergeSnapshot(
      FinanceSnapshot.decode((await other.exportSnapshot()).encode()),
    );
    expect((await db.watchTodoCompletions().first).length, 1);

    // Старий формат (етап 16): без полів повторення.
    final old = text.replaceAll(RegExp(r',\s*"repeatUnit": "week"'), '');
    final third = AppDatabase(NativeDatabase.memory());
    addTearDown(third.close);
    await third.mergeSnapshot(FinanceSnapshot.decode(old));
    expect((await third.watchTodos().first).single.repeatUnit, TodoRepeat.none);
  });

  test(
    'оновлення з версії 11 (етап 16): справи лишаються, нові колонки є',
    () async {
      final dir = await Directory.systemTemp.createTemp('mymanager');
      final file = File('${dir.path}/v11.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      await old.saveTodo(title: 'Стара справа', dueDate: d(10, 28));
      await old.customStatement('DROP TABLE todo_completions');
      for (final c in [
        'repeat_unit',
        'repeat_every',
        'repeat_weekdays',
        'repeat_until',
        'key_type',
        'count_years',
        'remind_days',
        'remind_before',
        'failed',
        'priority',
      ]) {
        await old.customStatement('ALTER TABLE todos DROP COLUMN $c');
      }
      await old.customStatement('PRAGMA user_version = 11');
      await old.close();
      final db12 = AppDatabase(NativeDatabase(file));
      final t = (await db12.watchTodos().first).single;
      expect(t.title, 'Стара справа');
      expect(t.repeatUnit, TodoRepeat.none);
      expect(t.repeatEvery, 1);
      expect(await db12.watchTodoCompletions().first, isEmpty);
      await db12.close();
      await dir.delete(recursive: true);
    },
  );

  // ---------- Етап 24: пропущені повтори й історія видаленої серії ----------

  Future<void> createdOn(String id, DateTime day) =>
      (db.update(db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(createdAt: Value(day.toUtc())),
      );
  Future<TodoGroups> groupsAll([DateTime? at]) async => groupTodos(
    [...await db.watchTodos().first, ...await db.watchDeletedSeries().first],
    at ?? now,
    completions: await db.watchTodoCompletions().first,
  );
  List<String> historyOfDay(TodoGroups g, DateTime day) => [
    for (final h in g.history)
      if (h.day == day) '${h.kind.name}${h.item.auto ? ':auto' : ''}',
  ];

  test(
    'щоденна: вчора не позначено — «не виконано» вчора, не у «Прострочених»',
    () async {
      final z = await db.saveTodo(
        title: 'Чистити зуби',
        dueDate: d(10, 20),
        repeat: TodoRepeat.day,
      );
      await createdOn(z, d(10, 20));
      db.clock = () => DateTime(2026, 10, 26, 21); // виконано того ж дня
      await db.setOccurrenceDone(z, d(10, 26), true);
      final g = await groupsAll();
      expect(g.overdue, isEmpty);
      expect(g.today.single.date, d(10, 28));
      expect(historyOfDay(g, d(10, 27)), ['missed:auto']);
      expect(historyOfDay(g, d(10, 26)), ['done']);
      // 20–25 і 27 — пропуски; 26 — виконано.
      expect(g.history.where((h) => h.item.auto).length, 7);
    },
  );

  test('пропуски — лише з дня створення і не довше за 30 днів', () async {
    final z = await db.saveTodo(
      title: 'Вода',
      dueDate: d(1, 1),
      repeat: TodoRepeat.day,
    );
    await createdOn(z, d(10, 25));
    var g = await groupsAll();
    expect(g.history.map((h) => h.day).toList(), [
      d(10, 27),
      d(10, 26),
      d(10, 25),
    ]);

    await createdOn(z, d(1, 1));
    g = await groupsAll();
    expect(g.history.length, doneHistoryDays);
    expect(g.history.last.day, d(9, 28));
  });

  test('виконано із запізненням: без дубля «не виконано»', () async {
    final z = await db.saveTodo(
      title: 'Ліки',
      dueDate: d(10, 27),
      repeat: TodoRepeat.day,
    );
    await createdOn(z, d(10, 27));
    expect(historyOfDay(await groupsAll(), d(10, 27)), ['missed:auto']);
    await db.setOccurrenceDone(z, d(10, 27), true); // сьогодні, 28-го
    final g = await groupsAll();
    expect(historyOfDay(g, d(10, 27)), ['missed']);
    expect(historyOfDay(g, d(10, 28)), ['doneLate']);
  });

  test('тижнева: останній пропуск — у «Прострочених», після наступного — «не виконано»', () async {
    final w = await db.saveTodo(
      title: 'Прибирання',
      dueDate: d(10, 24), // субота
      repeat: TodoRepeat.week,
    );
    await createdOn(w, d(10, 20));
    var g = await groupsAll();
    expect(g.overdue.single.date, d(10, 24));
    expect(g.history, isEmpty);

    g = await groupsAll(DateTime(2026, 10, 31, 12)); // настала наступна субота
    expect(g.overdue, isEmpty);
    expect(g.today.single.date, d(10, 31));
    expect(historyOfDay(g, d(10, 24)), ['missed:auto']);
  });

  test(
    'видалена серія: історія лишається до дня видалення, майбутнього немає',
    () async {
      final z = await db.saveTodo(
        title: 'Чистити зуби',
        dueDate: d(10, 20),
        repeat: TodoRepeat.day,
      );
      await createdOn(z, d(10, 20));
      db.clock = () => DateTime(2026, 10, 22, 21);
      await db.setOccurrenceDone(z, d(10, 22), true);
      db.clock = () => DateTime(2026, 10, 23, 21);
      await db.setOccurrenceFailed(z, d(10, 23), true);
      await (db.update(db.todos)..where((t) => t.id.equals(z))).write(
        TodosCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime(2026, 10, 25, 9).toUtc()),
        ),
      );
      final g = await groupsAll();
      expect(g.today, isEmpty);
      expect(g.planned, isEmpty);
      expect(g.overdue, isEmpty);
      expect(historyOfDay(g, d(10, 22)), ['done']);
      expect(historyOfDay(g, d(10, 23)), ['missed']);
      expect(historyOfDay(g, d(10, 24)), ['missed:auto']);
      expect(historyOfDay(g, d(10, 25)), isEmpty); // день видалення — ні
      expect(g.history.every((h) => h.item.seriesDeleted), isTrue);
      expect(g.history.map((h) => h.day).toSet(), {
        d(10, 20),
        d(10, 21),
        d(10, 22),
        d(10, 23),
        d(10, 24),
      });

      // Відновлення серії — знову звичайна справа.
      await db.setTodoDeleted(z, false);
      expect((await groupsAll()).today.single.date, d(10, 28));
    },
  );

  test('видалена разова справа зникає з історії, як і раніше', () async {
    final a = await db.saveTodo(title: 'Разова', dueDate: d(10, 28));
    await db.setTodoDone(a, true);
    expect((await groupsAll()).history, hasLength(1));
    await db.setTodoDeleted(a, true);
    expect((await groupsAll()).history, isEmpty);
    expect(await db.watchDeletedSeries().first, isEmpty);
  });
}
