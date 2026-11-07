import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:my_manager/data/database.dart';
import 'package:my_manager/features/activity/activity_stats.dart';

Activity act(String cat, DateTime s, DateTime? e) => Activity(
    id: '$cat${s.toIso8601String()}', categoryId: cat, start: s, end: e, note: null,
    createdAt: s, updatedAt: s, deleted: false);

ActivityCategory cat(String id, ActivityKind k) => ActivityCategory(
    id: id, name: id, icon: 'other', color: 0, kind: k, sortOrder: 0, hidden: false,
    updatedAt: DateTime(2000), deleted: false);

/// Етап 15: статистика Activity.
void main() {
  setUpAll(() => initializeDateFormatting('uk'));
  DateTime t(int d, int h, [int m = 0]) => DateTime(2026, 10, d, h, m);
  final cats = {
    'sleep': cat('sleep', ActivityKind.neutral),
    'work': cat('work', ActivityKind.useful),
    'yt': cat('yt', ActivityKind.waste),
  };

  test('період: день, тиждень з понеділка, місяць, зсув, підписи', () {
    final w = ActivityPeriod.of(ActivityPeriodKind.week, t(28, 12)); // середа
    expect(w.start, DateTime(2026, 10, 26));
    expect(w.days, 7);
    expect(w.shift(-1).start, DateTime(2026, 10, 19));
    final m = ActivityPeriod.of(ActivityPeriodKind.month, t(28, 12));
    expect(m.days, 31);
    expect(m.label, 'Жовтень 2026');
    expect(m.shift(1).start, DateTime(2026, 11));
    final c = ActivityPeriod.custom(DateTime(2026, 10, 1), DateTime(2026, 10, 10));
    expect(c.days, 10);
    expect(c.shift(-1).start, DateTime(2026, 9, 21));
    // Перехід на зимовий час (25.10) не ламає кількість днів.
    expect(ActivityPeriod.custom(DateTime(2026, 10, 24), DateTime(2026, 10, 26)).days, 3);
  });

  test('сон через північ ділиться між днями; таймер — до «зараз»', () {
    final list = [
      act('sleep', t(26, 23), t(27, 7)),
      act('work', t(27, 9), t(27, 17)),
      act('yt', t(27, 20), t(27, 22)),
      act('work', t(28, 9), null), // таймер
    ];
    final day27 = computeActivityStats(
      activities: list, categories: cats,
      period: ActivityPeriod.of(ActivityPeriodKind.day, t(27, 0)), now: t(28, 11));
    expect(day27.timeOf('sleep'), const Duration(hours: 7));
    expect(day27.timeOf('work'), const Duration(hours: 8));
    expect(day27.total, const Duration(hours: 17));
    expect(day27.byKind[ActivityKind.useful], const Duration(hours: 8));
    expect(day27.byKind[ActivityKind.waste], const Duration(hours: 2));
    expect(day27.share(ActivityKind.useful), closeTo(8 / 17, 0.001));
    expect(day27.byCategory.first.categoryId, 'work');

    final week = computeActivityStats(
      activities: list, categories: cats,
      period: ActivityPeriod.of(ActivityPeriodKind.week, t(28, 0)), now: t(28, 11));
    expect(week.timeOf('sleep'), const Duration(hours: 8));
    expect(week.timeOf('work'), const Duration(hours: 10)); // 8 + 2 (таймер)
    expect(week.elapsedDays, 3); // пн, вт, ср
    expect(week.averagePerDay(week.timeOf('work')), Duration(seconds: 10 * 3600 ~/ 3));
    expect(week.days[0].total, const Duration(hours: 1)); // пн: 23:00–24:00
    expect(week.days[1].total, const Duration(hours: 17));
    expect(week.days[2].byKind[ActivityKind.useful], const Duration(hours: 2));
    expect(week.days[3].total, Duration.zero); // майбутнє
  });

  test('формат різниці', () {
    expect(formatDelta(const Duration(minutes: 80)), '+1 год 20 хв');
    expect(formatDelta(const Duration(minutes: -35)), '−35 хв');
    expect(formatDelta(Duration.zero), 'без змін');
    expect(percent(0.414), '41 %');
  });
}
