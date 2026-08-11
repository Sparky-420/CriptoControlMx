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

  test('binds an anchor to the current diagnostic line', () {
    const anchoredBaseline = '''info - Same message - lib\\a.dart:1:1 - rule_one

### Huella con anclas verificables
| # | Severidad | Posición | Regla | Mensaje | Ancla fuente |
| 1 | info | 1:1 | `rule_one` | M1 | `approvedAnchor();` |''';
    const moved = 'info - Same message - lib\\a.dart:3:1 - rule_one';
    const sources = <String, String>{
      'lib/a.dart': 'other();\n\napprovedAnchor();',
    };
    expect(compareAnalyzeReports(anchoredBaseline, moved, sources: sources), 0);
    const substituted = 'info - Same message - lib\\a.dart:1:1 - rule_one';
    expect(
      compareAnalyzeReports(anchoredBaseline, substituted, sources: sources),
      isNot(0),
    );
  });
}
