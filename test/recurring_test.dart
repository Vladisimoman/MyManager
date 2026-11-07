import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/recurring.dart';
import 'package:my_manager/sync/snapshot.dart';

/// Етап 12: шаблони й регулярні платежі.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('дати повторів', () {
    test('щомісяця 31-го: у коротких місяцях — останній день', () {
      final s = DateTime(2026, 1, 31);
      expect([for (var i = 0; i < 4; i++) occurrenceAt(RepeatKind.monthly, s, i)], [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31),
        DateTime(2026, 4, 30),
      ]);
    });

    test('щотижня й щороку (29 лютого)', () {
      expect(occurrenceAt(RepeatKind.weekly, DateTime(2026, 10, 26), 2), DateTime(2026, 11, 9));
      expect(occurrenceAt(RepeatKind.yearly, DateTime(2028, 2, 29), 1), DateTime(2029, 2, 28));
      expect(occurrenceAt(RepeatKind.yearly, DateTime(2028, 2, 29), 4), DateTime(2032, 2, 29));
    });

    test('через перехід на зимовий час дати не зсуваються', () {
      // 25.10.2026 — перехід часу в Польщі / Україні.
      expect(occurrenceAt(RepeatKind.weekly, DateTime(2026, 10, 20), 1), DateTime(2026, 10, 27));
    });
  });

  group('очікувані платежі', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<EntryTemplate> netflix({DateTime? start}) async {
      final id = await db.saveTemplate(
        type: EntryType.expense,
        name: 'Netflix',
        amountCents: 1299,
        currency: 'EUR',
        categoryId: 'exp-subscriptions',
        walletId: AppDatabase.mainWalletId,
        repeat: RepeatKind.monthly,
        startDate: start ?? DateTime(2026, 8, 15),
      );
      return (await db.watchTemplates().first).firstWhere((t) => t.id == id);
    }

    Future<List<PendingPayment>> pending(DateTime today) async => pendingPayments(
          await db.watchTemplates().first,
          await db.watchHandledOccurrences().first,
          today,
        );

    test('з\'являються в день платежу; записати / пропустити — зникають', () async {
      final t = await netflix();
      var p = await pending(DateTime(2026, 10, 27));
      expect(p.map((x) => x.date), [DateTime(2026, 8, 15), DateTime(2026, 9, 15), DateTime(2026, 10, 15)]);

      // Записати (зі зміненою сумою) і пропустити.
      await db.addEntry(id: p[0].id, type: t.type, amountCents: 1499, currency: 'EUR',
          categoryId: t.categoryId, date: p[0].date, walletId: t.walletId);
      await db.skipOccurrence(t, p[1].id, p[1].date);
      p = await pending(DateTime(2026, 10, 27));
      expect(p.single.date, DateTime(2026, 10, 15));

      final entries = await db.watchAllEntries().first;
      expect(entries.single.amountCents, 1499); // пропущений не видно в записах
      expect(nextOccurrence(t, await db.watchHandledOccurrences().first, DateTime(2026, 10, 27)),
          DateTime(2026, 10, 15));

      // Скасувати пропуск — платіж знову чекає.
      await db.deleteEntryRow(occurrenceId(t.id, DateTime(2026, 9, 15)));
      expect((await pending(DateTime(2026, 10, 27))).length, 2);
    });

    test('перший платіж у майбутньому — нічого не чекає; шаблон без повтору — теж', () async {
      await netflix(start: DateTime(2026, 11, 1));
      await db.saveTemplate(type: EntryType.expense, name: 'Кава', amountCents: 350, currency: 'EUR',
          categoryId: 'exp-restaurant', walletId: AppDatabase.mainWalletId);
      expect(await pending(DateTime(2026, 10, 27)), isEmpty);
    });

    test('видалення запису платежу не повертає його в очікувані', () async {
      final t = await netflix(start: DateTime(2026, 10, 1));
      final id = occurrenceId(t.id, DateTime(2026, 10, 1));
      await db.addEntry(id: id, type: t.type, amountCents: 1299, currency: 'EUR',
          categoryId: t.categoryId, date: DateTime(2026, 10, 1));
      await db.setEntryDeleted(id, true);
      expect(await pending(DateTime(2026, 10, 27)), isEmpty);
    });

    test('показуємо не більше 12 найсвіжіших пропущених', () async {
      await db.saveTemplate(type: EntryType.expense, name: 'Кава', amountCents: 350, currency: 'EUR',
          categoryId: 'exp-restaurant', walletId: AppDatabase.mainWalletId,
          repeat: RepeatKind.weekly, startDate: DateTime(2025, 1, 1));
      final p = await pending(DateTime(2026, 10, 27));
      expect(p.length, maxPendingPerTemplate);
      expect(p.last.date, DateTime(2026, 10, 21));
    });

    test('підтвердження на двох телефонах — один запис після синхронізації', () async {
      final t = await netflix(start: DateTime(2026, 10, 15));
      final other = AppDatabase(NativeDatabase.memory());
      addTearDown(other.close);
      await other.mergeSnapshot(FinanceSnapshot.decode((await db.exportSnapshot()).encode()));
      final shared = (await other.watchTemplates().first).single;
      expect(shared.repeat, RepeatKind.monthly);
      expect(shared.startDate, DateTime(2026, 10, 15));

      final id = occurrenceId(t.id, DateTime(2026, 10, 15));
      Future<void> confirm(AppDatabase d) => d.addEntry(id: id, type: t.type, amountCents: 1299,
          currency: 'EUR', categoryId: t.categoryId, date: DateTime(2026, 10, 15));
      await confirm(db);
      await confirm(other);
      await db.mergeSnapshot(FinanceSnapshot.decode((await other.exportSnapshot()).encode()));
      expect((await db.watchAllEntries().first).length, 1);
    });

    test('видалення шаблону; очищення даних', () async {
      final t = await netflix();
      await db.setTemplateDeleted(t.id, true);
      expect(await db.watchTemplates().first, isEmpty);
      expect(await pending(DateTime(2026, 10, 27)), isEmpty);
      await db.setTemplateDeleted(t.id, false);
      await db.wipeAllData(resetId: 'x');
      expect(await db.watchTemplates().first, isEmpty);
    });

    test('оновлення з версії 7 (етап 11): таблиця шаблонів з\'являється', () async {
      final dir = await Directory.systemTemp.createTemp('mymanager');
      final file = File('${dir.path}/v7.sqlite');
      final old = AppDatabase(NativeDatabase(file));
      await old.addEntry(type: EntryType.expense, amountCents: 4590, currency: 'EUR',
          categoryId: 'exp-groceries', date: DateTime(2026, 10, 1));
      await old.customStatement('DROP TABLE templates');
      await old.customStatement('PRAGMA user_version = 7');
      await old.close();
      final db8 = AppDatabase(NativeDatabase(file));
      expect((await db8.watchAllEntries().first).single.amountCents, 4590);
      expect(await db8.watchTemplates().first, isEmpty);
      await db8.close();
      await dir.delete(recursive: true);
    });
  });
}
