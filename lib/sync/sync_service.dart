import '../data/database.dart';
import 'cloud_store.dart';
import 'snapshot.dart';

class SyncResult {
  const SyncResult({
    required this.pulled,
    required this.uploaded,
    this.resetApplied = false,
  });

  /// Скільки записів прийшло з Drive.
  final int pulled;

  /// Чи вивантажувались дані на Drive (false — там уже актуальна версія).
  final bool uploaded;

  /// Дані на цьому пристрої очищено, бо їх видалили на іншому.
  final bool resetApplied;
}

/// Синхронізація Finance з хмарою:
/// 1) завантажити `finance.json`; 2) злити з локальною базою;
/// 3) зберегти попередню версію як `finance.backup.json`; 4) вивантажити результат.
///
/// Якщо два пристрої вивантажать одночасно, нічого не губиться: кожен зберігає
/// свої зміни локально й донесе їх при наступній синхронізації.
///
/// Повне видалення даних позначається міткою [SettingKeys.dataResetId]:
/// пристрій зі старішою міткою очищує свої дані, а не повертає старі записи на Drive.
class SyncService {
  SyncService(this._db, this._store);

  final AppDatabase _db;
  final CloudStore _store;

  static const mainFile = 'finance.json';
  static const backupFile = 'finance.backup.json';
  static const lastSyncKey = '${AppDatabase.localPrefix}last_sync_at';

  Future<SyncResult> sync() async {
    final remoteText = await _store.read(mainFile);
    var pulled = 0;
    var resetApplied = false;

    if (remoteText != null) {
      // Якщо файл пошкоджений — FormatException, і ми нічого не перезаписуємо.
      final remote = FinanceSnapshot.decode(remoteText);
      final local = await _localResetMarker();
      final remoteMark = remote.resetMarker;

      if (remoteMark?.value == local?.value) {
        pulled = (await _db.mergeSnapshot(remote)).total;
      } else if (remoteMark != null &&
          (local == null || remoteMark.updatedAt.isAfter(local.updatedAt))) {
        // Дані видалили на іншому пристрої — очищуємо свої й беремо нові з Drive.
        await _db.wipeAllData(resetId: remoteMark.value);
        pulled = (await _db.mergeSnapshot(remote)).total;
        resetApplied = true;
      }
      // Інакше дані видалили тут — старі записи з Drive не зливаємо, а перезаписуємо.
    }

    final localText = (await _db.exportSnapshot()).encode();
    var uploaded = false;
    if (localText != remoteText) {
      if (remoteText != null) await _store.write(backupFile, remoteText);
      await _store.write(mainFile, localText);
      uploaded = true;
    }

    await _db.setSetting(lastSyncKey, DateTime.now().toUtc().toIso8601String());
    return SyncResult(
      pulled: pulled,
      uploaded: uploaded,
      resetApplied: resetApplied,
    );
  }

  Future<Setting?> _localResetMarker() {
    return (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(SettingKeys.dataResetId))).getSingleOrNull();
  }

  /// Текст локальних даних — щоб не синхронізувати, коли нічого не змінилось.
  Future<String> localFingerprint() async =>
      (await _db.exportSnapshot()).encode();
}
