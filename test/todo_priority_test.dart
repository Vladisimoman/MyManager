import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/todo/todo_logic.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 26: важливість справ — «обов'язково», «бажано», «як вийде».
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  DateTime d(int m, int day) => DateTime(2026, m, day);
  final now = DateTime(2026, 10, 28, 9);

  Future<TodoGroups> groups() async => groupTodos(
    await db.watchTodos().first,
    now,
    completions: await db.watchTodoCompletions().first,
  );
  List<String> titles(List<TodoItem> l) => [for (final i in l) i.todo.title];

  test('за замовчуванням — «бажано»; ключова дата — без важливості', () async {
    final a = await db.saveTodo(title: 'А');
    final k = await db.saveTodo(
      title: 'ДН',
      dueDate: DateTime(1990, 3, 1),
      keyType: 'birthday',
      priority: TodoPriority.must,
    );
    final all = {for (final t in await db.watchTodos().first) t.id: t};
    expect(all[a]!.priority, TodoPriority.should);
    expect(all[k]!.priority, TodoPriority.should);

    await db.saveTodo(id: a, title: 'А', priority: TodoPriority.could);
    expect(
      (await db.watchTodos().first).firstWhere((t) => t.id == a).priority,
      TodoPriority.could,
    );
  });

  test('«Сьогодні»: спершу обов\'язково, далі бажано, як вийде; усередині — за часом', () async {
    await db.saveTodo(
      title: 'Як вийде 8:00',
      dueDate: d(10, 28),
      dueMinutes: 480,
      priority: TodoPriority.could,
    );
    await db.saveTodo(
      title: 'Бажано 9:00',
      dueDate: d(10, 28),
      dueMinutes: 540,
    );
    await db.saveTodo(
      title: 'Обов\'язково без часу',
      dueDate: d(10, 28),
      priority: TodoPriority.must,
    );
    await db.saveTodo(
      title: 'Обов\'язково 10:00',
      dueDate: d(10, 28),
      dueMinutes: 600,
      priority: TodoPriority.must,
    );
    await db.saveTodo(
      title: 'Бажано 7:00',
      dueDate: d(10, 28),
      dueMinutes: 420,
    );
    expect(titles((await groups()).today), [
      'Обов\'язково 10:00',
      'Обов\'язково без часу',
      'Бажано 7:00',
      'Бажано 9:00',
      'Як вийде 8:00',
    ]);
  });

  test('«Прострочені» й «Без дати» — за важливістю', () async {
    await db.saveTodo(title: 'Старе бажане', dueDate: d(10, 20));
    await db.saveTodo(
      title: 'Вчорашнє обов\'язкове',
      dueDate: d(10, 27),
      priority: TodoPriority.must,
    );
    await db.saveTodo(
      title: 'Як вийде',
      dueDate: d(10, 25),
      priority: TodoPriority.could,
    );
    await db.saveTodo(title: 'Без дати бажано');
    await db.saveTodo(title: 'Без дати як вийде', priority: TodoPriority.could);
    await db.saveTodo(
      title: 'Без дати обов\'язково',
      priority: TodoPriority.must,
    );
    final g = await groups();
    expect(titles(g.overdue), [
      'Вчорашнє обов\'язкове',
      'Старе бажане',
      'Як вийде',
    ]);
    expect(titles(g.noDate), [
      'Без дати обов\'язково',
      'Без дати бажано',
      'Без дати як вийде',
    ]);
  });

  test('«Далі»: по днях, у межах дня — за важливістю', () async {
    await db.saveTodo(
      title: '30 як вийде',
      dueDate: d(10, 30),
      priority: TodoPriority.could,
    );
    await db.saveTodo(
      title: '30 обов\'язково',
      dueDate: d(10, 30),
      priority: TodoPriority.must,
    );
    await db.saveTodo(
      title: '29 як вийде',
      dueDate: d(10, 29),
      priority: TodoPriority.could,
    );
    await db.saveTodo(title: '31 бажано', dueDate: d(10, 31));
    expect(titles((await groups()).planned), [
      '29 як вийде',
      '30 обов\'язково',
      '30 як вийде',
      '31 бажано',
    ]);
  });

  test('календар: у дні відкриті — за важливістю', () async {
    await db.saveTodo(
      title: 'Як вийде',
      dueDate: d(10, 30),
      dueMinutes: 480,
      priority: TodoPriority.could,
    );
    await db.saveTodo(
      title: 'Обов\'язково',
      dueDate: d(10, 30),
      dueMinutes: 900,
      priority: TodoPriority.must,
    );
    await db.saveTodo(title: 'Бажано', dueDate: d(10, 30));
    final cal = agendaBetween(
      await db.watchTodos().first,
      d(10, 30),
      d(10, 30),
      now,
      completions: await db.watchTodoCompletions().first,
    );
    expect(titles(cal[d(10, 30)]!.todos), [
      'Обов\'язково',
      'Бажано',
      'Як вийде',
    ]);
  });

  test(
    'синхронізація: важливість переходить; старий файл — «бажано»',
    () async {
      await db.saveTodo(title: 'Важливе', priority: TodoPriority.must);
      final json = jsonDecode(
        (await db.exportSnapshot()).encode(),
      ) as Map<String, dynamic>;
      expect(json['version'], FinanceSnapshot.formatVersion);
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await other.mergeSnapshot(FinanceSnapshot.decode(jsonEncode(json)));
      expect(
        (await other.watchTodos().first).single.priority,
        TodoPriority.must,
      );

      final todo = (json['todos'] as List).single as Map;
      todo.remove('priority');
      json['version'] = 13;
      final third = AppDatabase(NativeDatabase.memory());
      addTearDown(third.close);
      await third.mergeSnapshot(FinanceSnapshot.decode(jsonEncode(json)));
      expect(
        (await third.watchTodos().first).single.priority,
        TodoPriority.should,
      );
    },
  );

  test('оновлення бази з версії 15: справи лишаються «бажаними»', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/v15.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await old.saveTodo(title: 'Стара', dueDate: d(10, 28));
    await old.customStatement('ALTER TABLE todos DROP COLUMN priority');
    await old.customStatement('PRAGMA user_version = 15');
    await old.close();

    final db16 = AppDatabase(NativeDatabase(file));
    final t = (await db16.watchTodos().first).single;
    expect((t.title, t.priority), ('Стара', TodoPriority.should));
    await db16.close();
  });
}
