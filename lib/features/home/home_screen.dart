import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../activity/activity_screen.dart';
import '../finance/finance_home_screen.dart';
import '../notifications/notifications.dart';
import '../settings/settings_screen.dart';
import '../todo/miss_recorder.dart';
import '../todo/todo_logic.dart';
import '../todo/todo_screen.dart';
import '../../sync/sync_controller.dart';

/// Головне меню: три модулі додатку.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Тримає синхронізацію активною, поки відкритий додаток.
    ref.watch(syncControllerProvider);
    // І сповіщення (етап 19): планує нагадування після кожної зміни справ.
    ref.watch(notificationControllerProvider);
    // Етап 25: пропуски повторюваних справ записуються в базу.
    ref.watch(missRecorderProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyManager'),
        actions: [
          IconButton(
            tooltip: 'Налаштування',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => _open(context, const SettingsScreen()),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _ModuleButton(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Finance',
                  subtitle: 'Надходження, витрати, баланс',
                  onTap: () => _open(context, const FinanceHomeScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ModuleButton(
                  icon: Icons.insights_outlined,
                  title: 'Activity',
                  subtitle: 'Що робив і скільки часу',
                  onTap: () => _open(context, const ActivityScreen()),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: _ModuleButton(
                  icon: Icons.checklist_outlined,
                  title: 'To-do',
                  subtitle: _todoSubtitle(ref),
                  onTap: () => _open(context, const TodoScreen()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// «Сьогодні: 3 справи» / «На сьогодні все зроблено».
  static String _todoSubtitle(WidgetRef ref) {
    final list = ref.watch(todosProvider).value;
    if (list == null || list.isEmpty) return 'Справи й нагадування';
    final n = todayLeft(
      list,
      ref.watch(todoClockProvider)(),
      completions: ref.watch(todoCompletionsProvider).value ?? const [],
    );
    if (n == 0) return 'На сьогодні все зроблено';
    final word = n % 10 == 1 && n % 100 != 11
        ? 'справа'
        : (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)
              ? 'справи'
              : 'справ');
    return 'Сьогодні: $n $word';
  }

  void _open(BuildContext context, Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _ModuleButton extends StatelessWidget {
  const _ModuleButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = scheme.onPrimaryContainer;
    return Material(
      color: scheme.primaryContainer,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Icon(icon, size: 40, color: fg),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(color: fg, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(color: fg)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: fg),
            ],
          ),
        ),
      ),
    );
  }
}
