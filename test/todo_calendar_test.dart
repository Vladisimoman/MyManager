import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/todo/todo_logic.dart';

/// Етап 18: календар — сітка місяця й що припадає на кожен день.
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

  Future<Map<DateTime, DayAgenda>> agenda(DateTime from, DateTime to) async =>
      agendaBetween(
        [
          ...await db.watchTodos().first,
          ...await db.watchDeletedSeries().first,
        ],
        from,
        to,
        now,
        completions: await db.watchTodoCompletions().first,
      );

  // Дата створення / видалення в минулому (у базі їх ставить реальний годинник).
  Future<void> createdOn(String id, DateTime day) =>
      (db.update(db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(createdAt: Value(day.toUtc())),
      );
  Future<void> deletedOn(String id, DateTime day) =>
      (db.update(db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(
          deleted: const Value(true),
          updatedAt: Value(day.add(const Duration(hours: 12)).toUtc()),
        ),
      );

  test('сітка місяця: з понеділка до неділі, повні тижні', () {
    final oct = monthGrid(d(10, 1));
    expect(oct.first, d(9, 28)); // 1 жовтня 2026 — четвер
    expect(oct.last, d(11, 1));
    expect(oct.length, 35);
    final feb = monthGrid(d(2, 1, 2027)); // 1 лютого 2027 — понеділок
    expect(feb.first, d(2, 1, 2027));
    expect(feb.last, d(2, 28, 2027));
    expect(feb.length, 28);
    final mar = monthGrid(d(3, 1, 2026)); // неділя → 6 тижнів
    expect(mar.length, 42);
    expect(mar.first.weekday, DateTime.monday);
    expect(mar.last.weekday, DateTime.sunday);
  });

  test('справи, повтори з виконанням і ключові дати по днях', () async {
    await db.saveTodo(title: 'Купити подарунок', dueDate: d(10, 30));
    final done = await db.saveTodo(title: 'Банк', dueDate: d(10, 27));
    await db.setTodoDone(done, true);
    await db.saveTodo(title: 'Без дати');
    final gym = await db.saveTodo(
      title: 'Спортзал',
      dueDate: d(10, 26),
      dueMinutes: 18 * 60,
      repeat: TodoRepeat.week,
      weekdays: [1, 3, 5],
    );
    await db.setOccurrenceDone(gym, d(10, 26), true);
    await db.saveTodo(
      title: 'ДН мами',
      dueDate: d(11, 1, 1970),
      keyType: 'birthday',
      countYears: true,
    );
    final cal = await agenda(d(10, 26), d(11, 1));

    // Понеділок: повтор виконали лише в середу — тут «не виконано».
    final mon = cal[d(10, 26)]!.todos.single;
    expect(mon.missed, isTrue);
    expect(mon.lateDoneOn, d(10, 28));
    expect(cal[d(10, 26)]!.openCount, 0);
    expect(cal[d(10, 26)]!.missedCount, 1);
    // Вівторок: «Банк» теж виконано в середу.
    expect(cal[d(10, 27)]!.todos.single.todo.title, 'Банк');
    expect(cal[d(10, 27)]!.todos.single.lateDoneOn, d(10, 28));
    // Середа: сьогоднішній повтор чекає; обидві — «виконано із запізненням».
    final wed = cal[d(10, 28)]!;
    expect(wed.openCount, 1);
    expect(wed.todos.map((t) => (t.todo.title, t.open, t.lateFrom)), [
      ('Спортзал', true, null),
      ('Спортзал', false, d(10, 26)),
      ('Банк', false, d(10, 27)),
    ]);
    // П'ятниця: повтор і разова справа; без часу — після 18:00.
    expect(cal[d(10, 30)]!.todos.map((t) => t.todo.title), [
      'Спортзал',
      'Купити подарунок',
    ]);
    // Неділя: день народження, рахуємо роки.
    final k = cal[d(11, 1)]!.keyDates.single;
    expect(k.todo.title, 'ДН мами');
    expect(k.daysLeft, 4);
    expect(yearsText(k), 'виповнюється 56');
    // Четвер і субота — порожні; справа без дати в календар не потрапляє.
    expect(cal[d(10, 29)], isNull);
    expect(
      cal.values.expand((a) => a.todos).where((t) => t.date == null),
      isEmpty,
    );
  });

  test('минулий день народження — «виповнилося»', () async {
    await db.saveTodo(
      title: 'ДН тата',
      dueDate: d(10, 2, 1965),
      keyType: 'birthday',
      countYears: true,
    );
    final k = (await agenda(d(10, 1), d(10, 31)))[d(10, 2)]!.keyDates.single;
    expect(k.daysLeft, -26);
    expect(yearsText(k), 'виповнилося 61');
  });

  test('видалені справи й повтори після «до» не показуються', () async {
    final a = await db.saveTodo(title: 'Старе', dueDate: d(10, 28));
    await db.setTodoDeleted(a, true);
    final c = await db.saveTodo(
      title: 'Курс',
      dueDate: d(10, 26),
      repeat: TodoRepeat.day,
      repeatUntil: d(10, 28),
    );
    await createdOn(c, d(10, 26));
    final cal = await agenda(d(10, 26), d(11, 1));
    expect(cal.keys.toList()..sort(), [d(10, 26), d(10, 27), d(10, 28)]);
    expect(cal[d(10, 28)]!.todos.single.todo.title, 'Курс');
    // Етап 24: минулі дні без позначки — «не виконано».
    expect(cal[d(10, 26)]!.todos.single.auto, isTrue);
    expect(cal[d(10, 27)]!.missedCount, 1);
    expect(cal[d(10, 27)]!.openCount, 0);
  });

  test(
    'етап 24: календар — пропуски, видалена серія, нічого до створення',
    () async {
      final z = await db.saveTodo(
        title: 'Зуби',
        dueDate: d(10, 1),
        repeat: TodoRepeat.day,
      );
      await createdOn(z, d(10, 20)); // створено 20-го, хоч старт серії 1-го
      db.clock = () => DateTime(2026, 10, 21, 21); // виконано того ж дня
      await db.setOccurrenceDone(z, d(10, 21), true);
      var cal = await agenda(d(10, 15), d(10, 30));
      expect(cal[d(10, 19)], isNull); // до створення — нічого
      expect(cal[d(10, 20)]!.todos.single.auto, isTrue);
      expect(cal[d(10, 21)]!.todos.single.done, isTrue);
      expect(cal[d(10, 28)]!.todos.single.open, isTrue); // сьогодні — чекає
      expect(cal[d(10, 29)]!.todos.single.open, isTrue);

      // Видалено 25-го: минуле лишається до 24-го, далі — нічого.
      await deletedOn(z, d(10, 25));
      cal = await agenda(d(10, 15), d(10, 30));
      expect(cal[d(10, 21)]!.todos.single.done, isTrue);
      expect(cal[d(10, 24)]!.todos.single.auto, isTrue);
      expect(cal[d(10, 24)]!.todos.single.seriesDeleted, isTrue);
      expect(cal[d(10, 25)], isNull);
      expect(cal[d(10, 28)], isNull);
    },
  );

  test(
    'етап 24: тижнева — останній пропуск ще «чекає», попередні — «не виконано»',
    () async {
      final w = await db.saveTodo(
        title: 'Прибирання',
        dueDate: d(10, 10), // субота
        repeat: TodoRepeat.week,
      );
      await createdOn(w, d(10, 1));
      final cal = await agenda(d(10, 1), d(10, 31));
      expect(cal[d(10, 10)]!.todos.single.auto, isTrue);
      expect(cal[d(10, 17)]!.todos.single.auto, isTrue);
      expect(cal[d(10, 24)]!.todos.single.open, isTrue); // ще у «Прострочених»
      expect(cal[d(10, 31)]!.todos.single.open, isTrue);
    },
  );
}
