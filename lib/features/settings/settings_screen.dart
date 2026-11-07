import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../sync/sync_controller.dart';
import '../../core/version.dart';
import '../notifications/notifications_card.dart';
import '../security/lock_screen.dart';
import 'backup.dart';
import 'categories_screen.dart';
import '../onboarding/welcome_screen.dart';
import '../wallets/wallets_screen.dart';

/// Налаштування: фінанси (гаманці, категорії), синхронізація з Drive, сповіщення, видалення даних.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncControllerProvider);
    final ctrl = ref.read(syncControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Налаштування')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Фінанси',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.account_balance_wallet_outlined),
                    title: const Text('Гаманці'),
                    subtitle: const Text(
                      'Валюти й початковий баланс кожного гаманця',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const WalletsScreen()),
                    ),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.category_outlined),
                    title: const Text('Категорії'),
                    subtitle: const Text('Додати, перейменувати, приховати'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const CategoriesScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Синхронізація з Google Drive',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Дані зберігаються в прихованій папці MyManager на твоєму Google Drive. '
              'Додаток не бачить інших файлів на диску.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: switch (sync.status) {
                  SyncStatus.notConfigured => const Text(
                    'Синхронізація ще не налаштована в цій збірці (немає Client ID).',
                  ),
                  SyncStatus.signedOut => _SignedOut(
                    state: sync,
                    onSignIn: ctrl.signIn,
                  ),
                  _ => _SignedIn(
                    state: sync,
                    onSync: () => ctrl.syncNow(interactive: true),
                    onSignOut: () => _confirmSignOut(context, ctrl),
                  ),
                },
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'Сповіщення',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const NotificationsCard(),
            const SizedBox(height: 28),
            Text(
              'Захист',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const SecurityCard(),
            const SizedBox(height: 28),
            Text(
              'Резервна копія',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Окремо від Google Drive: файл з усіма даними, який можна зберегти будь-де.',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            const BackupCard(),
            const SizedBox(height: 28),
            Text(
              'Небезпечна зона',
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.expense,
              ),
            ),
            const SizedBox(height: 8),
            Card(
              clipBehavior: Clip.antiAlias,
              child: ListTile(
                leading: const Icon(
                  Icons.delete_forever_outlined,
                  color: AppColors.expense,
                ),
                title: const Text('Видалити всі дані'),
                subtitle: Text(
                  sync.signedIn
                      ? 'На телефоні й на Google Drive. Почати з нуля.'
                      : 'На цьому телефоні. Почати з нуля.',
                ),
                onTap: () => _confirmWipe(context, ref),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                'MyManager $appVersion',
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmWipe(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _WipeDialog(),
    );
    if (ok != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(syncControllerProvider.notifier).wipeAllData();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не вдалося видалити дані: $e')),
      );
      return;
    }
    // Повертаємось на старт: покажеться екран вітання.
    ref.invalidate(needsOnboardingProvider);
    navigator.popUntil((r) => r.isFirst);
    messenger.showSnackBar(const SnackBar(content: Text('Усі дані видалено')));
  }

  Future<void> _confirmSignOut(
    BuildContext context,
    SyncController ctrl,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вийти з Google?'),
        content: const Text(
          'Записи залишаться на телефоні й на Drive. Синхронізація зупиниться, '
          'доки ти не увійдеш знову.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Скасувати'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Вийти'),
          ),
        ],
      ),
    );
    if (ok == true) await ctrl.signOut();
  }
}

class _SignedOut extends StatelessWidget {
  const _SignedOut({required this.state, required this.onSignIn});
  final SyncState state;
  final VoidCallback onSignIn;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Увійди, щоб дані зберігались на Drive і були доступні на інших пристроях.',
        ),
        if (state.message != null) ...[
          const SizedBox(height: 8),
          Text(
            state.message!,
            style: const TextStyle(color: AppColors.expense),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSignIn,
          icon: const Icon(Icons.login),
          label: const Text('Увійти через Google'),
        ),
      ],
    );
  }
}

class _SignedIn extends StatelessWidget {
  const _SignedIn({
    required this.state,
    required this.onSync,
    required this.onSignOut,
  });
  final SyncState state;
  final VoidCallback onSync;
  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final syncing = state.status == SyncStatus.syncing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.account_circle_outlined, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                state.email!,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SyncStatusLine(state: state),
        if (state.message != null) ...[
          const SizedBox(height: 6),
          Text(
            state.message!,
            style: TextStyle(
              fontSize: 13,
              color: state.status == SyncStatus.error
                  ? AppColors.expense
                  : scheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: syncing ? null : onSync,
          icon: syncing
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.sync),
          label: const Text('Синхронізувати зараз'),
        ),
        const SizedBox(height: 4),
        TextButton(
          onPressed: syncing ? null : onSignOut,
          child: const Text('Вийти з акаунта'),
        ),
      ],
    );
  }
}

/// Рядок «Синхронізовано 26.10 о 15:02» / «Синхронізація…» / «Помилка».
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key, required this.state, this.compact = false});
  final SyncState state;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, Color color, String text) = switch (state.status) {
      SyncStatus.notConfigured => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        'Синхронізація не налаштована',
      ),
      SyncStatus.signedOut => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        'Не синхронізовано — увійди в Google у налаштуваннях',
      ),
      SyncStatus.syncing => (
        Icons.cloud_sync_outlined,
        scheme.primary,
        'Синхронізація…',
      ),
      SyncStatus.error => (
        Icons.cloud_off_outlined,
        AppColors.expense,
        compact
            ? 'Синхронізація не вдалась — відкрий налаштування'
            : 'Остання спроба не вдалась',
      ),
      SyncStatus.idle => (
        Icons.cloud_done_outlined,
        scheme.onSurfaceVariant,
        state.lastSyncAt == null
            ? 'Ще не синхронізовано'
            : 'Синхронізовано ${DateFormat("dd.MM 'о' HH:mm", 'uk').format(state.lastSyncAt!.toLocal())}',
      ),
    };
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 13, color: color)),
        ),
      ],
    );
  }
}

/// Підтвердження видалення: кнопка активна, лише коли введено «ВИДАЛИТИ».
class _WipeDialog extends StatefulWidget {
  const _WipeDialog();

  @override
  State<_WipeDialog> createState() => _WipeDialogState();
}

class _WipeDialogState extends State<_WipeDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _controller.text.trim().toUpperCase() == 'ВИДАЛИТИ';
    return AlertDialog(
      title: const Text('Видалити всі дані?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Буде видалено всі записи, перекази, гаманці й твої категорії — на телефоні '
            'й на Google Drive. На Drive лишиться одна резервна копія попередніх даних.\n\n'
            'Щоб підтвердити, введи слово ВИДАЛИТИ.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'ВИДАЛИТИ',
            ),
            onChanged: (_) => setState(() {}),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Скасувати'),
        ),
        TextButton(
          onPressed: ready ? () => Navigator.pop(context, true) : null,
          style: TextButton.styleFrom(foregroundColor: AppColors.expense),
          child: const Text('Видалити все'),
        ),
      ],
    );
  }
}
