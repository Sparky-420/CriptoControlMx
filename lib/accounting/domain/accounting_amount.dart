final class AccountingAmount implements Comparable<AccountingAmount> {
  const AccountingAmount._(this.coefficient, this.scale);

  final BigInt coefficient;
  final int scale;

  static final AccountingAmount zero = AccountingAmount.fromInt(0);

  static AccountingAmount fromInt(int value) =>
      AccountingAmount._(BigInt.from(value), 0);

  static AccountingAmount parse(String value) {
    final Match? match = RegExp(
      r'^([+-]?)(\d+)(?:\.(\d+))?$',
    ).firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid decimal amount: $value');
    }

    final String sign = match.group(1) == '-' ? '-' : '';
    final String whole = match.group(2)!;
    final String fraction = match.group(3) ?? '';
    return _normalize(BigInt.parse('$sign$whole$fraction'), fraction.length);
  }

  static AccountingAmount _normalize(BigInt coefficient, int scale) {
    while (scale > 0 && coefficient.remainder(BigInt.from(10)) == BigInt.zero) {
      coefficient ~/= BigInt.from(10);
      scale--;
    }
    return AccountingAmount._(coefficient, scale);
  }

  AccountingAmount operator +(AccountingAmount other) {
    final int commonScale = scale > other.scale ? scale : other.scale;
    final BigInt left = coefficient * BigInt.from(10).pow(commonScale - scale);
    final BigInt right =
        other.coefficient * BigInt.from(10).pow(commonScale - other.scale);
    return _normalize(left + right, commonScale);
  }

  AccountingAmount operator -(AccountingAmount other) =>
      this + AccountingAmount._(-other.coefficient, other.scale);

  AccountingAmount operator *(AccountingAmount other) =>
      _normalize(coefficient * other.coefficient, scale + other.scale);

  AccountingAmount divide(AccountingAmount other, {int scale = 18}) {
    if (other.coefficient == BigInt.zero) {
      throw ArgumentError.value(other, 'other', 'Cannot divide by zero');
    }
    if (scale < 0) {
      throw ArgumentError.value(scale, 'scale', 'Must not be negative');
    }
    final exponent = other.scale + scale - this.scale;
    final BigInt numerator;
    final BigInt denominator;
    if (exponent >= 0) {
      numerator = coefficient * BigInt.from(10).pow(exponent);
      denominator = other.coefficient;
    } else {
      numerator = coefficient;
      denominator = other.coefficient * BigInt.from(10).pow(-exponent);
    }
    return _normalize(numerator ~/ denominator, scale);
  }

  AccountingAmount min(AccountingAmount other) =>
      compareTo(other) <= 0 ? this : other;

  AccountingAmount max(AccountingAmount other) =>
      compareTo(other) >= 0 ? this : other;

  @override
  int compareTo(AccountingAmount other) {
    final int commonScale = scale > other.scale ? scale : other.scale;
    final BigInt left = coefficient * BigInt.from(10).pow(commonScale - scale);
    final BigInt right =
        other.coefficient * BigInt.from(10).pow(commonScale - other.scale);
    return left.compareTo(right);
  }

  String toJson() {
    final String raw = coefficient.abs().toString().padLeft(scale + 1, '0');
    final String sign = coefficient.isNegative ? '-' : '';
    if (scale == 0) {
      return '$sign$raw';
    }
    final int wholeLength = raw.length - scale;
    return '$sign${raw.substring(0, wholeLength)}.${raw.substring(wholeLength)}';
  }

  @override
  bool operator ==(Object other) =>
      other is AccountingAmount &&
      coefficient == other.coefficient &&
      scale == other.scale;

  @override
  int get hashCode => Object.hash(coefficient, scale);
}

final class AccountingTolerance {
  const AccountingTolerance._();

  static final AccountingAmount legacyImport = AccountingAmount.parse(
    '0.00000001',
  );
}
