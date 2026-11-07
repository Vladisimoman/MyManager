import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/todo/todo_logic.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 16: To-Do.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  // «Виконано» ставиться в той самий «сьогодні», що й у тестах.
  setUp(
    () =>
        db = AppDatabase(NativeDatabase.memory())
          ..clock = () => DateTime(2026, 10, 28, 14, 30),
  );
  tearDown(() => db.close());

  final now = DateTime(2026, 10, 28, 14, 30);
  DateTime d(int day) => DateTime(2026, 10, day);

  test('розкладка: прострочені, сьогодні за часом, заплановані, без дати, виконані', () async {
    await db.saveTodo(title: 'Без часу', dueDate: d(28));
    await db.saveTodo(title: 'О 9', dueDate: d(28), dueMinutes: 9 * 60);
    await db.saveTodo(title: 'О 18', dueDate: d(28), dueMinutes: 18 * 60);
    await db.saveTodo(title: 'Вчорашня', dueDate: d(27));
    await db.saveTodo(title: 'Позавчорашня', dueDate: d(26));
    await db.saveTodo(title: 'Завтра', dueDate: d(29));
    await db.saveTodo(
      title: 'Наступний тиждень',
      dueDate: DateTime(2026, 11, 4),
    );
    await db.saveTodo(title: 'Колись');
    final doneId = await db.saveTodo(title: 'Зроблено', dueDate: d(20));
    await db.setTodoDone(doneId, true);
    final delId = await db.saveTodo(title: 'Видалено');
    await db.setTodoDeleted(delId, true);

    final g = groupTodos(await db.watchTodos().first, now);
    expect(g.overdue.map((t) => t.todo.title), ['Позавчорашня', 'Вчорашня']);
    expect(g.today.map((t) => t.todo.title), ['О 9', 'О 18', 'Без часу']);
    expect(g.planned.map((t) => t.todo.title), ['Завтра', 'Наступний тиждень']);
    expect(g.noDate.map((t) => t.todo.title), ['Колись']);
    // Призначено на 20-те, виконано 28-го: два записи в «Завершених».
    expect(g.history.map((h) => (h.day, h.kind, h.item.todo.title)), [
      (d(28), HistoryKind.doneLate, 'Зроблено'),
      (d(20), HistoryKind.missed, 'Зроблено'),
    ]);
    expect(g.history.first.item.lateFrom, d(20));
    expect(g.history.last.item.lateDoneOn, d(28));
    expect(todayLeft(await db.watchTodos().first, now), 5);

    await db.setTodoDone(doneId, false);
    expect(groupTodos(await db.watchTodos().first, now).overdue.length, 3);
  });

  test('без дати — час не зберігається; редагування', () async {
    final id = await db.saveTodo(title: ' Купити квитки ', dueMinutes: 600);
    var t = (await db.watchTodos().first).single;
    expect(t.title, 'Купити квитки');
    expect(t.dueMinutes, isNull);
    await db.saveTodo(
      id: id,
      title: 'Купити квитки',
      dueDate: d(30),
      dueMinutes: 600,
      note: 'на потяг',
    );
    t = (await db.watchTodos().first).single;
    expect(t.dueDate, d(30));
    expect(t.dueMinutes, 600);
    expect(t.note, 'на потяг');
    expect(minutesLabel(600), '10:00');
    expect(minutesLabel(9 * 60 + 5), '09:05');
  });

  test('синхронізація й очищення', () async {
    final id = await db.saveTodo(
      title: 'Зателефонувати',
      dueDate: d(29),
      dueMinutes: 750,
    );
    await db.setTodoDone(id, true);
    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.mergeSnapshot(
      FinanceSnapshot.decode((await db.exportSnapshot()).encode()),
    );
    final t = (await other.watchTodos().first).single;
    expect(t.title, 'Зателефонувати');
    expect(t.dueDate, d(29));
    expect(t.dueMinutes, 750);
    expect(t.done, isTrue);
    await db.wipeAllData(resetId: 'x');
    expect(await db.watchTodos().first, isEmpty);
  });

  test('оновлення з версії 10 (етап 15): таблиця справ з\'являється', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v10.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await old.saveActivity(
      categoryId: 'act-work',
      start: DateTime(2026, 10, 1, 9),
      end: DateTime(2026, 10, 1, 10),
    );
    await old.customStatement('DROP TABLE todos');
    await old.customStatement('PRAGMA user_version = 10');
    await old.close();
    final db11 = AppDatabase(NativeDatabase(file));
    expect((await db11.watchActivities().first).length, 1);
    expect(await db11.watchTodos().first, isEmpty);
    await db11.close();
    await dir.delete(recursive: true);
  });

  test(
    '«не виконано»: закриває справу, у «Завершених» — у день призначення',
    () async {
      final late = await db.saveTodo(title: 'Прострочена', dueDate: d(26));
      final early = await db.saveTodo(title: 'На п\'ятницю', dueDate: d(30));
      final open = await db.saveTodo(title: 'Ще чекає', dueDate: d(27));
      await db.setTodoFailed(late, true);
      await db.setTodoFailed(early, true);
      var g = groupTodos(await db.watchTodos().first, now);
      expect(g.overdue.map((t) => t.todo.title), ['Ще чекає']);
      expect(g.planned, isEmpty);
      expect(g.history.map((h) => (h.day, h.kind, h.item.todo.title)), [
        // закрито раніше строку — у день закриття
        (d(28), HistoryKind.missed, 'На п\'ятницю'),
        (d(26), HistoryKind.missed, 'Прострочена'),
      ]);
      expect(g.history.every((h) => h.item.failed && h.item.missed), isTrue);
      final t = (await db.watchTodos().first).firstWhere((t) => t.id == late);
      expect((t.failed, t.done, t.doneAt), (true, false, now));

      // Відкрити знову — знову прострочена; «виконано» знімає «не виконано».
      await db.setTodoFailed(late, false);
      await db.setTodoDone(open, true);
      await db.setTodoFailed(open, true);
      await db.setTodoDone(open, true);
      g = groupTodos(await db.watchTodos().first, now);
      expect(g.overdue.map((t) => t.todo.title), ['Прострочена']);
      final o = (await db.watchTodos().first).firstWhere((t) => t.id == open);
      expect((o.done, o.failed), (true, false));
      expect(
        g.history.where((h) => h.item.todo.id == open).map((h) => h.kind),
        [HistoryKind.doneLate, HistoryKind.missed],
      );
    },
  );

  test('повтор «не виконано»: лише цей раз, серія триває', () async {
    final id = await db.saveTodo(
      title: 'Зарядка',
      dueDate: d(26),
      repeat: TodoRepeat.day,
    );
    await db.setOccurrenceFailed(id, d(28), true);
    await db.setOccurrenceDone(id, d(27), true); // виконано 28-го — запізнення
    final g = groupTodos(
      await db.watchTodos().first,
      now,
      completions: await db.watchTodoCompletions().first,
    );
    expect(g.today, isEmpty);
    expect(g.overdue, isEmpty); // останній пропущений (28) закрито
    expect(g.planned.single.date, d(29));
    expect(g.history.map((h) => (h.day, h.kind, h.item.date)), [
      (d(28), HistoryKind.missed, d(28)), // «не виконано»
      (d(28), HistoryKind.doneLate, d(27)),
      (d(27), HistoryKind.missed, d(27)),
    ]);
    // Знову відкрити повтор — він знову «на сьогодні».
    await db.setOccurrenceFailed(id, d(28), false);
    final g2 = groupTodos(
      await db.watchTodos().first,
      now,
      completions: await db.watchTodoCompletions().first,
    );
    expect(g2.today.single.date, d(28));
  });

  test('історія — лише за 30 днів; виконана вчасно — один запис', () async {
    final old = await db.saveTodo(title: 'Давня', dueDate: d(1));
    db.clock = () => DateTime(2026, 9, 1, 10);
    await db.setTodoDone(old, true);
    db.clock = () => now;
    final ok = await db.saveTodo(title: 'Вчасно', dueDate: d(28));
    await db.setTodoDone(ok, true);
    final g = groupTodos(await db.watchTodos().first, now);
    expect(g.history.map((h) => (h.day, h.kind, h.item.todo.title)), [
      (d(28), HistoryKind.done, 'Вчасно'),
    ]);
  });
}
