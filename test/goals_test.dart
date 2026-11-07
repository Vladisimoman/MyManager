import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/goals.dart';
import 'package:my_manager/sync/snapshot.dart';

/// 1.15: цілі накопичення.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, GoalProgress>> progress() async =>
      goalProgress(await db.watchGoals().first, await db.watchGoalContributions().first);

  test('внески й зняття; видалений внесок не рахується', () async {
    final id = await db.saveGoal(name: ' Ноутбук ', icon: 'laptop', targetCents: 150000, currency: 'EUR');
    await db.addGoalContribution(goalId: id, amountCents: 60000, date: DateTime(2026, 10, 1));
    final c = await db.addGoalContribution(goalId: id, amountCents: 20000, date: DateTime(2026, 10, 2));
    await db.addGoalContribution(goalId: id, amountCents: -10000, date: DateTime(2026, 10, 3), note: 'на ремонт');
    var p = (await progress())[id]!;
    expect(p.goal.name, 'Ноутбук');
    expect(p.savedCents, 70000);
    expect(p.leftCents, 80000);
    expect(p.reached, isFalse);
    await db.setGoalContributionDeleted(c, true);
    p = (await progress())[id]!;
    expect(p.savedCents, 50000);
    // Гроші в гаманцях не чіпаємо.
    expect(await db.countEntries(), 0);
  });

  test('скільки відкладати щомісяця до терміну', () {
    final now = DateTime(2026, 10, 28);
    Goal goal(DateTime? deadline) => Goal(id: 'g', name: 'Ціль', icon: 'savings', targetCents: 150000,
        currency: 'EUR', deadline: deadline, archived: false, createdAt: now, updatedAt: now, deleted: false);

    final p = GoalProgress(goal(DateTime(2027, 3, 1)), 50000);
    expect(p.monthsLeft(now), 5); // листопад…березень
    expect(p.perMonthCents(now), 20000);

    expect(GoalProgress(goal(DateTime(2026, 11, 5)), 0).monthsLeft(now), 1);
    expect(GoalProgress(goal(null), 0).perMonthCents(now), isNull);
    final overdue = GoalProgress(goal(DateTime(2026, 10, 1)), 0);
    expect(overdue.overdue(now), isTrue);
    expect(overdue.perMonthCents(now), isNull);
    expect(GoalProgress(goal(DateTime(2027, 3, 1)), 160000).reached, isTrue);
    expect(GoalProgress(goal(DateTime(2027, 3, 1)), 160000).leftCents, 0);
  });

  test('архів, видалення, синхронізація, очищення', () async {
    final id = await db.saveGoal(name: 'Відпустка', icon: 'travel', targetCents: 200000,
        currency: 'PLN', deadline: DateTime(2027, 7, 1));
    await db.addGoalContribution(goalId: id, amountCents: 30000, date: DateTime(2026, 10, 1));
    await db.setGoalArchived(id, true);

    final other = AppDatabase(NativeDatabase.memory());
    addTearDown(other.close);
    await other.mergeSnapshot(FinanceSnapshot.decode((await db.exportSnapshot()).encode()));
    final g = (await other.watchGoals().first).single;
    expect(g.archived, isTrue);
    expect(g.deadline, DateTime(2027, 7, 1));
    expect(g.currency, 'PLN');
    expect((await other.watchGoalContributions().first).single.amountCents, 30000);

    await db.setGoalDeleted(id, true);
    expect(await db.watchGoals().first, isEmpty);
    await db.setGoalDeleted(id, false);
    await db.wipeAllData(resetId: 'x');
    expect(await db.watchGoals().first, isEmpty);
    expect(await db.watchGoalContributions().first, isEmpty);
  });

  test('оновлення з версії 8 (етап 12): таблиці цілей з\'являються', () async {
    final dir = await Directory.systemTemp.createTemp('mymanager');
    final file = File('${dir.path}/v8.sqlite');
    final old = AppDatabase(NativeDatabase(file));
    await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
        categoryId: 'exp-groceries', date: DateTime(2026, 10, 1));
    await old.customStatement('DROP TABLE goals');
    await old.customStatement('DROP TABLE goal_contributions');
    await old.customStatement('PRAGMA user_version = 8');
    await old.close();
    final db9 = AppDatabase(NativeDatabase(file));
    expect((await db9.watchAllEntries().first).single.amountCents, 4590);
    expect(await db9.watchGoals().first, isEmpty);
    await db9.close();
    await dir.delete(recursive: true);
  });
}
