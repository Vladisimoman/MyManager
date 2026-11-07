import 'package:intl/intl.dart';

/// Основна валюта: у ній показується загальний баланс.
const baseCurrency = 'EUR';

/// Стартовий набір валют (до етапу 7 — єдиний; тепер — швидкий вибір).
const currencies = ['EUR', 'UAH', 'USD'];

/// Фіатні валюти, які можна додати в гаманець (курси є в ЄЦБ або НБУ).
const fiatCurrencies = <String, String>{
  'EUR': 'Євро',
  'USD': 'Долар США',
  'UAH': 'Гривня',
  'PLN': 'Польський злотий',
  'GBP': 'Фунт стерлінгів',
  'CHF': 'Швейцарський франк',
  'CZK': 'Чеська крона',
  'HUF': 'Угорський форинт',
  'RON': 'Румунський лей',
  'SEK': 'Шведська крона',
  'NOK': 'Норвезька крона',
  'DKK': 'Данська крона',
  'TRY': 'Турецька ліра',
  'GEL': 'Грузинський ларі',
  'MDL': 'Молдовський лей',
  'KZT': 'Казахстанський теньге',
  'ILS': 'Ізраїльський шекель',
  'CAD': 'Канадський долар',
  'AUD': 'Австралійський долар',
  'JPY': 'Японська єна',
  'CNY': 'Китайський юань',
};

bool isFiat(String code) => fiatCurrencies.containsKey(code);

const _symbols = {
  'EUR': '€',
  'UAH': '₴',
  'USD': '\$',
  'PLN': 'zł',
  'GBP': '£',
  'TRY': '₺',
  'GEL': '₾',
  'KZT': '₸',
  'ILS': '₪',
  'JPY': '¥',
  'CNY': 'CN¥',
  'CAD': 'C\$',
  'AUD': 'A\$',
};

String currencySymbol(String code) => _symbols[code] ?? code;

/// Форматує суму в центах: `1234,50 €`.
/// [sign]: +1 додає «+ », -1 додає «− », 0 — без знака (від'ємне число отримує «−»).
String formatMoney(int cents, String currency, {int sign = 0}) {
  final f = NumberFormat.currency(
    locale: 'uk',
    symbol: currencySymbol(currency),
    decimalDigits: 2,
  );
  final body = f.format(cents.abs() / 100);
  if (sign > 0) return '+ $body';
  if (sign < 0 || cents < 0) return '− $body';
  return body;
}

/// Перетворює введений текст на центи. Приймає кому або крапку,
/// пробіли, не більше двох знаків після коми. Повертає null, якщо текст некоректний.
int? parseAmountToCents(String input) {
  final s = input.replaceAll(RegExp(r'[\s ]'), '').replaceAll(',', '.');
  if (!RegExp(r'^\d{1,10}(\.\d{0,2})?$').hasMatch(s)) return null;
  final parts = s.split('.');
  final whole = int.parse(parts[0]);
  final frac = (parts.length > 1 ? parts[1] : '').padRight(2, '0');
  return whole * 100 + int.parse(frac);
}

/// Центи → текст для поля вводу: `12,5` → `12,50`.
String centsToInput(int cents) {
  final whole = cents ~/ 100;
  final frac = (cents % 100).toString().padLeft(2, '0');
  return '$whole,$frac';
}

/// Як [parseAmountToCents], але дозволяє мінус на початку (для початкового балансу).
int? parseSignedAmountToCents(String input) {
  final t = input.trim();
  final negative = t.startsWith('-') || t.startsWith('−');
  final cents = parseAmountToCents(negative ? t.substring(1) : t);
  if (cents == null) return null;
  return negative ? -cents : cents;
}

/// Центи → текст для поля вводу зі знаком: `-1250` → `-12,50`.
String signedCentsToInput(int cents) =>
    cents < 0 ? '-${centsToInput(-cents)}' : centsToInput(cents);
