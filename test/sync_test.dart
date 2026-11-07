import 'dart:convert';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/finance/finance_providers.dart';
import 'package:my_manager/sync/cloud_store.dart';
import 'package:my_manager/sync/snapshot.dart';
import 'package:my_manager/sync/sync_controller.dart';
import 'package:my_manager/sync/sync_service.dart';

import 'helpers/memory_cloud.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late MemoryCloudStore cloud;
  final dbs = <AppDatabase>[];

  AppDatabase device() {
    final db = AppDatabase(NativeDatabase.memory());
    dbs.add(db);
    return db;
  }

  setUp(() => cloud = MemoryCloudStore());
  tearDown(() async {
    for (final db in dbs) {
      await db.close();
    }
    dbs.clear();
  });

  Future<String> add(AppDatabase db, int cents, {EntryType type = EntryType.expense}) =>
      db.addEntry(
        type: type,
        amountCents: cents,
        currency: 'EUR',
        categoryId: type == EntryType.expense ? 'exp-groceries' : 'inc-salary',
        date: DateTime(2026, 10, 20),
      );

  Future<List<int>> amounts(AppDatabase db) async =>
      (await db.watchAllEntries().first).map((e) => e.amountCents).toList()..sort();

  test('знімок: кодування й розбір без втрат', () async {
    final db = device();
    await add(db, 1234);
    await db.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 5000);
    final snap = await db.exportSnapshot();
    final again = FinanceSnapshot.decode(snap.encode());
    expect(again.encode(), snap.encode());
    expect(again.transactions.single.amountCents, 1234);
    expect(again.transactions.single.date, DateTime(2026, 10, 20));
    expect(again.categories.length, 20); // 17 + 2 інвестиційні + «Продаж речей»
  });

  test('перша синхронізація вивантажує, повторна — нічого не змінює', () async {
    final a = device();
    await add(a, 1000);
    final s = SyncService(a, cloud);

    final r1 = await s.sync();
    expect(r1.uploaded, isTrue);
    expect(cloud.files.keys, ['finance.json']); // резервної копії ще немає

    final r2 = await s.sync();
    expect(r2.uploaded, isFalse);
    expect(r2.pulled, 0);
    expect(cloud.writes, 1);
  });

  test('після перевстановлення дані повертаються з Drive', () async {
    final phone = device();
    await add(phone, 4590);
    await add(phone, 250000, type: EntryType.income);
    await phone.setWalletCurrency(AppDatabase.mainWalletId, 'EUR', 10000);
    await SyncService(phone, cloud).sync();

    final reinstalled = device(); // нова порожня база зі стартовими категоріями
    final r = await SyncService(reinstalled, cloud).sync();

    expect(r.pulled, greaterThan(0));
    expect(await amounts(reinstalled), [4590, 250000]);
    expect(await reinstalled.getInitialCents(AppDatabase.mainWalletId, 'EUR'), 10000);
    expect((await reinstalled.watchCategories(EntryType.expense).first).length, 12);
  });

  test('два пристрої обмінюються записами', () async {
    final a = device(), b = device();
    await add(a, 100);
    await SyncService(a, cloud).sync();
    await add(b, 200);
    await SyncService(b, cloud).sync(); // B отримує запис A і вивантажує обидва
    await SyncService(a, cloud).sync(); // A отримує запис B

    expect(await amounts(a), [100, 200]);
    expect(await amounts(b), [100, 200]);
  });

  test('конфлікт: перемагає пізніша зміна', () async {
    final a = device(), b = device();
    final id = await add(a, 100);
    await SyncService(a, cloud).sync();
    await SyncService(b, cloud).sync();

    Future<void> edit(AppDatabase db, int cents, DateTime at) =>
        (db.update(db.transactions)..where((t) => t.id.equals(id))).write(
          TransactionsCompanion(amountCents: Value(cents), updatedAt: Value(at)),
        );
    final now = DateTime.now().toUtc();
    await edit(b, 222, now.add(const Duration(minutes: 1))); // раніше
    await edit(a, 333, now.add(const Duration(minutes: 5))); // пізніше

    await SyncService(b, cloud).sync();
    await SyncService(a, cloud).sync();
    await SyncService(b, cloud).sync();

    expect(await amounts(a), [333]);
    expect(await amounts(b), [333]);
  });

  test('видалення доходить на інший пристрій', () async {
    final a = device(), b = device();
    final id = await add(a, 100);
    await add(a, 200);
    await SyncService(a, cloud).sync();
    await SyncService(b, cloud).sync();
    expect(await amounts(b), [100, 200]);

    await Future<void>.delayed(const Duration(milliseconds: 1100)); // updatedAt має секундну точність
    await a.setEntryDeleted(id, true);
    await SyncService(a, cloud).sync();
    await SyncService(b, cloud).sync();
    expect(await amounts(b), [200]);
  });

  test('нова й перейменована категорії доходять на інший пристрій', () async {
    final a = device(), b = device();
    await SyncService(a, cloud).sync();
    await SyncService(b, cloud).sync();

    final id = await a.addCategory(
        type: EntryType.expense, name: 'Кава', icon: 'coffee', color: 0xFF6D4C41);
    await a.updateCategory('exp-clothes',
        name: 'Одяг і взуття', icon: 'clothes', color: 0xFF8E24AA, hidden: true);
    await SyncService(a, cloud).sync();
    await SyncService(b, cloud).sync();

    final cats = {for (final c in await b.select(b.categories).get()) c.id: c};
    expect(cats[id]!.name, 'Кава');
    expect(cats['exp-clothes']!.name, 'Одяг і взуття');
    expect(cats['exp-clothes']!.hidden, isTrue);

    // Новий телефон зі стартовими категоріями не перезаписує перейменування.
    final fresh = device();
    await SyncService(fresh, cloud).sync();
    final f = await (fresh.select(fresh.categories)
          ..where((c) => c.id.equals('exp-clothes')))
        .getSingle();
    expect(f.name, 'Одяг і взуття');
  });

  test('перед вивантаженням попередня версія зберігається як резервна копія', () async {
    final a = device();
    await add(a, 100);
    await SyncService(a, cloud).sync();
    final first = cloud.files['finance.json'];

    await add(a, 200);
    await SyncService(a, cloud).sync();
    expect(cloud.files['finance.backup.json'], first);
    expect(cloud.files['finance.json'], isNot(first));
  });

  test('пошкоджений файл на Drive не перезаписується', () async {
    final a = device();
    await add(a, 100);
    cloud.files['finance.json'] = '{не json';
    await expectLater(SyncService(a, cloud).sync(), throwsFormatException);
    expect(cloud.files['finance.json'], '{не json');
    expect(await amounts(a), [100]); // локальні дані на місці
  });

  test('налаштування цього пристрою (local.*) не синхронізуються', () async {
    final a = device(), b = device();
    await a.setSetting('local.google_email', 'a@example.com');
    await SyncService(a, cloud).sync();
    expect(cloud.files['finance.json'], isNot(contains('google_email')));
    expect(cloud.files['finance.json'], isNot(contains('last_sync_at')));
    await SyncService(b, cloud).sync();
    expect(await b.getSetting('local.google_email'), isNull);
  });

  group('Google Drive API', () {
    test('створює файл у appDataFolder, потім оновлює його', () async {
      final calls = <String>[];
      var exists = false;
      final client = MockClient((req) async {
        calls.add('${req.method} ${req.url.path}');
        if (req.method == 'GET' && req.url.path == '/drive/v3/files') {
          expect(req.url.queryParameters['spaces'], 'appDataFolder');
          return http.Response(
              jsonEncode({'files': exists ? [{'id': 'F1', 'name': 'finance.json'}] : []}), 200);
        }
        if (req.method == 'POST') {
          expect(req.headers['Content-Type'], startsWith('multipart/related'));
          expect(req.body, contains('"parents":["appDataFolder"]'));
          exists = true;
          return http.Response('{"id":"F1"}', 200);
        }
        if (req.method == 'PATCH') return http.Response('{"id":"F1"}', 200);
        if (req.method == 'GET' && req.url.path.endsWith('/F1')) {
          return http.Response.bytes(utf8.encode('{"ok":"привіт"}'), 200);
        }
        return http.Response('?', 500);
      });
      final store = DriveAppDataStore(({invalidToken}) async => 't', client: client);

      expect(await store.read('finance.json'), isNull);
      await store.write('finance.json', '{}');
      await store.write('finance.json', '{"a":1}');
      expect(await store.read('finance.json'), '{"ok":"привіт"}');
      expect(calls.where((c) => c.startsWith('POST')).length, 1);
      expect(calls.where((c) => c.startsWith('PATCH')).length, 1);
    });

    test('при 401 оновлює токен і повторює запит', () async {
      final seenTokens = <String?>[];
      final client = MockClient((req) async {
        final auth = req.headers['Authorization'];
        if (auth == 'Bearer old') return http.Response('expired', 401);
        return http.Response('{"files":[]}', 200);
      });
      final store = DriveAppDataStore(({invalidToken}) async {
        seenTokens.add(invalidToken);
        return invalidToken == null ? 'old' : 'new';
      }, client: client);

      expect(await store.read('finance.json'), isNull);
      expect(seenTokens, [null, 'old']);
    });

    test('без входу — зрозуміла помилка', () async {
      final store = DriveAppDataStore(({invalidToken}) async => null,
          client: MockClient((_) async => http.Response('', 200)));
      await expectLater(
        store.read('x'),
        throwsA(isA<CloudException>().having((e) => e.isAuth, 'isAuth', isTrue)),
      );
    });
  });

  group('SyncController', () {
    ProviderContainer containerFor(AppDatabase db) {
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        syncAuthProvider.overrideWithValue(FakeSyncAuth()),
        cloudStoreProvider.overrideWithValue(cloud),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('вхід запам\'ятовується й одразу синхронізує', () async {
      final db = device();
      await add(db, 700);
      final c = containerFor(db);
      expect(c.read(syncControllerProvider).status, SyncStatus.signedOut);

      await c.read(syncControllerProvider.notifier).signIn();
      final s = c.read(syncControllerProvider);
      expect(s.status, SyncStatus.idle);
      expect(s.email, 'me@example.com');
      expect(s.lastSyncAt, isNotNull);
      expect(cloud.files['finance.json'], contains('"amountCents": 700'));
      expect(await db.getSetting(SyncController.emailKey), 'me@example.com');
    });

    test('без інтернету — помилка, дані лишаються на телефоні', () async {
      final db = device();
      final c = containerFor(db);
      await c.read(syncControllerProvider.notifier).signIn();
      cloud.offline = true;
      await add(db, 1);
      await c.read(syncControllerProvider.notifier).syncNow();
      expect(c.read(syncControllerProvider).status, SyncStatus.error);
      expect(await amounts(db), [1]);
    });

    test('прострочений дозвіл: кнопка просить підтвердження й синхронізує', () async {
      final db = device();
      final auth = FakeSyncAuth();
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        syncAuthProvider.overrideWithValue(auth),
        cloudStoreProvider.overrideWithValue(
          DriveAppDataStore(
            ({invalidToken}) => auth.accessToken(invalidToken: invalidToken),
            client: _fakeDrive(),
          ),
        ),
      ]);
      addTearDown(c.dispose);
      final ctrl = c.read(syncControllerProvider.notifier);
      await ctrl.signIn();
      expect(c.read(syncControllerProvider).message, isNull);
      expect(c.read(syncControllerProvider).status, SyncStatus.idle);

      auth.authorized = false; // минуло 7 днів
      await add(db, 9);
      await ctrl.syncNow(); // автоматична — без вікон
      expect(c.read(syncControllerProvider).status, SyncStatus.error);
      expect(c.read(syncControllerProvider).message, contains('підтвердити доступ'));
      expect(auth.interactiveCalls, 0);

      await ctrl.syncNow(interactive: true); // кнопка «Синхронізувати зараз»
      expect(auth.interactiveCalls, 1);
      expect(c.read(syncControllerProvider).status, SyncStatus.idle);
    });

    test('браузер: без доступу — підказка замість помилки, кнопка поновлює', () async {
      final db = device();
      final auth = FakeSyncAuth();
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWithValue(db),
        syncAuthProvider.overrideWithValue(auth),
        syncNeedsClickProvider.overrideWithValue(true),
        cloudStoreProvider.overrideWithValue(
          DriveAppDataStore(
            ({invalidToken}) => auth.accessToken(invalidToken: invalidToken),
            client: _fakeDrive(),
          ),
        ),
      ]);
      addTearDown(c.dispose);
      final ctrl = c.read(syncControllerProvider.notifier);
      await ctrl.signIn();

      auth.authorized = false; // сторінку перезавантажили / минула година
      await add(db, 9);
      await ctrl.syncNow();
      expect(c.read(syncControllerProvider).status, SyncStatus.idle);
      expect(c.read(syncControllerProvider).message, webSyncHint);
      expect(auth.interactiveCalls, 0);

      await ctrl.syncNow(interactive: true);
      expect(auth.interactiveCalls, 1);
      expect(c.read(syncControllerProvider).status, SyncStatus.idle);
      expect(c.read(syncControllerProvider).message, isNull);
    });

    test('вихід зупиняє синхронізацію, але не видаляє дані', () async {
      final db = device();
      await add(db, 5);
      final c = containerFor(db);
      await c.read(syncControllerProvider.notifier).signIn();
      await c.read(syncControllerProvider.notifier).signOut();
      expect(c.read(syncControllerProvider).status, SyncStatus.signedOut);
      expect(await db.getSetting(SyncController.emailKey), isNull);
      expect(await amounts(db), [5]);
    });
  });
}

/// Мінімальний «Drive»: зберігає один файл з id F1.
MockClient _fakeDrive() {
  String? content;
  return MockClient((req) async {
    if (req.method == 'GET' && req.url.queryParameters['alt'] == 'media') {
      return http.Response.bytes(utf8.encode(content ?? ''), 200);
    }
    if (req.method == 'GET') {
      return http.Response(jsonEncode({'files': content == null ? [] : [{'id': 'F1'}]}), 200);
    }
    final body = utf8.decode(req.bodyBytes);
    if (req.method == 'POST') {
      // multipart: вміст — друга частина
      final parts = body.split('\r\n\r\n');
      content = parts.last.substring(0, parts.last.lastIndexOf('\r\n--'));
    } else {
      content = body;
    }
    return http.Response('{"id":"F1"}', 200);
  });
}
