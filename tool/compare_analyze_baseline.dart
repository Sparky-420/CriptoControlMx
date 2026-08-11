import 'dart:io';

int compareAnalyzeReports(
  String baselineMarkdown,
  String currentOutput, {
  int maximumTotal = 30,
  Map<String, String>? sources,
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
  if (!_same(expected, actual)) {
    return 1;
  }
  if (sources != null &&
      !_anchorsMatch(baselineMarkdown, currentOutput, sources)) {
    return 1;
  }
  return 0;
}

bool _anchorsMatch(
  String markdown,
  String currentOutput,
  Map<String, String> sources,
) {
  final anchors = RegExp(
    r'\|\s*`([^`]+)`\s*\|\s*$',
    multiLine: true,
  ).allMatches(markdown).map((m) => m.group(1)!).toList();
  if (anchors.isEmpty) return true;
  final locations = RegExp(
    r'^\s*(?:info|warning|error) - .+ - (.+):(\d+):\d+ - [\w_]+\s*$',
    multiLine: true,
  ).allMatches(currentOutput).toList();
  if (locations.length < anchors.length) return false;
  for (var i = 0; i < anchors.length; i++) {
    final source = sources[locations[i].group(1)!.replaceAll('\\', '/')];
    final line = int.parse(locations[i].group(2)!);
    if (source == null ||
        line < 1 ||
        line > source.split('\n').length ||
        !source.split('\n')[line - 1].contains(anchors[i])) {
      return false;
    }
  }
  return true;
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
  final root = Directory.current;
  final result = compareAnalyzeReports(
    File(args[0]).readAsStringSync(),
    File(args[1]).readAsStringSync(),
    sources: <String, String>{
      'lib/cripto_control_app.dart': File(
        '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}cripto_control_app.dart',
      ).readAsStringSync(),
    },
  );
  if (result != 0) {
    stderr.writeln('Analyzer report differs from approved baseline.');
  }
  exitCode = result;
}
