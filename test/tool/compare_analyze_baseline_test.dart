import '../../tool/compare_analyze_baseline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const baseline = '''info - First message - lib\\a.dart:1:1 - rule_one
warning - Second message - lib\\b.dart:2:1 - rule_two''';
  test('accepts the same diagnostic tuples in a different order', () {
    const current = '''warning - Second message - lib\\b.dart:2:1 - rule_two
info - First message - lib\\a.dart:1:1 - rule_one''';
    expect(compareAnalyzeReports(baseline, current), 0);
  });
  test('rejects a changed message under an existing rule', () {
    const current = 'info - Changed message - lib\\a.dart:1:1 - rule_one';
    expect(compareAnalyzeReports(baseline, current), isNot(0));
  });
  test('rejects a report over the maximum total', () {
    const current = '''info - First message - lib\\a.dart:1:1 - rule_one
warning - Second message - lib\\b.dart:2:1 - rule_two''';
    expect(compareAnalyzeReports(baseline, current, maximumTotal: 1), isNot(0));
  });
}
