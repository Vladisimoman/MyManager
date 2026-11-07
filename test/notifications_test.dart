import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/notifications/notification_plan.dart';
import 'package:my_manager/features/notifications/notifications.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 19: які сповіщення й коли.
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

  DateTime d(int m, int day, [int h = 0, int min = 0]) =>
      DateTime(2026, m, day, h, min);
  final now = d(10, 28, 12); // середа, полудень

  Future<List<PlannedNotification>> plan({
    DateTime? at,
    int? digest = defaultDigestMinutes,
    int days = planDays,
  }) async => planNotifications(
    todos: await db.watchTodos().first,
    completions: await db.watchTodoCompletions().first,
    now: at ?? now,
    digestMinutes: digest,
    days: days,
  );

  test(
    'нагадування: вчасно, заздалегідь, вимкнене, без часу, минуле',
    () async {
      await db.saveTodo(
        title: 'Зустріч',
        dueDate: d(10, 28),
        dueMinutes: 15 * 60,
      );
      await db.saveTodo(
        title: 'Лікар',
        dueDate: d(10, 29),
        dueMinutes: 10 * 60,
        remindBefore: 60,
      );
      await db.saveTodo(
        title: 'Тихо',
        dueDate: d(10, 29),
        dueMinutes: 11 * 60,
        remindBefore: AppDatabase.noReminder,
      );
      await db.saveTodo(title: 'Без часу', dueDate: d(10, 29));
      await db.saveTodo(
        title: 'Вранці',
        dueDate: d(10, 28),
        dueMinutes: 8 * 60,
      );
      final done = await db.saveTodo(
        title: 'Зроблено',
        dueDate: d(10, 30),
        dueMinutes: 9 * 60,
      );
      await db.setTodoDone(done, true);

      final r = (await plan(digest: null))
          .where((n) => n.kind == NotificationKind.reminder)
          .toList();
      expect(r.map((n) => n.title), ['Зустріч', 'Лікар']);
      expect(r[0].at, d(10, 28, 15));
      expect(r[0].body, 'Зараз · 15:00');
      expect(r[1].at, d(10, 29, 9));
      expect(r[1].body, 'Через 1 год · о 10:00');
      expect(r.map((n) => n.id), [1, 2]);
      // payload несе справу й дату для «Виконано».
      final p = decodePayload(r[1].payload)!;
      expect(p.date, d(10, 29));
      expect(p.title, 'Лікар');
    },
  );

  test('повторювана справа: кожен повтор на 14 днів, крім виконаних', () async {
    final gym = await db.saveTodo(
      title: 'Спортзал',
      dueDate: d(10, 26),
      dueMinutes: 18 * 60,
      repeat: TodoRepeat.week,
      weekdays: [1, 3, 5],
      remindBefore: 30,
    );
    await db.setOccurrenceDone(gym, d(10, 30), true);
    final r = await plan(digest: null);
    expect(r.map((n) => n.at), [
      d(10, 28, 17, 30),
      // 30 жовтня виконано наперед
      d(11, 2, 17, 30),
      d(11, 4, 17, 30),
      d(11, 6, 17, 30),
      d(11, 9, 17, 30),
    ]);
    expect(r.first.body, 'Через 30 хв · о 18:00');
  });

  test('ранкове зведення: справи, прострочені, ключові дати; порожні дні — без нього', () async {
    await db.saveTodo(title: 'Банк', dueDate: d(10, 27)); // прострочена
    await db.saveTodo(title: 'Подарунок', dueDate: d(10, 29));
    await db.saveTodo(
      title: 'Спортзал',
      dueDate: d(10, 29),
      dueMinutes: 18 * 60,
      remindBefore: AppDatabase.noReminder,
    );
    await db.saveTodo(
      title: 'ДН мами',
      dueDate: DateTime(1970, 11, 1),
      keyType: 'birthday',
      countYears: true,
      remindDays: 3,
    );
    final all = await plan(at: d(10, 28, 20), days: 3);
    final digests = all
        .where((n) => n.kind == NotificationKind.digest)
        .toList();
    // 29-го: 2 справи + 1 прострочена; ДН через 3 дні.
    expect(digests.first.at, d(10, 29, 9));
    expect(digests.first.title, 'Сьогодні: 3 справи');
    expect(
      digests.first.body,
      '3 справи (1 прострочено) · ДН мами через 3 дні',
    );
    expect(digests.first.lines, [
      'Прострочено: 1',
      '• 18:00 Спортзал',
      '• Подарунок',
      'ДН мами — через 3 дні (виповнюється 56)',
    ]);
    // 30-го лишається лише прострочена «Банк» (і минулі справи 29-го).
    expect(digests.length, 2);
    expect(digests.every((n) => n.at.hour == 9), isTrue);
  });

  test('зведення з одними ключовими датами й без справ', () async {
    await db.saveTodo(
      title: 'Новий рік',
      dueDate: DateTime(2000, 10, 30),
      keyType: 'holiday',
      remindDays: 1,
    );
    final all = await plan(days: 5, digest: 8 * 60);
    expect(all.map((n) => (n.at, n.title, n.body)), [
      (d(10, 29, 8), 'Ключові дати', 'Новий рік завтра'),
      (d(10, 30, 8), 'Ключові дати', 'Новий рік сьогодні'),
    ]);
  });

  test('не більше $planLimit сповіщень, найближчі', () async {
    for (var i = 0; i < 10; i++) {
      await db.saveTodo(
        title: 'Щодня $i',
        dueDate: d(10, 28),
        dueMinutes: 20 * 60 + i,
        repeat: TodoRepeat.day,
      );
    }
    final all = await plan(digest: null);
    expect(all.length, planLimit);
    expect(all.first.at, d(10, 28, 20));
    expect(all.last.at.isBefore(d(11, 4, 21)), isTrue);
    expect(all.last.id, planLimit);
  });

  test(
    '«Виконано» зі сповіщення: разова — вся, повторювана — лише повтор',
    () async {
      final once = await db.saveTodo(
        title: 'Разова',
        dueDate: d(10, 28),
        dueMinutes: 15 * 60,
      );
      final rep = await db.saveTodo(
        title: 'Щодня',
        dueDate: d(10, 26),
        dueMinutes: 8 * 60,
        repeat: TodoRepeat.day,
      );
      await markDoneFromNotification(db, once, d(10, 28));
      await markDoneFromNotification(db, rep, d(10, 29));
      await markDoneFromNotification(db, 'немає-такої', d(10, 29));
      final todos = await db.watchTodos().first;
      expect(todos.firstWhere((t) => t.id == once).done, isTrue);
      expect(todos.firstWhere((t) => t.id == rep).done, isFalse);
      final c = await db.watchTodoCompletions().first;
      expect(c.single.id, AppDatabase.completionId(rep, d(10, 29)));
    },
  );

  test('payload: зіпсований чи порожній — null', () {
    expect(decodePayload(null), isNull);
    expect(decodePayload('не json'), isNull);
    expect(decodePayload(encodePayload())!.todoId, isNull);
  });

  test('синхронізація переносить «нагадати»; старі файли — «вчасно»', () async {
    await db.saveTodo(
      title: 'Лікар',
      dueDate: d(10, 29),
      dueMinutes: 10 * 60,
      remindBefore: 30,
    );
    final snap = await db.exportSnapshot();
    final json = jsonDecode(snap.encode()) as Map<String, dynamic>;
    final other = AppDatabase(NativeDatabase.memory());
    await other.mergeSnapshot(FinanceSnapshot.decode(jsonEncode(json)));
    expect((await other.watchTodos().first).single.remindBefore, 30);
    // Файл етапу 17 — без поля.
    final todo = (json['todos'] as List).single as Map;
    todo.remove('remindBefore');
    json['version'] = 10;
    final third = AppDatabase(NativeDatabase.memory());
    await third.mergeSnapshot(FinanceSnapshot.decode(jsonEncode(json)));
    expect((await third.watchTodos().first).single.remindBefore, 0);
    await other.close();
    await third.close();
  });

  test(
    'оновлення з версії 12 (етап 17–18): справи лишаються, «вчасно»',
    () async {
      final dir = await Directory.systemTemp.createTemp('mymanager');
      final file = File('${dir.path}/v12.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      await old.saveTodo(title: 'Стара', dueDate: d(10, 28), dueMinutes: 600);
      await old.customStatement('ALTER TABLE todos DROP COLUMN remind_before');
      await old.customStatement('ALTER TABLE todos DROP COLUMN failed');
      await old.customStatement('ALTER TABLE todos DROP COLUMN priority');
      await old.customStatement(
        'ALTER TABLE todo_completions DROP COLUMN failed',
      );
      await old.customStatement(
        'ALTER TABLE todo_completions DROP COLUMN is_auto',
      );
      await old.customStatement('PRAGMA user_version = 12');
      await old.close();
      final db13 = AppDatabase(NativeDatabase(file));
      final t = (await db13.watchTodos().first).single;
      expect(t.title, 'Стара');
      expect(t.remindBefore, 0);
      await db13.close();
      await dir.delete(recursive: true);
    },
  );

  test('«не виконано»: без нагадувань; переноситься синхронізацією', () async {
    final once = await db.saveTodo(
      title: 'Разова',
      dueDate: d(10, 29),
      dueMinutes: 10 * 60,
    );
    final rep = await db.saveTodo(
      title: 'Щодня',
      dueDate: d(10, 28),
      dueMinutes: 20 * 60,
      repeat: TodoRepeat.day,
    );
    await db.setTodoFailed(once, true);
    await db.setOccurrenceFailed(rep, d(10, 28), true);
    final r = await plan(digest: null, days: 3);
    expect(r.map((n) => n.at), [d(10, 29, 20), d(10, 30, 20)]);

    final other = AppDatabase(NativeDatabase.memory());
    await other.mergeSnapshot(
      FinanceSnapshot.decode((await db.exportSnapshot()).encode()),
    );
    final t = (await other.watchTodos().first).firstWhere((t) => t.id == once);
    expect(t.failed, isTrue);
    expect((await other.watchTodoCompletions().first).single.failed, isTrue);
    await other.close();
  });
}
