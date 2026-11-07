import 'package:my_manager/features/notifications/notification_plan.dart';
import 'package:my_manager/features/notifications/notifications.dart';

/// Сповіщення в тестах: нічого не показуємо, лише запам'ятовуємо розклад.
class FakeNotificationBackend implements NotificationBackend {
  FakeNotificationBackend({this.permitted = true, this.exact = true});

  bool permitted;
  bool exact;
  int permissionRequests = 0;
  int exactRequests = 0;
  int tests = 0;
  List<PlannedNotification> planned = const [];
  bool? plannedExact;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {}

  @override
  Future<String?> launchPayload() async => null;

  @override
  Future<bool> areEnabled() async => permitted;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permitted;
  }

  @override
  Future<bool> canScheduleExact() async => exact;

  @override
  Future<void> requestExactPermission() async => exactRequests++;

  @override
  Future<void> replacePlanned(
    List<PlannedNotification> plan, {
    required bool exact,
  }) async {
    planned = plan;
    plannedExact = exact;
  }

  @override
  Future<void> showTest() async => tests++;
}
