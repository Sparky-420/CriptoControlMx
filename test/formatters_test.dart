import 'package:flutter_test/flutter_test.dart';
import 'package:cripto_control_mx/shared/formatters.dart';

void main() {
  test('money and percentage formatters remain stable', () {
    expect(money(1234.567), r'$1234.57 MXN');
    expect(moneyShort(1234.567), r'$1235');
    expect(pct(-12.3456), '-12.35%');
    expect(fixed(1.23456, 3), '1.235');
  });

  test('crypto and compact formatters remain stable', () {
    expect(crypto(0.123456789), '0.12345679');
    expect(compact(1.23000000), '1.23');
    expect(compact(1.00000000), '1');
  });

  test('date formatters remain stable', () {
    final DateTime date = DateTime(2026, 6, 17, 9, 5);

    expect(shortDate(date), '17/06/2026');
    expect(longDate(date), '17/06/2026 09:05');
    expect(isoDate(date), '2026-06-17');
    expect(dateOnly(date), DateTime(2026, 6, 17));
  });

  test('csvEscape keeps CSV output compatible', () {
    expect(csvEscape('plain'), 'plain');
    expect(csvEscape('a,b'), '"a,b"');
    expect(csvEscape('a"b'), '"a""b"');
  });
}
