import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/activity/activity_logic.dart';
import 'package:my_manager/sync/snapshot.dart';

Activity act(String id, DateTime s, DateTime? e, {String cat = 'act-work', bool deleted = false}) => Activity(
    id: id, categoryId: cat, start: s, end: e, note: null,
    createdAt: s, updatedAt: s, deleted: deleted);

/// Етап 14: Activity.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 10, d, h, m);

  group('логіка', () {
    test('нова активність починається з кінця попередньої', () {
      final list = [
        act('sleep', t(27, 23), t(28, 8), cat: 'act-sleep'),
        act('old', t(27, 10), t(27, 11)),
      ];
      expect(suggestedStart(list, t(28, 8, 30)), t(28, 8));
      // Видалені й таймер — не рахуються.
      expect(suggestedStart([...list, act('x', t(28, 8), t(28, 8, 20), deleted: true)], t(28, 8, 30)), t(28, 8));
      expect(suggestedStart([act('run', t(28, 8), null)], t(28, 9)), isNull);
      // Давно (понад добу) — вказати самому.
      expect(suggestedStart([act('a', t(25, 8), t(25, 9))], t(28, 9)), isNull);
    });

    test('стрічка дня: сон через північ обрізано, прогалини, хвіст до «зараз»', () {
      final list = [
        act('sleep', t(27, 23, 30), t(28, 8), cat: 'act-sleep'),
        act('bf', t(28, 8), t(28, 8, 30), cat: 'act-breakfast'),
        act('work', t(28, 9, 30), t(28, 12)),
      ];
      final items = dayTimeline(list, DateTime(2026, 10, 28), t(28, 13));
      expect(items.map((i) => i.isGap ? 'gap ${i.duration.inMinutes}' : i.activity!.id), [
        'sleep', 'bf', 'gap 60', 'work', 'gap 60',
      ]);
      expect(items.first.from, DateTime(2026, 10, 28)); // з 00:00
      expect(items.first.startsBefore, isTrue);
      expect(trackedOn(list, DateTime(2026, 10, 28), t(28, 13)), const Duration(hours: 11));
      // Попередній день: лише 23:30–24:00.
      final prev = dayTimeline(list, DateTime(2026, 10, 27), t(28, 13));
      expect(prev.single.duration, const Duration(minutes: 30));
      expect(prev.single.endsAfter, isTrue);
    });

    test('таймер у стрічці — до «зараз», без хвоста-прогалини', () {
      final list = [act('a', t(28, 8), t(28, 9)), act('run', t(28, 9), null)];
      final items = dayTimeline(list, DateTime(2026, 10, 28), t(28, 10, 15));
      expect(items.length, 2);
      expect(items.last.to, t(28, 10, 15));
      expect(runningActivity(list)!.id, 'run');
    });

    test('перетини', () {
      final list = [act('a', t(28, 8), t(28, 9)), act('b', t(28, 9), t(28, 10))];
      expect(overlapping(list, t(28, 9), t(28, 9, 30)).map((a) => a.id), ['b']);
      expect(overlapping(list, t(28, 8, 30), t(28, 9, 30)).map((a) => a.id), ['a', 'b']);
      expect(overlapping(list, t(28, 9), t(28, 10), exceptId: 'b'), isEmpty);
    });

    test('формат тривалості', () {
      expect(formatDuration(const Duration(minutes: 30)), '30 хв');
      expect(formatDuration(const Duration(hours: 7)), '7 год');
      expect(formatDuration(const Duration(minutes: 80)), '1 год 20 хв');
      expect(formatClock(const Duration(hours: 1, minutes: 5, seconds: 9)), '1:05:09');
      expect(formatClock(const Duration(minutes: 4, seconds: 2)), '0:04:02');
    });
  });

  group('база', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('стартові категорії з позначками продуктивності', () async {
      final cats = await db.watchActivityCategories().first;
      expect(cats.length, 12);
      expect(cats.first.name, 'Сон');
      expect(cats.firstWhere((c) => c.id == 'act-youtube').kind, ActivityKind.waste);
      expect(cats.firstWhere((c) => c.id == 'act-work').kind, ActivityKind.useful);
      final id = await db.saveActivityCategory(name: 'Гітара', icon: 'music', color: 1, kind: ActivityKind.useful);
      expect((await db.watchActivityCategories().first).last.id, id);
    });

    test('таймер: почати й завершити; синхронізація зберігає точний час', () async {
      final id = await db.saveActivity(categoryId: 'act-work', start: t(28, 9, 15));
      expect(runningActivity(await db.watchActivities().first)!.id, id);
      await db.stopActivity(id, t(28, 10, 45));
      final a = (await db.watchActivities().first).single;
      expect(a.end, t(28, 10, 45));

      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await other.mergeSnapshot(FinanceSnapshot.decode((await db.exportSnapshot()).encode()));
      final b = (await other.watchActivities().first).single;
      expect(b.start, t(28, 9, 15));
      expect(b.end, t(28, 10, 45));
      expect((await other.watchActivityCategories().first).length, 12);
    });

    test('видалення, очищення даних повертає стартові категорії', () async {
      final id = await db.saveActivity(categoryId: 'act-sleep', start: t(28, 1), end: t(28, 8));
      await db.setActivityDeleted(id, true);
      expect(await db.watchActivities().first, isEmpty);
      await db.saveActivityCategory(name: 'Гітара', icon: 'music', color: 1, kind: ActivityKind.useful);
      await db.wipeAllData(resetId: 'x');
      expect((await db.watchActivityCategories().first).length, 12);
    });

    test('оновлення з версії 9: таблиці Activity й стартові категорії', () async {
      final dir = await Directory.systemTemp.createTemp('mymanager');
      final file = File('${dir.path}/v9.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
          categoryId: 'exp-groceries', date: DateTime(2026, 10, 1));
      await old.customStatement('DROP TABLE activities');
      await old.customStatement('DROP TABLE activity_categories');
      await old.customStatement('PRAGMA user_version = 9');
      await old.close();
      final db10 = AppDatabase(NativeDatabase(file));
      expect((await db10.watchAllEntries().first).single.amountCents, 4590);
      expect((await db10.watchActivityCategories().first).length, 12);
      await db10.close();
      await dir.delete(recursive: true);
    });
  });
}
