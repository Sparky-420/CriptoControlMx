import 'dart:io';

int compareAnalyzeReports(
  String baselineMarkdown,
  String currentOutput, {
  int maximumTotal = 30,
}) {
  final baseline = _baselineTuples(baselineMarkdown);
  final current = _currentTuples(currentOutput);
  if (current.length > maximumTotal || baseline.length != current.length) {
    return 1;
  }
  final expected = <String, int>{};
  final actual = <String, int>{};
  for (final value in baseline) {
    expected[value] = (expected[value] ?? 0) + 1;
  }
  for (final value in current) {
    actual[value] = (actual[value] ?? 0) + 1;
  }
  return _same(expected, actual) ? 0 : 1;
}

bool _same(Map<String, int> a, Map<String, int> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] == e.value);
List<String> _currentTuples(String input) {
  final r = RegExp(
    r'^\s*(info|warning|error) - (.+) - (.+):(\d+):(\d+) - ([\w_]+)\s*$',
    multiLine: true,
  );
  return r
      .allMatches(input)
      .map((m) => '${m[1]}|${m[3]!.replaceAll('\\', '/')}|${m[6]}|${m[2]}')
      .toList();
}

List<String> _baselineTuples(String input) {
  final diagnostics = _currentTuples(input);
  if (diagnostics.isNotEmpty) {
    return diagnostics;
  }
  final r = RegExp(
    r'^\|\s*\d+\s*\|\s*(info|warning|error)\s*\|[^|]*\|\s*`?([\w_]+)`?\s*\|\s*(.+?)\s*\|\s*$',
    multiLine: true,
  );
  return r.allMatches(input).map((m) => '${m[1]}||${m[2]}|${m[3]}').toList();
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/compare_analyze_baseline.dart <baseline.md> <analyze.txt>',
    );
    exitCode = 64;
    return;
  }
  final result = compareAnalyzeReports(
    File(args[0]).readAsStringSync(),
    File(args[1]).readAsStringSync(),
  );
  if (result != 0) {
    stderr.writeln('Analyzer report differs from approved baseline.');
  }
  exitCode = result;
}
