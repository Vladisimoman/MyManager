import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';

import '../../data/database.dart';
import '../../sync/sync_controller.dart';
import '../finance/finance_providers.dart';

/// Захист (етап 13): PIN і відбиток пальця.
///
/// PIN зберігається лише на цьому телефоні (налаштування `local.*` не
/// синхронізуються), у вигляді солі й SHA-256 — сам PIN ніде не записано.

const pinKey = '${AppDatabase.localPrefix}pin';
const biometricKey = '${AppDatabase.localPrefix}lock_biometric';
const pinLength = 4;

/// Скільки бути поза додатком, щоб при поверненні знову спитав PIN.
const lockAfterBackground = Duration(minutes: 1);

/// Після стількох помилок поспіль — пауза [lockoutDuration].
const maxAttempts = 5;
const lockoutDuration = Duration(seconds: 30);

String hashPin(String pin, String salt) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

String _newSalt() {
  final r = Random.secure();
  return base64Url.encode(List<int>.generate(16, (_) => r.nextInt(256)));
}

/// Відбиток / обличчя телефона. У тестах підміняється.
abstract class Biometrics {
  Future<bool> available();
  Future<bool> authenticate();
}

class DeviceBiometrics implements Biometrics {
  final _auth = LocalAuthentication();

  @override
  Future<bool> available() async {
    // У браузері відбитка немає — лише PIN.
    if (kIsWeb) return false;
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Розблокувати MyManager',
        biometricOnly: true,
      );
    } catch (_) {
      return false;
    }
  }
}

final biometricsProvider = Provider<Biometrics>((ref) => DeviceBiometrics());

/// Годинник — щоб у тестах перевіряти паузи й «хвилину у фоні».
final lockClockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

@immutable
class LockState {
  const LockState({
    this.loading = true,
    this.enabled = false,
    this.locked = false,
    this.biometric = false,
    this.failed = 0,
    this.lockedUntil,
  });

  /// Ще читаємо налаштування — екран прикритий, щоб не блимнули дані.
  final bool loading;
  final bool enabled;
  final bool locked;
  final bool biometric;
  final int failed;
  final DateTime? lockedUntil;

  LockState copyWith({
    bool? loading,
    bool? enabled,
    bool? locked,
    bool? biometric,
    int? failed,
    DateTime? lockedUntil,
    bool clearLockedUntil = false,
  }) => LockState(
    loading: loading ?? this.loading,
    enabled: enabled ?? this.enabled,
    locked: locked ?? this.locked,
    biometric: biometric ?? this.biometric,
    failed: failed ?? this.failed,
    lockedUntil: clearLockedUntil ? null : (lockedUntil ?? this.lockedUntil),
  );
}

/// Результат введення PIN на екрані блокування.
enum PinResult { ok, wrong, waiting }

/// Результат «Забув PIN → вхід у Google».
enum ResetResult { done, noAccount, otherAccount, cancelled }

class LockController extends Notifier<LockState> {
  AppDatabase get _db => ref.read(databaseProvider);
  DateTime _now() => ref.read(lockClockProvider)();

  @override
  LockState build() {
    _load();
    return const LockState();
  }

  Future<void> _load() async {
    try {
      final pin = await _db.getSetting(pinKey);
      final bio = await _db.getSetting(biometricKey);
      state = LockState(
        loading: false,
        enabled: pin != null,
        locked: pin != null,
        biometric: pin != null && bio == '1',
      );
    } catch (_) {
      // База недоступна — не замикаємо користувача.
      state = const LockState(loading: false);
    }
  }

  Future<bool> _check(String pin) async {
    final stored = await _db.getSetting(pinKey);
    if (stored == null) return true;
    final i = stored.indexOf(':');
    if (i < 0) return false;
    return hashPin(pin, stored.substring(0, i)) == stored.substring(i + 1);
  }

  /// Скільки ще чекати після помилок (null — можна вводити).
  Duration? waitLeft() {
    final until = state.lockedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    return left.isNegative ? null : left;
  }

  Future<PinResult> unlock(String pin) async {
    if (waitLeft() != null) return PinResult.waiting;
    if (await _check(pin)) {
      state = state.copyWith(locked: false, failed: 0, clearLockedUntil: true);
      return PinResult.ok;
    }
    final failed = state.failed + 1;
    state = state.copyWith(
      failed: failed,
      lockedUntil: failed % maxAttempts == 0
          ? _now().add(lockoutDuration)
          : null,
    );
    return PinResult.wrong;
  }

  /// Перевірка поточного PIN у налаштуваннях (без зміни стану блокування).
  Future<bool> verify(String pin) => _check(pin);

  Future<bool> unlockWithBiometrics() async {
    if (!state.biometric) return false;
    final ok = await ref.read(biometricsProvider).authenticate();
    if (ok) {
      state = state.copyWith(locked: false, failed: 0, clearLockedUntil: true);
    }
    return ok;
  }

  void lock() {
    if (state.enabled) state = state.copyWith(locked: true);
  }

  Future<void> setPin(String pin) async {
    final salt = _newSalt();
    await _db.setSetting(pinKey, '$salt:${hashPin(pin, salt)}');
    state = state.copyWith(
      loading: false,
      enabled: true,
      locked: false,
      failed: 0,
      clearLockedUntil: true,
    );
  }

  Future<void> disable() async {
    await _db.setSetting(pinKey, null);
    await _db.setSetting(biometricKey, null);
    state = const LockState(loading: false);
  }

  /// Вмикає відбиток лише після успішної перевірки ним.
  Future<bool> setBiometric(bool on) async {
    if (on && !await ref.read(biometricsProvider).authenticate()) return false;
    await _db.setSetting(biometricKey, on ? '1' : null);
    state = state.copyWith(biometric: on);
    return true;
  }

  /// «Забув PIN»: вхід у той самий Google-акаунт, що й для синхронізації.
  Future<ResetResult> resetWithGoogle() async {
    final saved = await _db.getSetting(SyncController.emailKey);
    if (saved == null) return ResetResult.noAccount;
    final String email;
    try {
      email = await ref.read(syncAuthProvider).signIn();
    } catch (_) {
      return ResetResult.cancelled;
    }
    if (email.trim().toLowerCase() != saved.trim().toLowerCase()) {
      return ResetResult.otherAccount;
    }
    await disable();
    return ResetResult.done;
  }
}

final lockControllerProvider = NotifierProvider<LockController, LockState>(
  LockController.new,
);
