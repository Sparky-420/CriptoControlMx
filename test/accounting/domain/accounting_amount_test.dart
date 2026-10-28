import 'package:cripto_control_mx/accounting/domain/accounting_amount.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('keeps Mercado Pago quantities exact through arithmetic and JSON', () {
    final received = AccountingAmount.parse('1');
    final fee = AccountingAmount.parse('0.00167532');
    final observed = AccountingAmount.parse('127.75883985');

    expect((received + fee).toJson(), '1.00167532');
    expect(AccountingAmount.parse(observed.toJson()), observed);
  });

  test('normalizes, compares, and rejects non-decimal input', () {
    final amount = AccountingAmount.parse('001.2300');
    expect(amount.toJson(), '1.23');
    expect(
      amount - AccountingAmount.parse('0.23'),
      AccountingAmount.fromInt(1),
    );
    expect(
      amount * AccountingAmount.parse('2'),
      AccountingAmount.parse('2.46'),
    );
    expect(
      AccountingAmount.parse(
        '1',
      ).divide(AccountingAmount.parse('8'), scale: 4).toJson(),
      '0.125',
    );
    expect(amount.min(AccountingAmount.parse('1.24')).toJson(), '1.23');
    expect(amount.max(AccountingAmount.parse('1.24')).toJson(), '1.24');
    expect(AccountingAmount.zero.toJson(), '0');
    expect(() => AccountingAmount.parse('1e3'), throwsFormatException);
    expect(() => AccountingAmount.parse('--1'), throwsFormatException);
  });

  test(
    'divides decimal amounts across mixed scales with truncation toward zero',
    () {
      expect(
        AccountingAmount.parse(
          '0.5',
        ).divide(AccountingAmount.parse('2')).toJson(),
        '0.25',
      );
      expect(
        AccountingAmount.parse(
          '1.25',
        ).divide(AccountingAmount.parse('0.5')).toJson(),
        '2.5',
      );
      expect(
        AccountingAmount.parse(
          '-0.5',
        ).divide(AccountingAmount.parse('2')).toJson(),
        '-0.25',
      );
      expect(
        AccountingAmount.parse(
          '0.00000000000000000001',
        ).divide(AccountingAmount.parse('2')).toJson(),
        '0',
      );
    },
  );

  test('division handles signs zero requested scale and argument errors', () {
    expect(
      AccountingAmount.parse('1').divide(AccountingAmount.parse('-2')).toJson(),
      '-0.5',
    );
    expect(
      AccountingAmount.parse(
        '-1',
      ).divide(AccountingAmount.parse('-2')).toJson(),
      '0.5',
    );
    expect(
      AccountingAmount.zero.divide(AccountingAmount.parse('-2')),
      AccountingAmount.zero,
    );
    expect(
      AccountingAmount.parse(
        '5',
      ).divide(AccountingAmount.parse('2'), scale: 0).toJson(),
      '2',
    );
    expect(
      () => AccountingAmount.fromInt(1).divide(AccountingAmount.zero),
      throwsArgumentError,
    );
    expect(
      () => AccountingAmount.fromInt(
        1,
      ).divide(AccountingAmount.fromInt(2), scale: -1),
      throwsArgumentError,
    );
  });
}
