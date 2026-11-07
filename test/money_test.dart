import 'package:flutter_test/flutter_test.dart';
import 'package:my_manager/core/money.dart';

void main() {
  group('parseAmountToCents', () {
    test('приймає кому, крапку й пробіли', () {
      expect(parseAmountToCents('12'), 1200);
      expect(parseAmountToCents('12,5'), 1250);
      expect(parseAmountToCents('12.05'), 1205);
      expect(parseAmountToCents('1 234,99'), 123499);
      expect(parseAmountToCents('0,01'), 1);
      expect(parseAmountToCents('7,'), 700);
    });

    test('відкидає некоректне', () {
      expect(parseAmountToCents(''), isNull);
      expect(parseAmountToCents('abc'), isNull);
      expect(parseAmountToCents('1,234'), isNull); // три знаки після коми
      expect(parseAmountToCents('-5'), isNull);
      expect(parseAmountToCents('1.2.3'), isNull);
    });
  });

  test('centsToInput повертає формат для поля вводу', () {
    expect(centsToInput(1250), '12,50');
    expect(centsToInput(5), '0,05');
  });

  test('formatMoney: символ валюти та знак', () {
    String norm(String s) => s.replaceAll(RegExp(r'[  ]'), ' ');
    expect(norm(formatMoney(123450, 'EUR')), '1 234,50 €');
    expect(norm(formatMoney(500, 'USD', sign: 1)), '+ 5,00 \$');
    expect(norm(formatMoney(500, 'UAH', sign: -1)), '− 5,00 ₴');
    expect(norm(formatMoney(-250, 'EUR')), '− 2,50 €');
  });

  test('початковий баланс може бути з мінусом', () {
    expect(parseSignedAmountToCents('-150'), -15000);
    expect(parseSignedAmountToCents('−12,5'), -1250);
    expect(parseSignedAmountToCents(' 200 '), 20000);
    expect(parseSignedAmountToCents('--1'), isNull);
    expect(signedCentsToInput(-1250), '-12,50');
    expect(signedCentsToInput(500), '5,00');
  });
}
