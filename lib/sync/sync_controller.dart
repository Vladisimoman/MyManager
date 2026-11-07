import 'dart:async';
import 'dart:io' show SocketException;

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../features/finance/finance_providers.dart';
import 'cloud_store.dart';
import 'google_auth.dart';
import 'sync_service.dart';
import 'worker_auth.dart';

enum SyncStatus { notConfigured, signedOut, idle, syncing, error }

class SyncState {
  const SyncState({
    required this.status,
    this.email,
    this.lastSyncAt,
    this.message,
  });

  final SyncStatus status;
  final String? email;
  final DateTime? lastSyncAt;

  /// Текст помилки або підсумок останньої синхронізації.
  final String? message;

  bool get signedIn => email != null;

  SyncState copyWith({
    SyncStatus? status,
    String? email,
    DateTime? lastSyncAt,
    String? message,
    bool clearEmail = false,
  }) => SyncState(
    status: status ?? this.status,
    email: clearEmail ? null : (email ?? this.email),
    lastSyncAt: lastSyncAt ?? this.lastSyncAt,
    message: message,
  );
}

/// Телефон — Google на Android; браузер — через наш Worker (етап 23).
final syncAuthProvider = Provider<SyncAuth>(
  (ref) => kIsWeb ? WorkerSyncAuth() : GoogleSyncAuth(),
);

/// Браузер: якщо Worker не зміг поновити доступ (минув строк ключа,
/// доступ відкликано), повторний вхід — лише кліком. Тоді це не помилка, а підказка.
final syncNeedsClickProvider = Provider<bool>((ref) => kIsWeb);

const webSyncHint =
    'Натисни «Синхронізувати зараз», щоб оновити дані з Google Drive';

final cloudStoreProvider = Provider<CloudStore>((ref) {
  final auth = ref.watch(syncAuthProvider);
  return DriveAppDataStore(
    ({invalidToken}) => auth.accessToken(invalidToken: invalidToken),
  );
});

final syncServiceProvider = Provider<SyncService>(
  (ref) =>
      SyncService(ref.watch(databaseProvider), ref.watch(cloudStoreProvider)),
);

/// Керує входом і автоматичною синхронізацією:
/// при запуску, через 5 с після змін, при поверненні в додаток і за кнопкою.
class SyncController extends Notifier<SyncState> {
  static const emailKey = '${AppDatabase.localPrefix}google_email';
  static const changeDelay = Duration(seconds: 5);
  static const resumeMinInterval = Duration(minutes: 1);

  StreamSubscription<void>? _changes;
  Timer? _debounce;
  AppLifecycleListener? _lifecycle;
  String? _lastSyncedData;
  bool _busy = false;

  /// Завершується, коли збережений акаунт прочитано з бази.
  Future<void> _ready = Future.value();

  AppDatabase get _db => ref.read(databaseProvider);
  SyncAuth get _auth => ref.read(syncAuthProvider);
  SyncService get _service => ref.read(syncServiceProvider);

  @override
  SyncState build() {
    ref.onDispose(_stopWatching);
    if (!ref.watch(syncAuthProvider).isConfigured) {
      return const SyncState(status: SyncStatus.notConfigured);
    }
    _ready = Future(_restore);
    return const SyncState(status: SyncStatus.signedOut);
  }

  Future<void> _restore() async {
    final email = await _db.getSetting(emailKey);
    final last = DateTime.tryParse(
      await _db.getSetting(SyncService.lastSyncKey) ?? '',
    );
    if (email == null) {
      state = SyncState(status: SyncStatus.signedOut, lastSyncAt: last);
      return;
    }
    state = SyncState(status: SyncStatus.idle, email: email, lastSyncAt: last);
    _startWatching();
    unawaited(syncNow()); // синхронізація при запуску
  }

  Future<void> signIn() async {
    await _ready;
    try {
      final email = await _auth.signIn();
      await _db.setSetting(emailKey, email);
      state = state.copyWith(status: SyncStatus.idle, email: email);
      _startWatching();
      await syncNow();
    } on GoogleSignInException catch (e) {
      state = state.copyWith(
        status: SyncStatus.signedOut,
        message: e.code == GoogleSignInExceptionCode.canceled
            ? 'Вхід скасовано'
            : 'Не вдалося увійти: ${e.description ?? e.code.name}',
      );
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.signedOut,
        message: 'Не вдалося увійти: $e',
      );
    }
  }

  Future<void> signOut() async {
    await _ready;
    _stopWatching();
    try {
      await _auth.signOut();
    } catch (_) {
      // Локальний вихід важливіший за відповідь Google.
    }
    await _db.setSetting(emailKey, null);
    _lastSyncedData = null;
    state = SyncState(
      status: SyncStatus.signedOut,
      lastSyncAt: state.lastSyncAt,
    );
  }

  /// Видаляє всі дані на телефоні; якщо є вхід у Google — і на Drive
  /// (попередня версія лишається в `finance.backup.json`).
  Future<void> wipeAllData() async {
    await _ready;
    await _db.wipeAllData(resetId: const Uuid().v4());
    _lastSyncedData = null;
    if (state.signedIn) await syncNow();
  }

  /// [onlyIfChanged] — пропустити, якщо локальні дані не змінились з останньої синхронізації.
  /// [interactive] — запуск кнопкою: якщо Google просить підтвердити доступ, показати вікно.
  Future<void> syncNow({
    bool onlyIfChanged = false,
    bool interactive = false,
  }) async {
    await _ready;
    if (_busy || !state.signedIn) return;
    if (onlyIfChanged &&
        _lastSyncedData != null &&
        await _service.localFingerprint() == _lastSyncedData) {
      return;
    }
    _busy = true;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      if (interactive && await _auth.accessToken() == null) {
        await _auth.authorizeInteractive();
      }
      final r = await _service.sync();
      _lastSyncedData = await _service.localFingerprint();
      state = state.copyWith(
        status: SyncStatus.idle,
        lastSyncAt: DateTime.now().toUtc(),
        message: r.resetApplied
            ? 'Дані видалено на іншому пристрої — тут теж очищено'
            : (r.pulled > 0 ? 'Отримано змін з Drive: ${r.pulled}' : null),
      );
    } on FormatException catch (e) {
      state = state.copyWith(status: SyncStatus.error, message: e.message);
    } on CloudException catch (e) {
      if (!interactive && e.isAuth && ref.read(syncNeedsClickProvider)) {
        state = state.copyWith(status: SyncStatus.idle, message: webSyncHint);
        return;
      }
      state = state.copyWith(
        status: SyncStatus.error,
        message: e.isAuth && e.statusCode == 401
            ? 'Google просить підтвердити доступ — натисни «Синхронізувати зараз»'
            : e.message,
      );
    } on GoogleSignInException catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        message: 'Потрібно увійти в Google ще раз (${e.code.name})',
      );
    } on SocketException {
      state = state.copyWith(status: SyncStatus.error, message: _offline);
    } on http.ClientException {
      state = state.copyWith(status: SyncStatus.error, message: _offline);
    } on TimeoutException {
      state = state.copyWith(status: SyncStatus.error, message: _offline);
    } catch (e) {
      state = state.copyWith(
        status: SyncStatus.error,
        message: 'Помилка синхронізації: $e',
      );
    } finally {
      _busy = false;
    }
  }

  static const _offline =
      'Немає інтернету — зміни збережено на телефоні, синхронізую пізніше';

  void _startWatching() {
    _stopWatching();
    final db = _db;
    _changes = db
        .tableUpdates(
          TableUpdateQuery.onAllTables([
            db.transactions,
            db.categories,
            db.settings,
            db.wallets,
            db.walletCurrencies,
            db.transfers,
            db.assets,
            db.assetTrades,
            db.belongings,
            db.budgets,
            db.templates,
            db.goals,
            db.goalContributions,
            db.activityCategories,
            db.activities,
            db.todos,
            db.todoCompletions,
          ]),
        )
        .listen((_) {
          _debounce?.cancel();
          _debounce = Timer(changeDelay, () => syncNow(onlyIfChanged: true));
        });
    _lifecycle = AppLifecycleListener(
      onResume: () {
        final last = state.lastSyncAt;
        if (last == null ||
            DateTime.now().toUtc().difference(last) > resumeMinInterval) {
          syncNow();
        }
      },
    );
  }

  void _stopWatching() {
    _changes?.cancel();
    _changes = null;
    _debounce?.cancel();
    _debounce = null;
    _lifecycle?.dispose();
    _lifecycle = null;
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(
  SyncController.new,
);
