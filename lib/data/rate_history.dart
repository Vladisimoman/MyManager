import '../core/money.dart';
import 'database.dart';

/// Курси за минулі дні (етап 10): записи перераховуються в EUR за курсом своєї дати.
/// Якщо курсу на дату немає (ще не завантажено, вихідні без даних тощо) —
/// беремо найближчий попередній день у межах [maxGapDays], інакше — поточний курс.
class RateHistory {
  RateHistory(Iterable<HistoricalRate> rows) {
    for (final r in rows) {
      if (r.perEur <= 0) continue;
      (_byCurrency[r.currency] ??= []).add((r.day, r.perEur));
    }
    for (final list in _byCurrency.values) {
      list.sort((a, b) => a.$1.compareTo(b.$1));
    }
  }

  static final empty = RateHistory(const []);

  /// Вихідні й свята: ЄЦБ не публікує курс, тож дивимось кілька днів назад.
  static const maxGapDays = 7;

  final _byCurrency = <String, List<(String, double)>>{};

  bool get isEmpty => _byCurrency.isEmpty;

  /// Одиниць валюти за 1 EUR на дату [date]; null — немає даних поблизу.
  double? perEurAt(String currency, DateTime date) {
    final list = _byCurrency[currency];
    if (list == null || list.isEmpty) return null;
    final key = isoDay(date);
    // Останній день ≤ date (двійковий пошук).
    var lo = 0, hi = list.length - 1, found = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (list[mid].$1.compareTo(key) <= 0) {
        found = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    if (found < 0) return null;
    final gap = DateTime.parse(key).difference(DateTime.parse(list[found].$1)).inDays;
    return gap <= maxGapDays ? list[found].$2 : null;
  }

  bool covers(String currency, DateTime date) => perEurAt(currency, date) != null;
}

String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Перерахунок між валютами через EUR за курсом дати [date] (або поточним).
/// null — немає курсу однієї з валют.
int? convertCentsOn(
  int cents,
  String from,
  String to,
  DateTime date,
  Map<String, ExchangeRate> rates,
  RateHistory? history,
) {
  if (from == to) return cents;
  final eur = toEurCentsOn(cents, from, date, rates, history);
  if (eur == null) return null;
  if (to == baseCurrency) return eur;
  final perEur = history?.perEurAt(to, date) ?? rates[to]?.perEur;
  if (perEur == null || perEur <= 0) return null;
  return (eur * perEur).round();
}

/// Сума у валюті → центи EUR за курсом дати [date] (або поточним, якщо курсу на дату немає).
/// null — курсу немає зовсім.
int? toEurCentsOn(
  int amountCents,
  String currency,
  DateTime date,
  Map<String, ExchangeRate> rates,
  RateHistory? history,
) {
  if (currency == baseCurrency) return amountCents;
  final perEur = history?.perEurAt(currency, date) ?? rates[currency]?.perEur;
  if (perEur == null || perEur <= 0) return null;
  return (amountCents / perEur).round();
}
