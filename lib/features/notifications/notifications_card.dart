import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../todo/todo_logic.dart' show minutesLabel;
import 'notification_plan.dart';
import 'notifications.dart';

/// Налаштування → Сповіщення (етап 19).
class NotificationsCard extends ConsumerWidget {
  const NotificationsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Браузер (етап 21): сповіщення приходять лише на телефон.
    if (kIsWeb) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.notifications_off_outlined),
          title: Text('Сповіщення — у додатку на телефоні'),
          subtitle: Text('Браузер не нагадує про справи'),
        ),
      );
    }
    final st = ref.watch(notificationControllerProvider);
    final ctrl = ref.read(notificationControllerProvider.notifier);
    final scheme = Theme.of(context).colorScheme;
    final digest = st.digestMinutes;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Нагадування про справи'),
            subtitle: const Text('Час нагадування — у кожній справі'),
            value: st.enabled,
            onChanged: ctrl.setEnabled,
          ),
          if (st.enabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.wb_sunny_outlined),
              title: const Text('Ранкове зведення'),
              subtitle: Text(
                digest == null
                    ? 'Вимкнено'
                    : 'О ${minutesLabel(digest)}: справи на день і ключові дати',
              ),
              trailing: Switch(
                value: digest != null,
                onChanged: (v) =>
                    ctrl.setDigest(v ? defaultDigestMinutes : null),
              ),
              onTap: () async {
                final m = digest ?? defaultDigestMinutes;
                final t = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60),
                  helpText: 'Час ранкового зведення',
                );
                if (t != null) await ctrl.setDigest(t.hour * 60 + t.minute);
              },
            ),
            if (st.permitted == false) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.warning_amber_rounded, color: scheme.error),
                title: const Text('Сповіщення заборонені'),
                subtitle: const Text(
                  'Телефон не показуватиме нагадування, поки не дозволиш.',
                ),
                trailing: TextButton(
                  onPressed: ctrl.requestPermission,
                  child: const Text('Дозволити'),
                ),
              ),
            ] else if (st.exact == false) ...[
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.timer_outlined, color: scheme.tertiary),
                title: const Text('Можуть запізнюватися'),
                subtitle: const Text(
                  'Дозволь «Будильники й нагадування», щоб приходили хвилина в хвилину.',
                ),
                trailing: TextButton(
                  onPressed: ctrl.requestExact,
                  child: const Text('Дозволити'),
                ),
              ),
            ],
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notifications_active_outlined),
              title: const Text('Надіслати тестове'),
              subtitle: Text(
                st.scheduled == 0
                    ? 'Заплановано: нічого'
                    : 'Заплановано на 2 тижні: ${st.scheduled}',
              ),
              onTap: ctrl.showTest,
            ),
          ],
        ],
      ),
    );
  }
}
