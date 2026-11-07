import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../data/database.dart';
import '../finance/finance_providers.dart' show databaseProvider;
import '../todo/todo_logic.dart' show isRepeating;
import '../todo/todo_screen.dart';
import 'notification_plan.dart';

/// Сповіщення (етап 19): локальні, без сервера. Додаток сам планує їх на
/// [planDays] днів уперед і переплановує після кожної зміни справ.

/// Навігатор додатка — щоб відкрити To-do з сповіщення.
final appNavigatorKey = GlobalKey<NavigatorState>();

const notifEnabledKey = '${AppDatabase.localPrefix}notif_enabled';
const notifDigestKey = '${AppDatabase.localPrefix}notif_digest';
const notifAskedKey = '${AppDatabase.localPrefix}notif_asked';

const actionDone = 'done';
const actionSnooze = 'snooze';
const snoozeDuration = Duration(minutes: 10);

/// Тонкий шар над плагіном (у тестах — підробка).
abstract class NotificationBackend {
  Future<void> init({void Function(String? payload)? onTap});

  /// payload сповіщення, яким відкрили додаток (null — відкрили як завжди).
  Future<String?> launchPayload();

  Future<bool> areEnabled();
  Future<bool> requestPermission();
  Future<bool> canScheduleExact();
  Future<void> requestExactPermission();

  /// Замінити всі заплановані (крім «Відкласти») на [plan].
  Future<void> replacePlanned(
    List<PlannedNotification> plan, {
    required bool exact,
  });
  Future<void> showTest();
}

final notificationBackendProvider = Provider<NotificationBackend>(
  (ref) => PluginNotificationBackend(),
);

// ---------------- Плагін ----------------

const _remindersChannel = AndroidNotificationDetails(
  'reminders',
  'Нагадування про справи',
  channelDescription: 'У час справи або трохи раніше',
  importance: Importance.high,
  priority: Priority.high,
  icon: 'ic_notification',
  category: AndroidNotificationCategory.reminder,
  actions: [
    AndroidNotificationAction(actionDone, 'Виконано'),
    AndroidNotificationAction(actionSnooze, 'Відкласти на 10 хв'),
  ],
);

AndroidNotificationDetails _digestDetails(List<String> lines) =>
    AndroidNotificationDetails(
      'digest',
      'Ранкове зведення',
      channelDescription: 'Справи на сьогодні й ключові дати',
      importance: Importance.defaultImportance,
      icon: 'ic_notification',
      styleInformation: lines.isEmpty
          ? null
          : BigTextStyleInformation(lines.join('\n')),
    );

const _initSettings = InitializationSettings(
  android: AndroidInitializationSettings('ic_notification'),
);

bool _tzReady = false;
void _initTz() {
  if (_tzReady) return;
  tzdata.initializeTimeZones();
  _tzReady = true;
}

/// Момент у часі; сповіщення разові, тож зона — UTC (перепланування
/// після кожної зміни бере поточний час телефона).
tz.TZDateTime _at(DateTime t) => tz.TZDateTime.from(t.toUtc(), tz.UTC);

class PluginNotificationBackend implements NotificationBackend {
  final _plugin = FlutterLocalNotificationsPlugin();

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> init({void Function(String? payload)? onTap}) async {
    if (!_supported) return;
    _initTz();
    await _plugin.initialize(
      settings: _initSettings,
      onDidReceiveNotificationResponse: (r) {
        if (r.notificationResponseType ==
            NotificationResponseType.selectedNotification) {
          onTap?.call(r.payload);
        }
      },
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
  }

  @override
  Future<String?> launchPayload() async {
    if (!_supported) return null;
    final d = await _plugin.getNotificationAppLaunchDetails();
    final r = d?.notificationResponse;
    if (d?.didNotificationLaunchApp != true || r == null) return null;
    if (r.actionId != null) return null;
    return r.payload ?? '';
  }

  @override
  Future<bool> areEnabled() async =>
      _supported && (await _android?.areNotificationsEnabled() ?? false);

  @override
  Future<bool> requestPermission() async =>
      _supported && (await _android?.requestNotificationsPermission() ?? false);

  @override
  Future<bool> canScheduleExact() async =>
      _supported && (await _android?.canScheduleExactNotifications() ?? false);

  @override
  Future<void> requestExactPermission() async {
    if (_supported) await _android?.requestExactAlarmsPermission();
  }

  @override
  Future<void> replacePlanned(
    List<PlannedNotification> plan, {
    required bool exact,
  }) async {
    if (!_supported) return;
    for (final p in await _plugin.pendingNotificationRequests()) {
      if (p.id < snoozeIdBase) await _plugin.cancel(id: p.id);
    }
    final mode = exact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
    for (final n in plan) {
      await _plugin.zonedSchedule(
        id: n.id,
        scheduledDate: _at(n.at),
        notificationDetails: NotificationDetails(
          android: n.kind == NotificationKind.reminder
              ? _remindersChannel
              : _digestDetails(n.lines),
        ),
        androidScheduleMode: mode,
        title: n.title,
        body: n.body,
        payload: n.payload,
      );
    }
  }

  @override
  Future<void> showTest() async {
    if (!_supported) return;
    await _plugin.show(
      id: snoozeIdBase - 1,
      title: 'Перевірка сповіщень',
      body: 'Якщо ти це бачиш — нагадування працюють 👍',
      notificationDetails: NotificationDetails(
        android: _digestDetails(const []),
      ),
      payload: encodePayload(),
    );
  }
}

/// Кнопки «Виконано» / «Відкласти» — працюють без відкриття додатка,
/// у фоновому ізоляті.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(NotificationResponse r) async {
  DartPluginRegistrant.ensureInitialized();
  final p = decodePayload(r.payload);
  if (p == null || p.todoId == null) return;
  if (r.actionId == actionDone) {
    final db = AppDatabase();
    try {
      await markDoneFromNotification(db, p.todoId!, p.date);
    } finally {
      await db.close();
    }
  } else if (r.actionId == actionSnooze) {
    _initTz();
    final plugin = FlutterLocalNotificationsPlugin();
    await plugin.initialize(settings: _initSettings);
    await plugin.zonedSchedule(
      id: snoozeIdBase + DateTime.now().millisecondsSinceEpoch ~/ 1000 % 800000,
      scheduledDate: _at(DateTime.now().add(snoozeDuration)),
      notificationDetails: const NotificationDetails(
        android: _remindersChannel,
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      title: p.title,
      body: p.body,
      payload: r.payload,
    );
  }
}

/// «Виконано» зі сповіщення: разова справа — виконана; повторювана — лише цей повтор.
Future<void> markDoneFromNotification(
  AppDatabase db,
  String todoId,
  DateTime? date,
) async {
  final t = await (db.select(
    db.todos,
  )..where((x) => x.id.equals(todoId))).getSingleOrNull();
  if (t == null || t.deleted) return;
  if (isRepeating(t)) {
    if (date != null) await db.setOccurrenceDone(todoId, date, true);
  } else {
    await db.setTodoDone(todoId, true);
  }
}

// ---------------- Планувальник ----------------

class NotificationState {
  const NotificationState({
    this.enabled = true,
    this.digestMinutes = defaultDigestMinutes,
    this.permitted,
    this.exact,
    this.scheduled = 0,
  });

  final bool enabled;

  /// null — ранкове зведення вимкнено.
  final int? digestMinutes;

  /// Дозвіл на сповіщення / точний час (null — ще не перевірено).
  final bool? permitted;
  final bool? exact;

  /// Скільки сповіщень заплановано.
  final int scheduled;

  NotificationState copyWith({
    bool? enabled,
    int? Function()? digestMinutes,
    bool? permitted,
    bool? exact,
    int? scheduled,
  }) => NotificationState(
    enabled: enabled ?? this.enabled,
    digestMinutes: digestMinutes != null ? digestMinutes() : this.digestMinutes,
    permitted: permitted ?? this.permitted,
    exact: exact ?? this.exact,
    scheduled: scheduled ?? this.scheduled,
  );
}

final notificationControllerProvider =
    NotifierProvider<NotificationController, NotificationState>(
      NotificationController.new,
    );

class NotificationController extends Notifier<NotificationState> {
  static const changeDelay = Duration(seconds: 1);

  final _subs = <StreamSubscription<void>>[];
  Timer? _debounce;
  AppLifecycleListener? _lifecycle;
  bool _started = false;

  AppDatabase get _db => ref.read(databaseProvider);
  NotificationBackend get _backend => ref.read(notificationBackendProvider);

  @override
  NotificationState build() {
    ref.onDispose(_stop);
    Future(_start);
    return const NotificationState();
  }

  void _stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _debounce?.cancel();
    _lifecycle?.dispose();
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;
    try {
      await _backend.init(onTap: (_) => _openTodo());
    } catch (e) {
      debugPrint('Сповіщення недоступні: $e');
      return;
    }
    final enabled = await _db.getSetting(notifEnabledKey);
    final digest = await _db.getSetting(notifDigestKey);
    state = state.copyWith(
      enabled: enabled != '0',
      digestMinutes: () {
        if (digest == null) return defaultDigestMinutes;
        final v = int.tryParse(digest);
        return v == null || v < 0 ? null : v;
      },
    );
    await _askOnce();
    await refreshStatus();
    // Будь-яка зміна справ (і синхронізація з іншого пристрою) — перепланувати.
    _subs
      ..add(_db.watchTodos().listen((_) => _scheduleSoon()))
      ..add(_db.watchTodoCompletions().listen((_) => _scheduleSoon()));
    _lifecycle = AppLifecycleListener(
      onResume: () async {
        await refreshStatus();
        _scheduleSoon();
      },
    );
    if (await _backend.launchPayload() != null) _openTodo();
  }

  /// Перший запуск: дозвіл на сповіщення, потім — пояснення про точний час.
  Future<void> _askOnce() async {
    if (await _db.getSetting(notifAskedKey) != null) return;
    await _db.setSetting(notifAskedKey, '1');
    if (!state.enabled) return;
    final ok =
        await _backend.areEnabled() || await _backend.requestPermission();
    if (!ok || await _backend.canScheduleExact()) return;
    final context = appNavigatorKey.currentContext;
    if (context == null || !context.mounted) return;
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Нагадування вчасно'),
        content: const Text(
          'Щоб нагадування про справи приходили хвилина в хвилину, дозволь '
          'MyManager «Будильники й нагадування» на наступному екрані.\n\n'
          'Без цього вони можуть запізнюватися на кілька хвилин.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Пізніше'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Дозволити'),
          ),
        ],
      ),
    );
    if (go == true) await _backend.requestExactPermission();
  }

  Future<void> refreshStatus() async {
    state = state.copyWith(
      permitted: await _backend.areEnabled(),
      exact: await _backend.canScheduleExact(),
    );
  }

  void _scheduleSoon() {
    _debounce?.cancel();
    _debounce = Timer(changeDelay, () => unawaited(reschedule()));
  }

  /// Перепланувати все зараз.
  Future<void> reschedule() async {
    _debounce?.cancel();
    final now = ref.read(todoClockProvider)();
    final plan = state.enabled && state.permitted != false
        ? planNotifications(
            todos: await _db.watchTodos().first,
            completions: await _db.watchTodoCompletions().first,
            now: now,
            digestMinutes: state.digestMinutes,
          )
        : const <PlannedNotification>[];
    try {
      await _backend.replacePlanned(plan, exact: state.exact ?? false);
      state = state.copyWith(scheduled: plan.length);
    } catch (e) {
      debugPrint('Не вдалося запланувати сповіщення: $e');
    }
  }

  Future<void> setEnabled(bool v) async {
    await _db.setSetting(notifEnabledKey, v ? null : '0');
    state = state.copyWith(enabled: v);
    if (v && state.permitted == false) {
      await _backend.requestPermission();
      await refreshStatus();
    }
    await reschedule();
  }

  /// null — вимкнути ранкове зведення.
  Future<void> setDigest(int? minutes) async {
    await _db.setSetting(notifDigestKey, minutes == null ? '-1' : '$minutes');
    state = state.copyWith(digestMinutes: () => minutes);
    await reschedule();
  }

  Future<void> requestPermission() async {
    await _backend.requestPermission();
    await refreshStatus();
    await reschedule();
  }

  Future<void> requestExact() => _backend.requestExactPermission();

  Future<void> showTest() => _backend.showTest();

  void _openTodo() {
    final nav = appNavigatorKey.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    nav.push(MaterialPageRoute(builder: (_) => const TodoScreen()));
  }
}
