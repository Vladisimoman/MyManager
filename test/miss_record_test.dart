import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/todo/miss_recorder.dart';
import 'package:my_manager/features/todo/todo_logic.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 25: пропуски повторюваних справ зберігаються в базі.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(
    () =>
        db = AppDatabase(NativeDatabase.memory())
          ..clock = () => DateTime(2026, 10, 28, 12),
  );
  tearDown(() => db.close());

  DateTime d(int m, int day) => DateTime(2026, m, day);
  final now = DateTime(2026, 10, 28, 12); // середа

  Future<void> createdOn(AppDatabase db, String id, DateTime day) =>
      (db.update(db.todos)..where((t) => t.id.equals(id))).write(
        TodosCompanion(createdAt: Value(day.toUtc())),
      );
  Future<String> daily(AppDatabase db, String title, DateTime from) async {
    final id = await db.saveTodo(
      title: title,
      dueDate: from,
      repeat: TodoRepeat.day,
    );
    await createdOn(db, id, from);
    return id;
  }

  Future<Map<String, TodoCompletion>> records(AppDatabase db) async => {
    for (final c in await db.allTodoCompletions()) c.id: c,
  };
  Future<TodoGroups> groups(AppDatabase db, [DateTime? at]) async => groupTodos(
    [...await db.watchTodos().first, ...await db.watchDeletedSeries().first],
    at ?? now,
    completions: await db.watchTodoCompletions().first,
  );

  test(
    'записує минулі пропуски з дня створення; сьогодні й позначені — ні',
    () async {
      final z = await daily(db, 'Зуби', d(10, 24));
      db.clock = () => DateTime(2026, 10, 25, 21);
      await db.setOccurrenceDone(z, d(10, 25), true);
      db.clock = () => now;

      expect(await recordMissedRepeats(db, now), 3); // 24, 26, 27
      final r = await records(db);
      expect(r.keys.toSet(), {
        '$z:2026-10-24',
        '$z:2026-10-25',
        '$z:2026-10-26',
        '$z:2026-10-27',
      });
      final miss = r['$z:2026-10-27']!;
      expect((miss.failed, miss.isAuto, miss.deleted), (true, true, false));
      expect(
        miss.updatedAt.isAtSameMomentAs(AppDatabase.autoMissUpdatedAt),
        isTrue,
      );
      expect(r['$z:2026-10-25']!.isAuto, isFalse);

      // Повторний запуск нічого не дублює.
      expect(await recordMissedRepeats(db, now), 0);
      // Наступного дня — лише сьогоднішній (28-й) пропуск.
      expect(await recordMissedRepeats(db, DateTime(2026, 10, 29, 9)), 1);
    },
  );

  test(
    'на екрані — так само, як до запису; кнопка «пізніше» лишається',
    () async {
      final z = await daily(db, 'Зуби', d(10, 26));
      final before = (await groups(db)).history
          .map((h) => (h.day, h.kind, h.item.auto))
          .toList();
      await recordMissedRepeats(db, now);
      final after = (await groups(db)).history
          .map((h) => (h.day, h.kind, h.item.auto))
          .toList();
      expect(after, before);
      expect(after, [
        (d(10, 27), HistoryKind.missed, true),
        (d(10, 26), HistoryKind.missed, true),
      ]);

      // «Виконано пізніше» — звичайне пізнє виконання.
      await db.setOccurrenceDone(z, d(10, 27), true);
      final c = (await records(db))['$z:2026-10-27']!;
      expect((c.failed, c.isAuto), (false, false));
      final g = await groups(db);
      expect(
        g.history.where((h) => h.day == d(10, 28)).single.kind,
        HistoryKind.doneLate,
      );
    },
  );

  test('збережений пропуск не залежить від зміни правила повтору', () async {
    final z = await daily(db, 'Спорт', d(10, 20));
    await recordMissedRepeats(db, now);
    // Тепер лише по понеділках (26-го).
    await db.saveTodo(
      id: z,
      title: 'Спорт',
      dueDate: d(10, 19),
      repeat: TodoRepeat.week,
      weekdays: [1],
    );
    final days = (await groups(db)).history.map((h) => h.day).toSet();
    expect(days, {for (var i = 20; i <= 27; i++) d(10, i)});
  });

  test(
    '«відкрито знову» й останній тижневий у «Прострочених» — не записуються',
    () async {
      final z = await daily(db, 'Зуби', d(10, 26));
      db.clock = () => DateTime(2026, 10, 26, 21);
      await db.setOccurrenceFailed(z, d(10, 26), true);
      await db.setOccurrenceFailed(z, d(10, 26), false); // відкрито знову
      final w = await db.saveTodo(
        title: 'Прибирання',
        dueDate: d(10, 24), // субота
        repeat: TodoRepeat.week,
      );
      await createdOn(db, w, d(10, 20));

      expect(await recordMissedRepeats(db, now), 1); // лише 27-ме
      final r = await records(db);
      expect(r['$z:2026-10-26']!.deleted, isTrue);
      expect(r.containsKey('$w:2026-10-24'), isFalse);
      // Коли настала наступна субота — записується.
      expect(
        await recordMissedRepeats(db, DateTime(2026, 10, 31, 9)),
        greaterThan(0),
      );
      expect((await records(db))['$w:2026-10-24']!.isAuto, isTrue);
    },
  );

  test(
    'видалена серія — лише до дня видалення; ключові дати й разові — ні',
    () async {
      final z = await daily(db, 'Зуби', d(10, 20));
      await (db.update(db.todos)..where((t) => t.id.equals(z))).write(
        TodosCompanion(
          deleted: const Value(true),
          updatedAt: Value(DateTime(2026, 10, 23, 9).toUtc()),
        ),
      );
      await db.saveTodo(title: 'Разова', dueDate: d(10, 20));
      await db.saveTodo(
        title: 'ДН',
        dueDate: DateTime(1990, 10, 21),
        keyType: 'birthday',
      );
      expect(await recordMissedRepeats(db, now), 3); // 20, 21, 22
    },
  );

  test(
    'синхронізація: справжня позначка перемагає автоматичний пропуск',
    () async {
      final phone = AppDatabase(NativeDatabase.memory());
      addTearDown(phone.close);
      final z = await daily(db, 'Зуби', d(10, 26));
      await phone.mergeSnapshot(await db.exportSnapshot());

      // Телефон (без інтернету) позначив 27-ме виконаним того ж дня,
      // браузер наступного дня записав пропуск.
      phone.clock = () => DateTime(2026, 10, 27, 22);
      await phone.setOccurrenceDone(z, d(10, 27), true);
      await recordMissedRepeats(db, now);
      expect((await records(db))['$z:2026-10-27']!.isAuto, isTrue);

      // Злиття в обидва боки — виконання лишається.
      await db.mergeSnapshot(await phone.exportSnapshot());
      await phone.mergeSnapshot(await db.exportSnapshot());
      for (final x in [db, phone]) {
        final c = (await records(x))['$z:2026-10-27']!;
        expect((c.failed, c.isAuto, c.deleted), (false, false, false));
      }
      // Пропуск 26-го приходить на телефон як автоматичний.
      expect((await records(phone))['$z:2026-10-26']!.isAuto, isTrue);
    },
  );

  test(
    'знімок: поле «auto» туди й назад; старий файл (версія 12) читається',
    () async {
      final z = await daily(db, 'Зуби', d(10, 27));
      await recordMissedRepeats(db, now);
      final json = jsonDecode(
        (await db.exportSnapshot()).encode(),
      ) as Map<String, dynamic>;
      expect(json['version'], FinanceSnapshot.formatVersion);
      final c = (json['todoCompletions'] as List).single as Map;
      expect(c['auto'], isTrue);

      c.remove('auto');
      json['version'] = 12;
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await other.mergeSnapshot(FinanceSnapshot.decode(jsonEncode(json)));
      final r = (await records(other))['$z:2026-10-27']!;
      expect((r.failed, r.isAuto), (true, false));
    },
  );

  test(
    'оновлення бази з версії 14: записи лишаються, нове поле — «ні»',
    () async {
      final dir = await Directory.systemTemp.createTemp('mymanager');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/v14.sqlite');
      final old = AppDatabase(NativeDatabase(file))
        ..clock = () => DateTime(2026, 10, 27, 21);
      final z = await old.saveTodo(
        title: 'Зуби',
        dueDate: d(10, 27),
        repeat: TodoRepeat.day,
      );
      await old.setOccurrenceFailed(z, d(10, 27), true);
      await old.customStatement(
        'ALTER TABLE todo_completions DROP COLUMN is_auto',
      );
      await old.customStatement('ALTER TABLE todos DROP COLUMN priority');
      await old.customStatement('PRAGMA user_version = 14');
      await old.close();

      final db15 = AppDatabase(NativeDatabase(file));
      final c = (await db15.allTodoCompletions()).single;
      expect((c.failed, c.isAuto), (true, false));
      await db15.close();
    },
  );
}
