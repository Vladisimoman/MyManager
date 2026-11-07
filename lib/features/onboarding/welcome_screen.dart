import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../core/theme.dart';
import '../../data/database.dart';
import '../../sync/sync_controller.dart';
import '../finance/finance_providers.dart';
import '../home/home_screen.dart';
import '../settings/initial_balance.dart';

const onboardingDoneKey = '${AppDatabase.localPrefix}onboarding_done';

/// Чи показувати вітання: лише на свіжій установці без записів.
/// Якщо записи вже є (оновлення з попередньої версії) — одразу позначаємо як пройдене.
final needsOnboardingProvider = FutureProvider<bool>((ref) async {
  final db = ref.watch(databaseProvider);
  if (await db.getSetting(onboardingDoneKey) != null) return false;
  if (await db.countEntries() > 0) {
    await db.setSetting(onboardingDoneKey, '1');
    return false;
  }
  return true;
});

/// Перший екран додатку: вітання або головне меню.
class StartGate extends ConsumerWidget {
  const StartGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(needsOnboardingProvider)
        .when(
          loading: () =>
              const Scaffold(body: Center(child: CircularProgressIndicator())),
          // Якщо щось пішло не так — не блокуємо користувача, показуємо меню.
          error: (_, _) => const HomeScreen(),
          data: (needs) => needs ? const WelcomeScreen() : const HomeScreen(),
        );
  }
}

/// Два кроки: 1) вхід у Google (щоб підтягнути дані з Drive) або «Пропустити»;
/// 2) початковий баланс (необов'язково).
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  int _step = 0;
  bool _busy = false;
  final _balance = TextEditingController();
  String? _balanceError;

  @override
  void dispose() {
    _balance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: _step == 0
              ? _signInStep(sync, text, scheme)
              : _balanceStep(text, scheme),
        ),
      ),
    );
  }

  Widget _signInStep(SyncState sync, TextTheme text, ColorScheme scheme) {
    final canSignIn = sync.status != SyncStatus.notConfigured;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Icon(
          Icons.account_balance_wallet_outlined,
          size: 72,
          color: scheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Вітаю в MyManager',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'Облік надходжень і витрат у кількох валютах. '
          'Дані зберігаються на телефоні й синхронізуються з твоїм Google Drive.',
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        if (sync.message != null && sync.status != SyncStatus.idle)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              sync.message!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.expense),
            ),
          ),
        if (canSignIn)
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: _busy ? null : _signIn,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.login),
              label: const Text('Увійти через Google'),
            ),
          ),
        if (canSignIn)
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'Якщо ти вже користувався MyManager — записи підтягнуться з Drive.',
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        TextButton(
          onPressed: _busy ? null : () => setState(() => _step = 1),
          child: Text(canSignIn ? 'Пропустити' : 'Далі'),
        ),
      ],
    );
  }

  Widget _balanceStep(TextTheme text, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Text(
          'Скільки в тебе готівки?',
          textAlign: TextAlign.center,
          style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text(
          'Це початковий баланс гаманця «Готівка» в євро. Інші валюти, картки й рахунки '
          'додаси в розділі «Гаманці». Можна пропустити.',
          textAlign: TextAlign.center,
          style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        InitialBalanceField(controller: _balance, errorText: _balanceError),
        const Spacer(),
        SizedBox(
          height: 52,
          child: FilledButton(
            onPressed: _busy ? null : _finishWithBalance,
            child: const Text('Почати'),
          ),
        ),
        TextButton(
          onPressed: _busy ? null : _finish,
          child: const Text('Пропустити'),
        ),
      ],
    );
  }

  Future<void> _signIn() async {
    setState(() => _busy = true);
    final ctrl = ref.read(syncControllerProvider.notifier);
    await ctrl.signIn();
    if (!mounted) return;
    final state = ref.read(syncControllerProvider);
    if (!state.signedIn) {
      setState(() => _busy = false);
      return;
    }
    // Якщо з Drive прийшли записи — початковий баланс уже теж прийшов, вітання не потрібне.
    final db = ref.read(databaseProvider);
    if (await db.countEntries() > 0) {
      await _finish();
      return;
    }
    final initial = await db.getInitialCents(
      AppDatabase.mainWalletId,
      baseCurrency,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _step = 1;
      if (initial != 0) _balance.text = signedCentsToInput(initial);
    });
  }

  Future<void> _finishWithBalance() async {
    final t = _balance.text.trim();
    if (t.isNotEmpty) {
      final cents = parseSignedAmountToCents(t);
      if (cents == null) {
        setState(() => _balanceError = 'Невірна сума, напр. 1250,50');
        return;
      }
      setState(() => _busy = true);
      await ref
          .read(databaseProvider)
          .setWalletCurrency(AppDatabase.mainWalletId, baseCurrency, cents);
    }
    await _finish();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    await ref.read(databaseProvider).setSetting(onboardingDoneKey, '1');
    ref.invalidate(needsOnboardingProvider);
  }
}
