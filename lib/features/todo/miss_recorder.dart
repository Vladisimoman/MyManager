import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database.dart';
import '../finance/finance_providers.dart' show databaseProvider;
import 'todo_logic.dart';
import 'todo_screen.dart' show todoClockProvider;

/// Етап 25: пропуски повторюваних справ зберігаються в базі.
///
/// Коли день минув без позначки, повтор записується як «не виконано»
/// автоматично — при запуску, при поверненні в додаток і після півночі.
/// Записи мають найменший час зміни, тож справжня позначка з іншого
/// пристрою при синхронізації завжди перемагає.

/// Записати всі ще не збережені пропуски на [now]. Повертає, скільки записано.
Future<int> recordMissedRepeats(AppDatabase db, DateTime now) async {
  final list = [
    ...await db.watchTodos().first,
    ...await db.watchDeletedSeries().first,
  ];
  final records = await db.allTodoCompletions();
  final any = {for (final c in records) c.id};
  final active = {
    for (final c in records)
      if (!c.deleted) c.id,
  };
  final misses = <(String, DateTime)>[];
  for (final t in list) {
    for (final d in missesToRecord(
      t,
      now,
      closed: (d) => active.contains(AppDatabase.completionId(t.id, d)),
      hasRecord: (d) => any.contains(AppDatabase.completionId(t.id, d)),
    )) {
      misses.add((t.id, d));
    }
  }
  if (misses.isNotEmpty) await db.recordAutoMisses(misses);
  return misses.length;
}

final missRecorderProvider = Provider<MissRecorder>((ref) {
  final r = MissRecorder(
    ref.read(databaseProvider),
    ref.read(todoClockProvider),
  );
  ref.onDispose(r.dispose);
  r.start();
  return r;
});

class MissRecorder {
  MissRecorder(this._db, this._clock);

  final AppDatabase _db;
  final DateTime Function() _clock;
  AppLifecycleListener? _lifecycle;
  Timer? _midnight;
  Future<int>? _running;
  bool _disposed = false;

  void start() {
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(run()));
    Future(run);
  }

  /// Записати пропуски зараз (паралельні виклики об'єднуються).
  Future<int> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<int> _run() async {
    if (_disposed) return 0;
    try {
      return await recordMissedRepeats(_db, _clock());
    } catch (e) {
      debugPrint('Пропуски не записано: $e');
      return 0;
    } finally {
      _scheduleMidnight();
    }
  }

  /// Наступний запуск — одразу після півночі.
  void _scheduleMidnight() {
    _midnight?.cancel();
    if (_disposed) return;
    final now = _clock();
    final next = DateTime(now.year, now.month, now.day + 1, 0, 1);
    _midnight = Timer(next.difference(now), () => unawaited(run()));
  }

  void dispose() {
    _disposed = true;
    _midnight?.cancel();
    _lifecycle?.dispose();
  }
}
