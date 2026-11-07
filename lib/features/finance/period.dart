import 'package:intl/intl.dart';

enum PeriodKind { week, month, year, custom }

/// Проміжок часу [start, end) у локальних днях. Тиждень починається з понеділка.
class Period {
  const Period._(this.kind, this.start, this.end);

  final PeriodKind kind;
  final DateTime start; // включно, північ
  final DateTime end; // не включно, північ

  factory Period.of(PeriodKind kind, DateTime anchor) {
    final d = DateTime(anchor.year, anchor.month, anchor.day);
    switch (kind) {
      case PeriodKind.week:
        final monday = d.subtract(Duration(days: d.weekday - DateTime.monday));
        return Period._(kind, monday, _addDays(monday, 7));
      case PeriodKind.month:
        return Period._(
          kind,
          DateTime(d.year, d.month),
          DateTime(d.year, d.month + 1),
        );
      case PeriodKind.year:
        return Period._(kind, DateTime(d.year), DateTime(d.year + 1));
      case PeriodKind.custom:
        return Period._(kind, d, _addDays(d, 1));
    }
  }

  /// Свій діапазон: обидві дати включно.
  factory Period.custom(DateTime first, DateTime last) {
    final a = DateTime(first.year, first.month, first.day);
    final b = DateTime(last.year, last.month, last.day);
    return Period._(PeriodKind.custom, a, _addDays(b, 1));
  }

  /// Останній день періоду (включно).
  DateTime get lastDay => _addDays(end, -1);

  int get days => _daysBetween(start, end);

  bool contains(DateTime date) => !date.isBefore(start) && date.isBefore(end);

  bool get canShift => kind != PeriodKind.custom;

  /// Попередній (-1) або наступний (+1) період того ж типу.
  Period shift(int step) {
    switch (kind) {
      case PeriodKind.week:
        return Period.of(kind, _addDays(start, 7 * step));
      case PeriodKind.month:
        return Period.of(kind, DateTime(start.year, start.month + step));
      case PeriodKind.year:
        return Period.of(kind, DateTime(start.year + step));
      case PeriodKind.custom:
        return this;
    }
  }

  String get label {
    switch (kind) {
      case PeriodKind.week:
        return _rangeLabel(start, lastDay);
      case PeriodKind.month:
        final m = DateFormat('LLLL y', 'uk').format(start);
        return m[0].toUpperCase() + m.substring(1);
      case PeriodKind.year:
        return '${start.year}';
      case PeriodKind.custom:
        return _rangeLabel(start, lastDay);
    }
  }

  static String _rangeLabel(DateTime a, DateTime b) {
    if (a == b) return DateFormat('d MMMM y', 'uk').format(a);
    if (a.year == b.year && a.month == b.month) {
      return '${a.day}–${DateFormat('d MMMM y', 'uk').format(b)}';
    }
    if (a.year == b.year) {
      return '${DateFormat('d MMM', 'uk').format(a)} – ${DateFormat('d MMM y', 'uk').format(b)}';
    }
    return '${DateFormat('d MMM y', 'uk').format(a)} – ${DateFormat('d MMM y', 'uk').format(b)}';
  }

  @override
  bool operator ==(Object other) =>
      other is Period &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);
}

/// Додає дні календарно (стійко до переходу на літній / зимовий час).
DateTime _addDays(DateTime d, int days) =>
    DateTime(d.year, d.month, d.day + days);

int _daysBetween(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

DateTime addDays(DateTime d, int days) => _addDays(d, days);
int daysBetween(DateTime a, DateTime b) => _daysBetween(a, b);
