import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sync/sync_controller.dart';
import 'lock.dart';

/// Екрани захисту (етап 13): блокування, встановлення PIN, розділ у налаштуваннях.

// ---------------- Клавіатура PIN ----------------

class PinPad extends StatefulWidget {
  const PinPad({
    super.key,
    required this.onComplete,
    this.onBiometric,
    this.enabled = true,
  });

  /// Викликається, коли введено [pinLength] цифр. Повертає true — очистити поле.
  final Future<void> Function(String pin) onComplete;
  final VoidCallback? onBiometric;
  final bool enabled;

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> {
  String _pin = '';

  void clear() => setState(() => _pin = '');

  Future<void> _tap(String d) async {
    if (!widget.enabled || _pin.length >= pinLength) return;
    setState(() => _pin += d);
    if (_pin.length == pinLength) {
      final pin = _pin;
      await widget.onComplete(pin);
      if (mounted) setState(() => _pin = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget key(String d) =>
        _Key(label: d, onTap: widget.enabled ? () => _tap(d) : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < pinLength; i++)
              Container(
                key: ValueKey('pin-dot-$i'),
                width: 16,
                height: 16,
                margin: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i < _pin.length ? scheme.primary : Colors.transparent,
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
          ],
        ),
        const SizedBox(height: 32),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(d)],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 88,
              height: 72,
              child: widget.onBiometric == null
                  ? null
                  : IconButton(
                      tooltip: 'Відбиток пальця',
                      iconSize: 32,
                      icon: const Icon(Icons.fingerprint),
                      onPressed: widget.onBiometric,
                    ),
            ),
            key('0'),
            SizedBox(
              width: 88,
              height: 72,
              child: IconButton(
                tooltip: 'Стерти',
                icon: const Icon(Icons.backspace_outlined),
                onPressed: _pin.isEmpty
                    ? null
                    : () => setState(
                        () => _pin = _pin.substring(0, _pin.length - 1),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Key extends StatelessWidget {
  const _Key({required this.label, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SizedBox(
        width: 72,
        height: 64,
        child: TextButton(
          style: TextButton.styleFrom(shape: const CircleBorder()),
          onPressed: onTap,
          child: Text(label, style: const TextStyle(fontSize: 28)),
        ),
      ),
    );
  }
}

// ---------------- Обгортка всього додатка ----------------

/// Ставиться в MaterialApp.builder: закриває будь-який екран, поки додаток замкнено.
/// Замикає при запуску й після [lockAfterBackground] поза додатком.
class LockGate extends ConsumerStatefulWidget {
  const LockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<LockGate> createState() => _LockGateState();
}

class _LockGateState extends ConsumerState<LockGate>
    with WidgetsBindingObserver {
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    final now = ref.read(lockClockProvider)();
    if (s == AppLifecycleState.paused || s == AppLifecycleState.hidden) {
      _leftAt ??= now;
    } else if (s == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (left != null && now.difference(left) >= lockAfterBackground) {
        ref.read(lockControllerProvider.notifier).lock();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = ref.watch(lockControllerProvider);
    final covered = lock.loading || lock.locked;
    return Stack(
      children: [
        // Під замком екрани лишаються як були (зі станом), але невидимі й недоступні.
        Offstage(
          offstage: covered,
          child: TickerMode(enabled: !covered, child: widget.child),
        ),
        if (lock.loading)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: const SizedBox.expand(),
          ),
        if (!lock.loading && lock.locked)
          // Над Navigator немає Overlay — даємо свій (для підказок кнопок).
          Overlay(
            initialEntries: [OverlayEntry(builder: (_) => const LockScreen())],
          ),
      ],
    );
  }
}

// ---------------- Екран блокування ----------------

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;
  bool _forgot = false;
  bool _busy = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Відбиток — одразу, щоб не тягнутись до кнопки.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ref.read(lockControllerProvider).biometric) _bio();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _bio() async {
    await ref.read(lockControllerProvider.notifier).unlockWithBiometrics();
  }

  void _startTicker() {
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = ref.read(lockControllerProvider.notifier).waitLeft();
      setState(() {});
      if (left == null) _tick?.cancel();
    });
  }

  Future<void> _onPin(String pin) async {
    final ctrl = ref.read(lockControllerProvider.notifier);
    final r = await ctrl.unlock(pin);
    if (!mounted || r == PinResult.ok) return;
    final s = ref.read(lockControllerProvider);
    if (ctrl.waitLeft() != null) {
      _startTicker();
      setState(() => _message = null);
    } else {
      final left = maxAttempts - s.failed % maxAttempts;
      setState(() => _message = 'Невірний PIN. Залишилось спроб: $left');
    }
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    final r = await ref.read(lockControllerProvider.notifier).resetWithGoogle();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (r) {
        ResetResult.done => null,
        ResetResult.noAccount =>
          'На цьому телефоні не було входу в Google. Скинути PIN можна лише очищенням '
              'даних додатка (Налаштування Android → Додатки → MyManager → Сховище). '
              'Дані повернуться хіба що з резервної копії у файлі.',
        ResetResult.otherAccount =>
          'Це інший акаунт. Увійди в той, що використовується для синхронізації: '
              '${ref.read(syncControllerProvider).email ?? ''}',
        ResetResult.cancelled => 'Вхід скасовано',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lock = ref.watch(lockControllerProvider);
    final wait = ref.read(lockControllerProvider.notifier).waitLeft();
    return Material(
      color: scheme.surface,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 40, color: scheme.primary),
                const SizedBox(height: 12),
                Text(
                  'MyManager',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  _forgot ? 'Скидання PIN' : 'Введи PIN',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 28),
                if (!_forgot)
                  PinPad(
                    enabled: wait == null,
                    onComplete: _onPin,
                    onBiometric: lock.biometric ? _bio : null,
                  )
                else ...[
                  Text(
                    'Увійди в той самий Google-акаунт, що й для синхронізації, — '
                    'PIN вимкнеться, дані залишаться. Потім зможеш задати новий у налаштуваннях.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _busy ? null : _reset,
                    icon: const Icon(Icons.login),
                    label: const Text('Увійти через Google'),
                  ),
                ],
                const SizedBox(height: 12),
                if (wait != null)
                  Text(
                    'Забагато спроб. Зачекай ${wait.inSeconds + 1} с',
                    style: TextStyle(color: scheme.error),
                  ),
                if (_message != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() {
                    _forgot = !_forgot;
                    _message = null;
                  }),
                  child: Text(_forgot ? 'Назад до PIN' : 'Забув PIN?'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Встановлення / зміна / вимкнення PIN ----------------

enum PinSetupMode { create, change, disable }

class PinSetupScreen extends ConsumerStatefulWidget {
  const PinSetupScreen({super.key, required this.mode});
  final PinSetupMode mode;

  @override
  ConsumerState<PinSetupScreen> createState() => _PinSetupScreenState();
}

class _PinSetupScreenState extends ConsumerState<PinSetupScreen> {
  /// 0 — поточний PIN (зміна / вимкнення), 1 — новий, 2 — повтор.
  late int _step = widget.mode == PinSetupMode.create ? 1 : 0;
  String? _first;
  String? _error;

  String get _title => switch (_step) {
    0 => 'Введи поточний PIN',
    1 => 'Придумай PIN з $pinLength цифр',
    _ => 'Повтори PIN',
  };

  Future<void> _onPin(String pin) async {
    final ctrl = ref.read(lockControllerProvider.notifier);
    if (_step == 0) {
      if (!await ctrl.verify(pin)) {
        setState(() => _error = 'Невірний PIN');
        return;
      }
      if (widget.mode == PinSetupMode.disable) {
        await ctrl.disable();
        if (mounted) Navigator.of(context).pop(true);
        return;
      }
      setState(() {
        _step = 1;
        _error = null;
      });
      return;
    }
    if (_step == 1) {
      setState(() {
        _first = pin;
        _step = 2;
        _error = null;
      });
      return;
    }
    if (pin != _first) {
      setState(() {
        _step = 1;
        _first = null;
        _error = 'PIN не збігся — спробуй ще раз';
      });
      return;
    }
    await ctrl.setPin(pin);
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(switch (widget.mode) {
          PinSetupMode.create => 'Новий PIN',
          PinSetupMode.change => 'Змінити PIN',
          PinSetupMode.disable => 'Вимкнути PIN',
        }),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 24),
                PinPad(key: ValueKey(_step), onComplete: _onPin),
                const SizedBox(height: 12),
                if (_error != null)
                  Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------- Розділ «Захист» у налаштуваннях ----------------

final biometricsAvailableProvider = FutureProvider<bool>(
  (ref) => ref.watch(biometricsProvider).available(),
);

class SecurityCard extends ConsumerWidget {
  const SecurityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lock = ref.watch(lockControllerProvider);
    final bioAvailable = ref.watch(biometricsAvailableProvider).value ?? false;
    final signedIn = ref.watch(syncControllerProvider).email != null;
    final ctrl = ref.read(lockControllerProvider.notifier);

    Future<void> open(PinSetupMode mode) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => PinSetupScreen(mode: mode)));

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('Блокування PIN-кодом'),
            subtitle: Text(
              lock.enabled
                  ? 'Питає PIN при запуску й після хвилини поза додатком'
                  : (signedIn
                        ? 'Якщо забудеш PIN — скинеш входом у Google'
                        : 'Порада: спершу увійди в Google — тоді забутий PIN можна скинути'),
            ),
            value: lock.enabled,
            onChanged: (on) =>
                open(on ? PinSetupMode.create : PinSetupMode.disable),
          ),
          if (lock.enabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Змінити PIN'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => open(PinSetupMode.change),
            ),
            if (bioAvailable) ...[
              const Divider(height: 1),
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint),
                title: const Text('Відбиток пальця'),
                subtitle: const Text('Замість PIN; PIN лишається запасним'),
                value: lock.biometric,
                onChanged: (on) async {
                  final ok = await ctrl.setBiometric(on);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Відбиток не підтверджено')),
                    );
                  }
                },
              ),
            ],
          ],
        ],
      ),
    );
  }
}
